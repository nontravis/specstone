import 'package:specstone_core/src/consistency_check/scenario_blocks.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/index_query/banned_matches.dart'
    show SearchLine, codeSpansOf;
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/link_scan.dart';
import 'package:specstone_core/src/journeys/journey_steps.dart';
import 'package:specstone_core/src/setup_migration/renumber_doc.dart';
import 'package:specstone_core/src/setup_migration/renumber_index.dart';

// MARK: - Constants

const _lineFeed = 0x0A;
final _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

// MARK: - Types

/// A link or code span opening at column `at` of a line, and the DocPaths
/// it cites: empty for a doc address that names no doc of the run.
typedef _Citation = ({int at, List<String> docPaths});

// MARK: - RenumberBodyRewrite

/// Rewrites the body lines of one doc of the renumber pass, [_lines], in
/// place: its item ID tokens and journey `step:` values.
final class RenumberBodyRewrite {
  new(this._doc, this._index, this._lines)
    : _body = Doc.parse(_doc.lf).afterFrontmatter;

  final RenumberDoc _doc;
  final RenumberIndex _index;
  final List<String> _lines;
  final String _body;

  /// The index in [_lines] of the first line past the frontmatter.
  late final int _firstLine = '\n'
      .allMatches(_doc.lf.substring(0, _doc.lf.length - _body.length))
      .length;

  late final Map<int, List<_Citation>> _linkCitations = _linkCitationsOf();

  late final Map<int, LetteredItem> _openers = {
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
      scenarioRefOf(named.to),
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
  Renumbering? _renumberingIn(List<String> docPaths, String written) {
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

// MARK: - Word boundaries

/// Whether the code point before [at] in [text] is a letter or digit.
bool _isWordCharBefore(String text, int at) {
  if (at == 0) return false;
  final isPair = at >= 2 && _isLowSurrogate(text.codeUnitAt(at - 1));
  return _wordChar.hasMatch(text.substring(at - (isPair ? 2 : 1), at));
}

bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;
