import 'dart:convert';

import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/consistency_check/item_id_rules.dart';
import 'package:specstone_core/src/consistency_check/scenario_blocks.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart' show withKeyBlock;
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/document_writing/key_block_values.dart';
import 'package:specstone_core/src/index_query/banned_matches.dart'
    show SearchLine, codeSpansOf;
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/link_scan.dart';
import 'package:specstone_core/src/journeys/journey_steps.dart';
import 'package:specstone_core/src/rendering/formatter.dart' show layOutDoc;
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

// MARK: - Constants

const _gnfrType = 'gnfr';
const _tracedFromKey = 'traced_from';
const _overridesKey = 'overrides';
const _confirmedKey = 'confirmed';
const _scenarioRefPrefix = 'S';
const _statementPrefix = '- **Statement:**';
const _docsPrefix = 'docs/';
const _planLabel = 'renumber ids: ';
const _referencesLabel = '; references: ';
const _lineFeed = 0x0A;
final _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

// MARK: - Types

/// One lettered ID of a doc and the number the pass gives it.
typedef _Lettered = ({String docPath, IdAt item, String from, String to});

/// A renumbering a reference names: the renumbered doc and its ID's change.
typedef _Named = ({String docPath, String from, String to});

/// A `confirmed` entry's fingerprint before the pass and the one a matched
/// entry records.
typedef _Stamp = ({String before, String after});

/// The stamps of the run, keyed by the renumbered doc and its old ID.
typedef _Stamps = Map<(String, String), _Stamp>;

/// A link or code span opening at column `at` of a line, and the DocPaths
/// it cites: empty for a doc address that names no doc of the run.
typedef _Citation = ({int at, List<String> docPaths});

/// A rewritten doc and whether it rewrote a reference to another doc's ID.
typedef _Rewrite = ({String lf, bool citesOthers});

// MARK: - RenumberPass

/// The one-time pass of a pack upgrade that renumbers each lettered item ID
/// and scenario number (`doc_model` RULE-12, apply_steps_and_pins E18, E19).
///
/// It reads IDs and next numbers as `check` does, so each new number is the
/// `next` its `item_id_lettered` finding named.
final class RenumberPass {
  new _(this._docs, this._index) : renumberings = _index.renumberings;

  /// Plans the pass over every typed doc of the run: planned DocPath, LF
  /// text, merged doc type.
  factory plan(List<({String docPath, String lf, MergedDocType type})> docs) {
    final runDocs = [
      for (final doc in docs) _RunDoc(doc.docPath, doc.lf, doc.type),
    ]..sort((a, b) => compareCodePoints(a.docPath, b.docPath));
    return RenumberPass._({
      for (final doc in runDocs) doc.docPath: doc,
    }, _IdIndex(runDocs));
  }

  final Map<String, _RunDoc> _docs;
  final _IdIndex _index;

  /// Each renumbering, in tree then document order.
  final List<({String docPath, String from, String to})> renumberings;

  late final _Stamps _stamps = _stampsOf();

  late final Map<String, _Rewrite> _rewrites = {
    for (final doc in _docs.values) doc.docPath: _rewriteOf(doc, _stamps),
  };

  /// Returns the doc at [docPath] with its renumbered IDs and every reference
  /// to one rewritten, each matched `confirmed` fingerprint carried over.
  ///
  /// A doc the pass was not planned over comes back as given.
  String apply(String docPath, String lf) {
    final doc = _docs[docPath];
    if (doc == null || renumberings.isEmpty) return lf;
    if (lf == doc.lf) return _rewrites[docPath]?.lf ?? lf;
    return _rewriteOf(_RunDoc(docPath, lf, doc.type), _stamps).lf;
  }

  /// The `renumber ids:` plan line, or null when nothing renumbers.
  String? get planLine {
    if (renumberings.isEmpty) return null;
    final ids = [
      for (final (:docPath, :from, :to) in renumberings)
        '$docPath $from -> $to',
    ].join(', ');
    final references = [
      for (final MapEntry(key: docPath, value: rewrite) in _rewrites.entries)
        if (rewrite.citesOthers) docPath,
    ];
    if (references.isEmpty) return '$_planLabel$ids';
    return '$_planLabel$ids$_referencesLabel${references.join(', ')}';
  }

  // MARK: - Stamps

  /// The fingerprints of each renumbered block a `confirmed` entry tracks.
  ///
  /// The new fingerprint reads the doc's final text, laid out as `format`
  /// lays it out, so the first `check` after the run matches it (R60).
  _Stamps _stampsOf() {
    final stamps = <(String, String), _Stamp>{};
    for (final doc in _docs.values) {
      final tracked = [
        for (final lettered in doc.lettered)
          if (_isTracked(doc, lettered)) lettered,
      ];
      if (tracked.isEmpty) continue;
      final finalText = layOutDoc(_rewriteOf(doc, const {}).lf, doc.type);
      final finalDoc = _RunDoc(doc.docPath, finalText, doc.type);
      for (final lettered in tracked) {
        stamps[(doc.docPath, lettered.from)] = (
          before: fingerprintOf(_letteredBlock(doc, lettered.item)),
          after: fingerprintOf(_renumberedBlock(finalDoc, lettered)),
        );
      }
    }
    return stamps;
  }

  /// Whether a link tracks [lettered]: a scenario, or a `gnfr` NFR.
  static bool _isTracked(_RunDoc doc, _Lettered lettered) =>
      lettered.item.prefix == scenarioIdPrefix || doc.type.id == _gnfrType;

  /// The text a link fingerprints of the lettered [item], read from its line
  /// span (P5): a scenario's block, an NFR's Statement line.
  static String _letteredBlock(_RunDoc doc, IdAt item) {
    if (item.prefix != scenarioIdPrefix) return doc.statementOf(item);
    return doc.lines.sublist(item.line - 1, item.endLine).join('\n');
  }

  static String _renumberedBlock(_RunDoc finalDoc, _Lettered lettered) {
    if (lettered.item.prefix == scenarioIdPrefix) {
      return finalDoc.scenarioBlocks[_scenarioRefOf(lettered.to)] ?? '';
    }
    final item = finalDoc.items
        .where((item) => item.id?.written == lettered.to)
        .firstOrNull;
    return item == null ? '' : finalDoc.statementOf(item);
  }

  // MARK: - Rewrite

  _Rewrite _rewriteOf(_RunDoc doc, _Stamps stamps) {
    if (!_index.mayName(doc.lf)) return (lf: doc.lf, citesOthers: false);
    final lines = [...doc.lines];
    final body = _BodyRewrite(doc, _index, lines);
    final citesInBody = body.rewriteTokens();
    final rewritesSteps = body.rewriteSteps();
    final bodyText = lines.join('\n');
    final lf = _withEntriesRewritten(bodyText, doc, stamps);
    return (
      lf: lf,
      citesOthers: citesInBody || rewritesSteps || lf != bodyText,
    );
  }

  /// Returns [lf] with each `traced_from`, `overrides`, and `confirmed` value
  /// naming a renumbered scenario or NFR set to its new number.
  String _withEntriesRewritten(String lf, _RunDoc doc, _Stamps stamps) {
    final ownStory = _index.parentStoryOf[doc.docPath];
    String? renamed(String label) =>
        _index.renamedLabel(label, ownStory: ownStory)?.label;
    var text = _withBlockValues(lf, _tracedFromKey, renamed);
    text = _withBlockValues(text, _overridesKey, renamed);
    final confirmed = _ConfirmedRenamer((label) {
      final named = _index.renamedLabel(label, ownStory: ownStory);
      if (named == null) return null;
      return (label: named.label, stamp: stamps[(named.docPath, named.from)]);
    });
    return _withBlockValues(text, _confirmedKey, confirmed.call);
  }

  static String _withBlockValues(
    String lf,
    String name,
    String? Function(String value) rename,
  ) {
    final block = Doc.parse(lf).frontmatter
        ?.where((candidate) => candidate.name == name)
        .firstOrNull;
    if (block == null) return lf;
    final renamed = renameKeyBlockValues(block.text, block.key, rename);
    return renamed == block.text ? lf : withKeyBlock(lf, name, renamed);
  }
}

/// Returns the `S<N>` ref of the scenario ID [id], `Scenario <N>`; any other
/// ID as it is.
String _scenarioRefOf(String id) {
  if (!id.startsWith(scenarioIdPrefix)) return id;
  return '$_scenarioRefPrefix${id.substring(scenarioIdPrefix.length)}';
}

// MARK: - Run doc

/// One typed doc of the run, parsed once as `check` parses it.
final class _RunDoc {
  new(this.docPath, this.lf, this.type)
    : parsed = parseIndexedDoc(
        docPath: docPath,
        bytes: utf8.encode(lf),
        match: MatchedDocType(type),
      );

  final String docPath;
  final String lf;
  final MergedDocType type;
  final ParsedDoc parsed;

  DocContent get content => parsed.content;

  String get name => parsed.doc.name;

  late final List<String> lines = lf.split('\n');

  late final List<IdAt> items = idsInDoc(content, type);

  /// The doc's lettered IDs, each with the next free number of its prefix,
  /// counted as `check`'s `item_id_lettered` counts it (R61).
  late final List<_Lettered> lettered = _letteredOf();

  /// The `### Scenario <N>` blocks, keyed `S<N>`, as `check` reads them.
  late final Map<String, String> scenarioBlocks = _scenarioBlocksOf();

  bool get holdsScenarios =>
      type.sections.any((section) => section.id == acceptanceSectionId);

  /// The first unfenced `- **Statement:**` line of [item], trimmed, as
  /// `check` fingerprints an NFR; empty without one.
  String statementOf(IdAt item) {
    for (var line = item.line; line <= item.endLine; line++) {
      if (content.lineFacts.isFenced(line)) continue;
      final text = lines[line - 1].trim();
      if (text.startsWith(_statementPrefix)) return text;
    }
    return '';
  }

  List<_Lettered> _letteredOf() {
    final read = [
      for (final item in items)
        if (item.id case final id?) (item: item, id: id),
    ];
    final next = nextFreeIds([for (final entry in read) entry.id]);
    return [
      for (final (index, (:item, :id)) in read.indexed)
        if (id is LetteredId)
          if (next[index] case final to?)
            (docPath: docPath, item: item, from: id.written, to: to),
    ];
  }

  Map<String, String> _scenarioBlocksOf() {
    final index = heldSectionIndex(content, type, acceptanceSectionId);
    if (index == null) return const {};
    return scenarioBlocksIn(
      sectionBodyLines(content.sections, content.lineFacts, index),
    );
  }
}

// MARK: - ID index

/// What the run's renumberings and doc names resolve to.
final class _IdIndex {
  new(List<_RunDoc> docs)
    : _lettered = [for (final doc in docs) ...doc.lettered] {
    for (final doc in docs) {
      _docPaths.add(doc.docPath);
      (_byName[doc.name] ??= []).add(doc.docPath);
      (_byTypedName['${doc.type.id}:${doc.name}'] ??= []).add(doc.docPath);
      if (doc.holdsScenarios) {
        _storyPaths.putIfAbsent(doc.name, () => doc.docPath);
      }
    }
    for (final (:docPath, :item, :from, :to) in _lettered) {
      (_toByDoc[docPath] ??= {}).putIfAbsent(from, () => to);
      prefixes.add(item.prefix);
    }
    _indexNfrs(docs);
    _indexParentStories(docs);
  }

  final List<_Lettered> _lettered;
  final _docPaths = <String>{};
  final _byName = <String, List<String>>{};
  final _byTypedName = <String, List<String>>{};
  final _storyPaths = <String, String>{};
  final _toByDoc = <String, Map<String, String>>{};
  final _nfrPaths = <String, String>{};

  /// The prefixes of the renumbered IDs.
  final prefixes = <String>{};

  /// The Name of the story each doc under a story sits under, by DocPath.
  final parentStoryOf = <String, String>{};

  List<({String docPath, String from, String to})> get renumberings => [
    for (final (:docPath, item: _, :from, :to) in _lettered)
      (docPath: docPath, from: from, to: to),
  ];

  void _indexNfrs(List<_RunDoc> docs) {
    for (final doc in docs) {
      if (doc.type.id != _gnfrType) continue;
      for (final lettered in doc.lettered) {
        _nfrPaths.putIfAbsent(lettered.from, () => doc.docPath);
      }
    }
  }

  /// Gives each doc whose type has a parent the story with the longest Name
  /// that opens the doc's Name.
  void _indexParentStories(List<_RunDoc> docs) {
    for (final doc in docs) {
      if (doc.type.parent == null) continue;
      String? parent;
      for (final name in _storyPaths.keys) {
        final isLonger = name.length > (parent?.length ?? -1);
        if (isLonger && doc.name.startsWith('$name/')) parent = name;
      }
      if (parent != null) parentStoryOf[doc.docPath] = parent;
    }
  }

  /// Whether [lf] holds the text of any renumbered ID or scenario ref.
  bool mayName(String lf) => _lettered.any(
    (lettered) =>
        lf.contains(lettered.from) ||
        lf.contains(_scenarioRefOf(lettered.from)),
  );

  /// The new ID of [from] in the doc at [docPath], or null.
  String? toOf(String docPath, String from) => _toByDoc[docPath]?[from];

  /// Returns [label], a scenario ref or an NFR ID, with its new number; null
  /// when it names no renumbered item. An `S<N>` ref names a scenario of
  /// [ownStory].
  ({String label, String docPath, String from})? renamedLabel(
    String label, {
    required String? ownStory,
  }) {
    if (readScenarioRef(label) case final ref?) {
      final storyName = ref.storyName;
      final named = scenarioOf(storyName ?? ownStory, ref.number);
      if (named == null) return null;
      final number = _scenarioRefOf(named.to);
      return (
        label: storyName == null ? number : '$storyName#$number',
        docPath: named.docPath,
        from: named.from,
      );
    }
    final docPath = _nfrPaths[label];
    final to = docPath == null ? null : toOf(docPath, label);
    if (docPath == null || to == null) return null;
    return (label: to, docPath: docPath, from: label);
  }

  /// The renumbering of scenario [number] of the story named [storyName].
  _Named? scenarioOf(String? storyName, IdRead number) {
    final docPath = storyName == null ? null : _storyPaths[storyName];
    if (docPath == null) return null;
    final digits = number.written.substring(number.prefix.length);
    final from = '$scenarioIdPrefix$digits';
    final to = toOf(docPath, from);
    return to == null ? null : (docPath: docPath, from: from, to: to);
  }

  /// The docs the code span text [text] in the doc at [fromPath] cites: a
  /// Name, `<doc type>:<Name>`, or a path that resolves (RULE-11); empty for
  /// a doc address naming no doc of the run; null when it cites no doc.
  List<String>? citedBySpan(String text, String fromPath) {
    final address = readDocAddress(text);
    if (address.isName) {
      final typeId = address.typeId;
      final named = typeId == null
          ? _byName[address.body]
          : _byTypedName['$typeId:${address.body}'];
      if (named != null) return named;
      return address.isReferenceWithoutLookup ? const [] : null;
    }
    if (address.typeId != null) return null;
    final docPath = docAtPath(address.body, fromPath);
    return docPath == null ? null : [docPath];
  }

  /// The doc of the run [path] reaches from the doc at [fromPath], as a link
  /// would, else read as a DocPath; null when none.
  String? docAtPath(String path, String fromPath) {
    if (resolveDocLink(path, fromPath) case DocTarget(:final docPath)
        when _docPaths.contains(docPath)) {
      return docPath;
    }
    if (_docPaths.contains(path)) return path;
    if (!path.startsWith(_docsPrefix)) return null;
    final docPath = path.substring(_docsPrefix.length);
    return _docPaths.contains(docPath) ? docPath : null;
  }
}

// MARK: - Body rewrite

/// Rewrites the body lines of one doc, [_lines], in place.
final class _BodyRewrite {
  new(this._doc, this._index, this._lines)
    : _body = Doc.parse(_doc.lf).afterFrontmatter;

  final _RunDoc _doc;
  final _IdIndex _index;
  final List<String> _lines;
  final String _body;

  /// The index in [_lines] of the first line past the frontmatter.
  late final int _firstLine = '\n'
      .allMatches(_doc.lf.substring(0, _doc.lf.length - _body.length))
      .length;

  late final Map<int, List<_Citation>> _linkCitations = _linkCitationsOf();

  late final Map<int, _Lettered> _openers = {
    for (final lettered in _doc.lettered) lettered.item.line: lettered,
  };

  /// Rewrites each item ID token outside fences and code spans that its
  /// doc renumbers: the doc of the nearest citation before it on its line,
  /// else this doc (R67). Returns whether a token of another doc changed.
  bool rewriteTokens() {
    var citesOthers = false;
    for (var index = _firstLine; index < _lines.length; index++) {
      final line = _lines[index];
      if (!_index.prefixes.any(line.contains)) continue;
      if (_doc.content.lineFacts.isFenced(index + 1)) continue;
      final (:text, :othersChanged) = _rewriteLine(line, index + 1);
      _lines[index] = text;
      citesOthers = citesOthers || othersChanged;
    }
    return citesOthers;
  }

  /// Sets each journey `step:` value naming a renumbered scenario to its new
  /// number; returns whether one changed.
  bool rewriteSteps() {
    if (_doc.type.id != journeyTypeId) return false;
    final content = _doc.content;
    final section = heldSectionIndex(content, _doc.type, stepsSectionId);
    if (section == null) return false;
    final body = sectionBodyLines(content.sections, content.lineFacts, section);
    final steps = readJourneySteps(
      body.map((line) => line.text).join('\n'),
      blockKinds: _doc.type.listedGenerators.toSet(),
    );
    var changed = false;
    for (final step in steps.steps) {
      final (value, index) = (step.stepValue, step.stepIndex);
      if (value == null || index == null) continue;
      changed = _rewriteStep(value, body[index].line - 1) || changed;
    }
    return changed;
  }

  bool _rewriteStep(String value, int lineIndex) {
    final ref = readStepTargetValue(value);
    if (ref == null) return false;
    final named = _index.scenarioOf(ref.storyName, ref.number);
    if (named == null) return false;
    final written = ref.number.written;
    final line = _lines[lineIndex];
    final at = line.lastIndexOf(written);
    _lines[lineIndex] = line.replaceRange(
      at,
      at + written.length,
      _scenarioRefOf(named.to),
    );
    return true;
  }

  ({String text, bool othersChanged}) _rewriteLine(String line, int fileLine) {
    final citations = [..._spanCitations(line), ...?_linkCitations[fileLine]]
      ..sort((a, b) => a.at - b.at);
    // An item's own start line takes its own number, so two items lettered
    // alike still get two numbers.
    var opener = _openers[fileLine];
    var othersChanged = false;
    final edits = <({int at, int end, String to})>[];
    for (final (:at, :written) in _tokensOf(SearchLine(line, fileLine).prose)) {
      final cited = _citedAt(citations, at) ?? [_doc.docPath];
      final named = _renumberingIn(cited, written);
      if (named == null) continue;
      final isOwn = named.docPath == _doc.docPath;
      var to = named.to;
      if (isOwn && opener != null && opener.from == written) {
        to = opener.to;
        opener = null;
      }
      othersChanged = othersChanged || !isOwn;
      edits.add((at: at, end: at + written.length, to: to));
    }
    var text = line;
    for (final (:at, :end, :to) in edits.reversed) {
      text = text.replaceRange(at, end, to);
    }
    return (text: text, othersChanged: othersChanged);
  }

  /// The renumbered ID tokens of [prose], in line order, none overlapping.
  List<({int at, String written})> _tokensOf(String prose) {
    final found = <({int at, String written})>[];
    for (final prefix in _index.prefixes) {
      var at = prose.indexOf(prefix);
      for (; at >= 0; at = prose.indexOf(prefix, at + 1)) {
        if (_isWordCharBefore(prose, at)) continue;
        final id = readItemId(prose.substring(at), prefix);
        if (id is! LetteredId) continue;
        if (_isWordCharAt(prose, at + id.written.length)) continue;
        found.add((at: at, written: id.written));
      }
    }
    found.sort((a, b) => a.at - b.at);
    final tokens = <({int at, String written})>[];
    for (final token in found) {
      final end = tokens.isEmpty
          ? 0
          : tokens.last.at + tokens.last.written.length;
      if (token.at >= end) tokens.add(token);
    }
    return tokens;
  }

  /// The renumbering of [written] in the first of [docPaths] that has one.
  _Named? _renumberingIn(List<String> docPaths, String written) {
    for (final docPath in docPaths) {
      if (_index.toOf(docPath, written) case final to?) {
        return (docPath: docPath, from: written, to: to);
      }
    }
    return null;
  }

  /// The DocPaths the nearest citation before column [at] names, or null
  /// when none precedes it.
  static List<String>? _citedAt(List<_Citation> citations, int at) {
    List<String>? cited;
    for (final citation in citations) {
      if (citation.at >= at) break;
      cited = citation.docPaths;
    }
    return cited;
  }

  List<_Citation> _spanCitations(String line) => [
    for (final (:start, :end, :ticks) in codeSpansOf(line))
      if (_index.citedBySpan(
            line.substring(start + ticks, end - ticks),
            _doc.docPath,
          )
          case final docPaths?)
        (at: start, docPaths: docPaths),
  ];

  /// The links to a doc of the run, by file line, each at its column.
  Map<int, List<_Citation>> _linkCitationsOf() {
    final lineStarts = [0];
    for (var i = 0; i < _body.length; i++) {
      if (_body.codeUnitAt(i) == _lineFeed) lineStarts.add(i + 1);
    }
    final citations = <int, List<_Citation>>{};
    final sources = linkSourcesOf(_body, firstLine: _firstLine + 1);
    for (final (:offset, :line, :shown) in sources) {
      final docPath = shown == null
          ? null
          : _index.docAtPath(shown, _doc.docPath);
      if (docPath == null) continue;
      final at = offset - lineStarts[line - 1 - _firstLine];
      (citations[line] ??= []).add((at: at, docPaths: [docPath]));
    }
    return citations;
  }
}

/// Whether the code point before [at] in [text] is a letter or digit.
bool _isWordCharBefore(String text, int at) {
  if (at == 0) return false;
  final isPair = at >= 2 && _isLowSurrogate(text.codeUnitAt(at - 1));
  return _wordChar.hasMatch(text.substring(at - (isPair ? 2 : 1), at));
}

/// Whether the code point at [at] in [text] is a letter or digit.
bool _isWordCharAt(String text, int at) {
  if (at >= text.length) return false;
  final isPair =
      at + 1 < text.length && _isLowSurrogate(text.codeUnitAt(at + 1));
  return _wordChar.hasMatch(text.substring(at, at + (isPair ? 2 : 1)));
}

bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

// MARK: - Confirmed entries

/// Renames the `confirmed` values [renameKeyBlockValues] passes one at a
/// time: a label, then its fingerprint, or both in one quoted value.
final class _ConfirmedRenamer {
  new(this._rename);

  final ({String label, _Stamp? stamp})? Function(String label) _rename;

  _Stamp? _pending;

  String? call(String value) {
    final pending = _pending;
    _pending = null;
    if (pending != null && value == pending.before) return pending.after;
    final space = value.indexOf(' ');
    if (space >= 0) {
      return _entry(value.substring(0, space), value.substring(space + 1));
    }
    final renamed = _rename(value);
    _pending = renamed?.stamp;
    return renamed?.label;
  }

  String? _entry(String label, String fingerprint) {
    final renamed = _rename(label);
    if (renamed == null) return null;
    final stamp = renamed.stamp;
    final matched = stamp != null && fingerprint == stamp.before;
    return '${renamed.label} ${matched ? stamp.after : fingerprint}';
  }
}
