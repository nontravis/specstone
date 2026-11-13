import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

const _mermaidInfo = 'mermaid';
const _frontMatterMark = '---';
const _arrowChars = '-=.';
const _openers = '([{';
const _closers = ')]}';

final _flowchartWord = RegExp(r'^(?:flowchart|graph)\b');
final _directives = RegExp(
  r'^(?:subgraph|end|classDef|class|style|click|linkStyle|direction)\b',
);
final _idRun = RegExp('[A-Za-z0-9_]+');

/// Returns the flowchart findings of a typed [doc]; an untyped doc has none.
///
/// Each `mermaid` fenced block of a section whose merged doc type sets the
/// `diagram` key is read when its first body word is `flowchart` or `graph`:
/// a missing title under `title` sits at the opening fence, and every edge
/// and node-label finding sits at its own line, keyed to tell two on one
/// line apart. Any other line form is neither an edge nor a node label, so
/// an exotic form goes unchecked rather than wrongly flagged.
Iterable<Finding> checkDiagrams(CheckContext context, IndexedDoc doc) sync* {
  final type = context.typeOf(doc);
  if (type == null) return;
  final content = context.contentOf(doc);
  for (var i = 0; i < content.sections.length; i++) {
    final diagram = context.templateSectionAt(doc, i)?.diagram;
    if (diagram == null) continue;
    for (final block in _flowchartBlocks(
      sectionBodyLines(content.sections, content.lineFacts, i),
    )) {
      yield* _blockFindings(context, doc, block, diagram);
    }
  }
}

/// One `mermaid` flowchart block: its opening-fence line and body lines.
typedef DiagramBlock = ({int fenceLine, List<BodyLine> lines});

/// Returns each `mermaid` fence of [body] whose first body word is
/// `flowchart` or `graph`.
Iterable<DiagramBlock> _flowchartBlocks(List<BodyLine> body) sync* {
  final scan = fenceScan([for (final line in body) line.text]);
  var i = 0;
  while (i < body.length) {
    final info = scan.opens[i];
    if (info == null) {
      i++;
      continue;
    }
    var end = i + 1;
    while (end < body.length && !scan.closes[end]) {
      end++;
    }
    final lines = body.sublist(i + 1, end);
    if (info == _mermaidInfo &&
        lines.isNotEmpty &&
        _flowchartWord.hasMatch(lines.first.text.trim())) {
      yield (fenceLine: body[i].line, lines: lines);
    }
    i = end + 1;
  }
}

Iterable<Finding> _blockFindings(
  CheckContext context,
  IndexedDoc doc,
  DiagramBlock block,
  DiagramLint diagram,
) sync* {
  final frontMatter = _frontMatterLines(block.lines);
  if (diagram.title &&
      !frontMatter.any((line) => line.text.trimLeft().startsWith('title:'))) {
    yield context.finding(
      doc,
      FindingKind.diagramTitleMissing,
      line: block.fenceLine,
      message: 'the diagram carries no title',
    );
  }
  for (final line in block.lines) {
    yield* _lineFindings(context, doc, line, diagram, frontMatter);
  }
}

/// The `---` front matter of [lines], delimiters included, when its first
/// line opens one; empty when it closes nowhere.
List<BodyLine> _frontMatterLines(List<BodyLine> lines) {
  if (lines.isEmpty || lines.first.text.trim() != _frontMatterMark) {
    return const [];
  }
  for (var j = 1; j < lines.length; j++) {
    if (lines[j].text.trim() == _frontMatterMark) {
      return lines.sublist(0, j + 1);
    }
  }
  return const [];
}

Iterable<Finding> _lineFindings(
  CheckContext context,
  IndexedDoc doc,
  BodyLine line,
  DiagramLint diagram,
  List<BodyLine> frontMatter,
) sync* {
  if (frontMatter.contains(line)) return;
  final text = line.text.trim();
  if (text.isEmpty ||
      _flowchartWord.hasMatch(text) ||
      _directives.hasMatch(text)) {
    return;
  }
  final scan = scanDiagramLine(line.text);
  if (diagram.edgeLabels) {
    for (final edge in scan.edges) {
      final label = edge.label.trim();
      if (label.isNotEmpty && !diagram.bannedLabels.contains(label)) continue;
      final pair = '${edge.from} --> ${edge.to}';
      yield context.finding(
        doc,
        FindingKind.diagramEdgeUnlabeled,
        line: line.line,
        message: label.isEmpty
            ? 'the edge $pair carries no label'
            : 'the edge $pair carries the banned label $label',
        keys: {'edge': pair},
      );
    }
  }
  for (final node in scan.nodes) {
    if (!_holdsUnquotedBracket(line.text.substring(node.start, node.end))) {
      continue;
    }
    yield context.finding(
      doc,
      FindingKind.diagramLabelUnquoted,
      line: line.line,
      message: 'the label of node ${node.id} holds an unquoted bracket',
      keys: {'node': node.id},
    );
  }
}

/// The nodes and edges of one diagram line, as written.
final class DiagramLineScan {
  /// Each node with a shape: its id and the content range of the shape.
  final nodes = <({String id, int start, int end})>[];

  /// Each edge: its two node ids and its label text, empty without one.
  final edges = <({String from, String to, String label})>[];
}

/// Reads [line] into its node shapes and edges.
///
/// An identifier names a node, the shape right after it its label, and an
/// arrow run of `-`, `=`, or `.` characters an edge. An arrow carries its
/// label in `|label|` after it, or as the text between a bare run and the
/// tipped run that closes it (`A -- text --> B`). An arrow with no node on
/// either side names no edge, and an unclosed shape runs to the line's end.
DiagramLineScan scanDiagramLine(String line) {
  final scan = DiagramLineScan();
  final tokens = _tokensOf(line);
  String? lastId;
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    if (token is _NodeToken) {
      lastId = token.id;
      if (token.shapeEnd > token.shapeStart) {
        scan.nodes.add((
          id: token.id,
          start: token.shapeStart,
          end: token.shapeEnd,
        ));
      }
    } else if (token is _ArrowToken && lastId != null) {
      final next = tokens[i + 1];
      final piped = next is _PipeToken ? tokens[i + 2] : next;
      if (piped is _NodeToken) {
        scan.edges.add((
          from: lastId,
          to: piped.id,
          label: next is _PipeToken ? next.label : token.label,
        ));
      }
    }
  }
  return scan;
}

/// One token of a diagram line: a node, an arrow, or a `|label|` pipe.
sealed class _Token;

final class _NodeToken extends _Token {
  new(this.id, this.shapeStart, this.shapeEnd);

  final String id;
  final int shapeStart;
  final int shapeEnd;
}

final class _ArrowToken extends _Token {
  new(this.label);

  /// The text between a bare run and the run that closes it; empty without.
  final String label;
}

final class _PipeToken extends _Token {
  new(this.label);

  final String label;
}

/// Returns the tokens of [line]: node ids with their shapes, arrow runs with
/// the bare-run label folded in, and `|label|` pipes after an arrow.
List<_Token> _tokensOf(String line) {
  final tokens = <_Token>[];
  var i = 0;
  while (i < line.length) {
    final unit = line.codeUnitAt(i);
    if (unit == 0x20 || unit == 0x09) {
      i++;
      continue;
    }
    final id = _idRun.matchAsPrefix(line, i);
    if (id != null) {
      final shape = _shapeRangeAt(line, id.end);
      tokens.add(_NodeToken(id[0]!, shape?.$1 ?? id.end, shape?.$2 ?? id.end));
      i = shape?.$2 ?? id.end;
      continue;
    }
    final arrow = _arrowAt(line, i);
    if (arrow != null) {
      final closing = arrow.hasTip ? null : _tipArrowAfter(line, arrow.end);
      tokens.add(
        _ArrowToken(
          closing == null
              ? ''
              : line.substring(arrow.end, closing.start).trim(),
        ),
      );
      i = closing?.end ?? arrow.end;
      continue;
    }
    if (unit == 0x7C && tokens.lastOrNull is _ArrowToken) {
      final close = line.indexOf('|', i + 1);
      if (close >= 0) {
        tokens.add(_PipeToken(line.substring(i + 1, close)));
        i = close + 1;
        continue;
      }
    }
    i++;
  }
  return tokens;
}

/// The arrow at [i]: its end offset and whether it ends with the tip `>`;
/// null when fewer than two arrow characters start there.
({int end, bool hasTip})? _arrowAt(String line, int i) {
  var end = i;
  while (end < line.length &&
      _arrowChars.codeUnits.contains(line.codeUnitAt(end))) {
    end++;
  }
  if (end - i < 2) return null;
  final hasTip = end < line.length && line.codeUnitAt(end) == 0x3E;
  return (end: hasTip ? end + 1 : end, hasTip: hasTip);
}

/// The tipped arrow run after [from], or null; a bare arrow's label is the
/// text up to its start.
({int start, int end})? _tipArrowAfter(String line, int from) {
  var i = from;
  while (i < line.length) {
    if (!_arrowChars.codeUnits.contains(line.codeUnitAt(i))) {
      i++;
      continue;
    }
    final arrow = _arrowAt(line, i);
    if (arrow == null) {
      i++;
      continue;
    }
    if (arrow.hasTip) return (start: i, end: arrow.end);
    i = arrow.end;
  }
  return null;
}

/// The content range of the shape opening at [i], or null when none does.
///
/// The range starts past the opener and ends at the matching closer, a
/// quoted closer opaque; an unclosed shape runs to the line's end.
(int, int)? _shapeRangeAt(String line, int i) {
  if (i >= line.length || !_openers.contains(line[i])) return null;
  final opener = line.codeUnitAt(i);
  final closer = _closers.codeUnitAt(_openers.indexOf(line[i]));
  var depth = 1;
  var quoted = false;
  for (var j = i + 1; j < line.length; j++) {
    final unit = line.codeUnitAt(j);
    if (quoted) {
      quoted = unit != 0x22;
    } else if (unit == 0x22) {
      quoted = true;
    } else if (unit == opener) {
      depth++;
    } else if (unit == closer) {
      depth--;
      if (depth == 0) return (i + 1, j);
    }
  }
  return (i + 1, line.length);
}

/// Whether [shapeContent] holds a bracket outside double quotes.
bool _holdsUnquotedBracket(String shapeContent) {
  var quoted = false;
  for (final unit in shapeContent.codeUnits) {
    if (quoted) {
      quoted = unit != 0x22;
    } else if (unit == 0x22) {
      quoted = true;
    } else if (_openers.codeUnits.contains(unit) ||
        _closers.codeUnits.contains(unit)) {
      return true;
    }
  }
  return false;
}
