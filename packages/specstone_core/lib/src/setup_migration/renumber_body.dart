import 'package:specstone_core/src/consistency_check/scenario_blocks.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/document_writing/key_block_values.dart';
import 'package:specstone_core/src/index_query/banned_matches.dart'
    show codeSpansOf;
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/link_scan.dart';
import 'package:specstone_core/src/journeys/journey_steps.dart';
import 'package:specstone_core/src/setup_migration/renumber_doc.dart';
import 'package:specstone_core/src/setup_migration/renumber_index.dart';

// MARK: - Constants

const _lineFeed = 0x0A;
const _tracedFromKey = 'traced_from';

/// The prefix of a short scenario ref in prose, `S6a` (W6).
const _shortRefPrefix = 'S';
final _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

// MARK: - Types

/// A link or code span opening at column `at` of a line, and the DocPaths
/// it cites: empty for a doc address that names no doc of the run.
typedef _Citation = ({int at, List<String> docPaths});

/// An ID token of a prose line: its column, its text, and its prefix.
typedef _Token = ({int at, String written, IdRead id});

/// The edit of one token: its new text, and whether it names another doc.
typedef _Edit = ({String to, bool isOwn});

// MARK: - RenumberBodyRewrite

/// Rewrites the body lines of one doc of the renumber pass, [_lines], in
/// place: its item ID tokens and journey `step:` values.
final class RenumberBodyRewrite {
  new(this._doc, this._index, this._lines)
    : _body = _doc.lf.substring(_doc.frontmatterText.length);

  final RenumberDoc _doc;
  final RenumberIndex _index;
  final List<String> _lines;
  final String _body;

  /// The index in [_lines] of the first line past the frontmatter.
  late final int _firstLine = '\n'.allMatches(_doc.frontmatterText).length;

  /// The one link scan of the body: its prose and its link sources (W4).
  late final LinkScan _scan = linkScanOf(_body, firstLine: _firstLine + 1);

  late final List<int> _lineStarts = _lineStartsOf(_body);

  late final Map<int, List<_Citation>> _linkCitations = _linkCitationsOf();

  late final Map<int, LetteredItem> _openers = {
    for (final lettered in _doc.lettered) lettered.item.line: lettered,
  };

  /// The stories whose short refs `S6a` the doc's prose may hold: the doc
  /// itself when it is one, and each story its `traced_from` names (W6).
  late final Set<String> _shortRefStories = {
    ?_index.ownStoryOf(_doc.docPath),
    for (final value in _tracedFromValues())
      if (readScenarioRef(value) case final ref?)
        ?_index.storyOfRef(ref, _doc.docPath),
  }..removeWhere((story) => !_index.renumbersAScenarioOf(story));

  /// Rewrites each item ID token of the prose that its doc renumbers: the
  /// doc of the nearest citation before it on its line, else this doc
  /// (R67), and each short scenario ref of a story in [_shortRefStories].
  /// Returns whether a token of another doc changed.
  bool rewriteTokens() {
    var citesOthers = false;
    final prefixes = [
      ..._index.prefixes,
      if (_shortRefStories.isNotEmpty) _shortRefPrefix,
    ];
    for (var index = _firstLine; index < _lines.length; index++) {
      final prose = _proseOf(index - _firstLine);
      if (!prefixes.any(prose.contains)) continue;
      final (:text, :othersChanged) = _rewriteLine(
        _lines[index],
        prose,
        index + 1,
        prefixes,
      );
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
    final lettered = _index.scenarioOf(ref.storyName, ref.number);
    if (lettered == null) return false;
    final written = ref.number.written;
    final line = _lines[lineIndex];
    final at = line.lastIndexOf(written);
    _lines[lineIndex] = line.replaceRange(
      at,
      at + written.length,
      scenarioRefOf(lettered.to),
    );
    return true;
  }

  /// The prose of body line [bodyLine]: the line with all that is no prose
  /// blanked (W4).
  String _proseOf(int bodyLine) {
    final start = _lineStarts[bodyLine];
    final end = bodyLine + 1 < _lineStarts.length
        ? _lineStarts[bodyLine + 1] - 1
        : _scan.prose.length;
    return _scan.prose.substring(start, end);
  }

  ({String text, bool othersChanged}) _rewriteLine(
    String line,
    String prose,
    int fileLine,
    List<String> prefixes,
  ) {
    final citations = [..._spanCitations(line), ...?_linkCitations[fileLine]]
      ..sort((a, b) => a.at - b.at);
    // An item's own start line takes its own number, so two items lettered
    // alike still get two numbers.
    var opener = _openers[fileLine];
    var othersChanged = false;
    final edits = <({int at, int end, String to})>[];
    for (final token in _tokensOf(prose, prefixes)) {
      final cited = _citedAt(citations, token.at);
      final edit = token.id.prefix == _shortRefPrefix
          ? _shortRefEdit(token, cited)
          : _idEdit(token, cited, opener);
      if (edit == null) continue;
      if (edit.isOwn && opener?.from == token.written) opener = null;
      othersChanged = othersChanged || !edit.isOwn;
      edits.add((
        at: token.at,
        end: token.at + token.written.length,
        to: edit.to,
      ));
    }
    var text = line;
    for (final (:at, :end, :to) in edits.reversed) {
      text = text.replaceRange(at, end, to);
    }
    return (text: text, othersChanged: othersChanged);
  }

  /// The edit of the item ID [token]: the renumbering of the first [cited]
  /// doc, else this doc's, whose own opener takes the opener's number.
  _Edit? _idEdit(_Token token, List<String>? cited, LetteredItem? opener) {
    for (final docPath in cited ?? [_doc.docPath]) {
      final to = _index.toOf(docPath, token.written);
      if (to == null) continue;
      final isOwn = docPath == _doc.docPath;
      final ownOpener = isOwn && opener?.from == token.written;
      return (to: ownOpener ? opener!.to : to, isOwn: isOwn);
    }
    return null;
  }

  /// The edit of the short scenario ref [token]: the scenario of the first
  /// [cited] story, else of the doc's own story, that it may name (W6).
  _Edit? _shortRefEdit(_Token token, List<String>? cited) {
    final stories = cited ?? [?_index.ownStoryOf(_doc.docPath)];
    for (final story in stories) {
      if (!_shortRefStories.contains(story)) continue;
      final lettered = _index.scenarioAt(story, token.id);
      if (lettered == null) continue;
      return (to: scenarioRefOf(lettered.to), isOwn: story == _doc.docPath);
    }
    return null;
  }

  /// The lettered ID tokens of [prose] of [prefixes], read by the grammar,
  /// in line order, none overlapping.
  List<_Token> _tokensOf(String prose, List<String> prefixes) {
    final found = <_Token>[];
    for (final prefix in prefixes) {
      for (
        var at = prose.indexOf(prefix);
        at >= 0;
        at = prose.indexOf(prefix, at + 1)
      ) {
        if (_isWordCharBefore(prose, at)) continue;
        final id = readItemIdAt(prose, at, prefix);
        if (id is! LetteredId) continue;
        found.add((at: at, written: id.written, id: id));
      }
    }
    found.sort((a, b) => a.at - b.at);
    final tokens = <_Token>[];
    for (final token in found) {
      final end = tokens.isEmpty
          ? 0
          : tokens.last.at + tokens.last.written.length;
      if (token.at >= end) tokens.add(token);
    }
    return tokens;
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
    final citations = <int, List<_Citation>>{};
    for (final (:offset, :line, :shown, end: _, angle: _) in _scan.sources) {
      final docPath = shown == null
          ? null
          : _index.docAtPath(shown, _doc.docPath);
      if (docPath == null) continue;
      final at = offset - _lineStarts[line - 1 - _firstLine];
      (citations[line] ??= []).add((at: at, docPaths: [docPath]));
    }
    return citations;
  }

  /// The `traced_from` values of the doc, read by the key-block scan.
  List<String> _tracedFromValues() {
    final block = Doc.parse(_doc.frontmatterText).frontmatter
        ?.where((candidate) => candidate.name == _tracedFromKey)
        .firstOrNull;
    if (block == null) return const [];
    final values = <String>[];
    renameKeyBlockValues(block.text, block.key, (value) {
      values.add(value);
      return null;
    });
    return values;
  }
}

// MARK: - Text

/// The offset of each line's first code unit in [text].
List<int> _lineStartsOf(String text) {
  final starts = [0];
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == _lineFeed) starts.add(i + 1);
  }
  return starts;
}

/// Whether the code point before [at] in [text] is a letter or digit.
bool _isWordCharBefore(String text, int at) {
  if (at == 0) return false;
  final isPair = at >= 2 && _isLowSurrogate(text.codeUnitAt(at - 1));
  return _wordChar.hasMatch(text.substring(at - (isPair ? 2 : 1), at));
}

bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;
