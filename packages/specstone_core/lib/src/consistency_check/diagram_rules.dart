import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/diagram_names.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/models/diagram_block.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/models/text_range.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

const _frontMatterMark = '---';
const _arrowChars = '-=.';
const _headChars = 'xo';
const _openLinkRun = 3;
const _openers = '([{';
const _closers = ')]}';

final _flowchartWord = RegExp(r'^(?:flowchart|graph)\b');
final _sequenceWord = RegExp(r'^sequenceDiagram\b');
final _directives = RegExp(
  r'^(?:subgraph|end|classDef|class|style|click|linkStyle|direction)\b',
);
final _idRun = RegExp('[A-Za-z0-9_]+');
final _classShorthand = RegExp(':::[A-Za-z0-9_]+');
final _subgraphId = RegExp(r'^subgraph\s+([A-Za-z0-9_]+)');
final _technologyPart = RegExp(r'\s+\([^()]*\)$');
// A sequence id runs over any character but `<>:,;@` and a line break.
const _sequenceId = r'[^<>:\n,;@]+?';
final _participant = RegExp(
  '^(participant|actor)\\s+($_sequenceId)(?:\\s+as\\s+(.+))?\$',
);
final _message = RegExp(
  '^($_sequenceId)\\s*(?:-->>|->>|--x|-x|--\\)|-\\)|-->|->)\\s*[+-]?\\s*'
  '($_sequenceId)\\s*:',
);
final _edgeQuotes = RegExp(r'^"|"$');
const _createPrefix = 'create ';

/// Returns the diagram findings of a typed [doc]; an untyped doc has none.
///
/// Each `mermaid` fenced block of a section whose merged doc type sets the
/// `diagram` key is read when its first body word is `flowchart`, `graph`, or
/// `sequenceDiagram`. A missing title under `title` sits at the opening
/// fence. Flowchart and graph blocks alone take the edge and node-label
/// rules: each finding sits at its own line, keyed to tell two on one line
/// apart, and any other line form is neither an edge nor a node label, so an
/// exotic form goes unchecked rather than wrongly flagged. Under `names`,
/// each name a block draws is held to the sources of the doc, one finding per
/// name at the line where it first appears.
Iterable<Finding> checkDiagrams(CheckContext context, IndexedDoc doc) sync* {
  final type = context.typeOf(doc);
  if (type == null) return;
  final content = context.contentOf(doc);
  DiagramNames? sources;
  DiagramNames sourcesOfDoc() => sources ??= context.diagramNamesOf(doc);
  for (var i = 0; i < content.sections.length; i++) {
    final diagram = context.templateSectionAt(doc, i)?.diagram;
    if (diagram == null) continue;
    for (final block in _diagramBlocks(
      sectionBodyLines(content.sections, content.lineFacts, i),
    )) {
      yield* _blockFindings(context, doc, block, diagram, sourcesOfDoc);
    }
  }
}

/// Returns each `mermaid` fence of [body] whose first body word is
/// `flowchart`, `graph`, or `sequenceDiagram`, tagged by that kind.
Iterable<_KindedBlock> _diagramBlocks(List<BodyLine> body) sync* {
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
    final drawn = lines.skip(_frontMatterLines(lines).length);
    final kind = info == mermaidInfoWord && drawn.isNotEmpty
        ? _kindOf(drawn.first.text.trim())
        : null;
    if (kind != null) {
      yield _KindedBlock(
        kind: kind,
        block: DiagramBlock(fenceLine: body[i].line, lines: lines),
      );
    }
    i = end + 1;
  }
}

_DiagramKind? _kindOf(String firstLine) {
  if (_flowchartWord.hasMatch(firstLine)) return _DiagramKind.flowchart;
  if (_sequenceWord.hasMatch(firstLine)) return _DiagramKind.sequence;
  return null;
}

/// The diagram kinds a block may be, by its first body word.
enum _DiagramKind { flowchart, sequence }

/// A diagram block and the kind its first body word gives.
final class _KindedBlock {
  const new({required this.kind, required this.block});

  final _DiagramKind kind;
  final DiagramBlock block;
}

Iterable<Finding> _blockFindings(
  CheckContext context,
  IndexedDoc doc,
  _KindedBlock read,
  DiagramLint diagram,
  DiagramNames Function() sourcesOfDoc,
) sync* {
  final _KindedBlock(:kind, :block) = read;
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
  if (kind == _DiagramKind.flowchart) {
    for (final line in block.lines) {
      yield* _lineFindings(context, doc, line, diagram, frontMatter);
    }
  }
  if (diagram.names) {
    yield* _nameFindings(context, doc, _drawnNames(read), sourcesOfDoc(), kind);
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
      text.startsWith('%%') ||
      _flowchartWord.hasMatch(text) ||
      _directives.hasMatch(text)) {
    return;
  }
  final scan = _scanDiagramLine(line.text);
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
    final label = _withoutShapePairs(line.text.substring(node.start, node.end));
    if (!_holdsUnquotedBracket(label)) {
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

/// Returns the findings of the names [drawn] holds, one per name at the line
/// where it first appears.
///
/// An `actor` must carry a role name; any other box or participant must carry
/// a name of [sources], or else a role name, which is the one fault of
/// drawing a role as a box. A merged set with no `roles` section leaves the
/// role checks unread. A role named in a flowchart cannot become an actor
/// there, so its message gives the fix its [kind] can take.
Iterable<Finding> _nameFindings(
  CheckContext context,
  IndexedDoc doc,
  List<_DrawnName> drawn,
  DiagramNames sources,
  _DiagramKind kind,
) sync* {
  final first = <String, _DrawnName>{};
  for (final name in drawn) {
    final held = first[name.text];
    if (held == null || name.line < held.line) first[name.text] = name;
  }
  final readsRoles = context.holdsRoles;
  for (final _DrawnName(:text, :line, :isActor) in first.values) {
    final isRole = sources.roles.contains(text);
    if (isActor ? !isRole : !sources.names.contains(text) && isRole) {
      if (!readsRoles) continue;
      yield context.finding(
        doc,
        FindingKind.diagramActorMismatch,
        line: line,
        message: isActor
            ? '$text is drawn as an actor but names no role'
            : kind == _DiagramKind.flowchart
            ? '$text names a role; a box never does, draw the role as a '
                  'sequence `actor` or leave it out'
            : '$text names a role, so draw it as an actor',
        keys: {'label': text},
      );
    } else if (!isActor && !sources.names.contains(text)) {
      yield context.finding(
        doc,
        FindingKind.diagramNameUnknown,
        line: line,
        message: '$text names no component, system, or role of the project',
        keys: {'label': text},
      );
    }
  }
}

/// A name a diagram draws, the line where it first appears, and whether the
/// diagram declares it an `actor`.
final class _DrawnName {
  const new({required this.text, required this.line, this.isActor = false});

  final String text;
  final int line;
  final bool isActor;
}

List<_DrawnName> _drawnNames(_KindedBlock read) => switch (read.kind) {
  _DiagramKind.flowchart => _flowchartNames(read.block),
  _DiagramKind.sequence => _sequenceNames(read.block),
};

/// Returns the name of each node of a flowchart [block]: the label of the
/// first shape that gives one, else its ID at its first line.
///
/// A `subgraph` title and the ID of a `subgraph` are no name.
List<_DrawnName> _flowchartNames(DiagramBlock block) {
  final frontMatter = _frontMatterLines(block.lines);
  final labels = <String, _DrawnName>{};
  final firstSeen = <String, int>{};
  final groups = <String>{};
  for (final line in block.lines) {
    final text = line.text.trim();
    if (frontMatter.contains(line) ||
        text.isEmpty ||
        text.startsWith('%%') ||
        _flowchartWord.hasMatch(text)) {
      continue;
    }
    if (_subgraphId.firstMatch(text) case final group?) groups.add(group[1]!);
    if (_directives.hasMatch(text)) continue;
    final bare = line.text.replaceAll(_classShorthand, '');
    final scan = _scanDiagramLine(bare);
    for (final id in scan.ids) {
      firstSeen.putIfAbsent(id, () => line.line);
    }
    for (final node in scan.nodes) {
      final label = _boxLabel(bare.substring(node.start, node.end));
      if (label.isNotEmpty) {
        labels.putIfAbsent(
          node.id,
          () => _DrawnName(text: label, line: line.line),
        );
      }
    }
  }
  return [
    for (final MapEntry(:key, :value) in firstSeen.entries)
      if (labels[key] case final label?)
        label
      else if (!groups.contains(key))
        _DrawnName(text: key, line: value),
  ];
}

/// Returns [shapeContent] as a box name: its pair delimiters and quotes
/// dropped, and a trailing ` (<technology>)`.
String _boxLabel(String shapeContent) {
  var label = _withoutShapePairs(shapeContent).trim();
  if (label.length >= 2 && label.startsWith('"') && label.endsWith('"')) {
    label = label.substring(1, label.length - 1);
  }
  return label.replaceFirst(_technologyPart, '').trim();
}

/// Returns the name of each `participant` and `actor` of a sequence [block],
/// by its display label else its ID, then each participant never declared by
/// its ID at its first message line.
List<_DrawnName> _sequenceNames(DiagramBlock block) {
  final frontMatter = _frontMatterLines(block.lines);
  final lines = [
    for (final line in block.lines)
      if (!frontMatter.contains(line)) line,
  ];
  final declared = <String>{};
  final names = <_DrawnName>[];
  for (final line in lines) {
    final text = _withoutCreate(line.text.trim());
    if (_participant.firstMatch(text) case final match?) {
      declared.add(match[2]!);
      final label = match[3]?.trim().replaceAll(_edgeQuotes, '');
      names.add(
        _DrawnName(
          text: label == null || label.isEmpty ? match[2]! : label,
          line: line.line,
          isActor: match[1] == 'actor',
        ),
      );
    }
  }
  for (final line in lines) {
    final match = _message.firstMatch(line.text.trim());
    if (match == null) continue;
    for (final id in [match[1]!, match[2]!]) {
      if (declared.add(id)) names.add(_DrawnName(text: id, line: line.line));
    }
  }
  return names;
}

String _withoutCreate(String text) => text.startsWith(_createPrefix)
    ? text.substring(_createPrefix.length).trimLeft()
    : text;

/// The nodes and edges of one diagram line, as written.
final class _DiagramLineScan {
  /// Each node with a shape: its id and the content range of the shape.
  final nodes = <_ShapedNode>[];

  /// Each edge: its two node ids and its label text, empty without one.
  final edges = <_Edge>[];

  /// Each node id, in line order, with a shape or without.
  final ids = <String>[];
}

/// A node with a shape: its id and the content range of the shape.
final class _ShapedNode {
  const new({required this.id, required this.start, required this.end});

  final String id;
  final int start;
  final int end;
}

/// An edge: its two node ids and its label text, empty without one.
final class _Edge {
  const new({required this.from, required this.to, required this.label});

  final String from;
  final String to;
  final String label;
}

/// An arrow run: its end offset, whether it ends with the tip `>`, and how
/// many arrow characters it holds.
final class _Arrow {
  const new({required this.end, required this.hasTip, required this.run});

  final int end;
  final bool hasTip;
  final int run;
}

/// Reads [line] into its node shapes and edges.
///
/// An identifier names a node, the shape right after it its label, and an
/// arrow run of `-`, `=`, or `.` characters an edge. An arrow carries its
/// label in `|label|` after it, or as the text between a bare run and the
/// tipped run that closes it (`A -- text --> B`). An arrow with no node on
/// either side names no edge, and an unclosed shape runs to the line's end.
_DiagramLineScan _scanDiagramLine(String line) {
  final scan = _DiagramLineScan();
  final tokens = _tokensOf(line);
  String? lastId;
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    if (token is _NodeToken) {
      lastId = token.id;
      scan.ids.add(token.id);
      if (token.shapeEnd > token.shapeStart) {
        scan.nodes.add(
          _ShapedNode(
            id: token.id,
            start: token.shapeStart,
            end: token.shapeEnd,
          ),
        );
      }
    } else if (token is _ArrowToken && lastId != null) {
      final next = tokens.elementAtOrNull(i + 1);
      final target = next is _PipeToken ? tokens.elementAtOrNull(i + 2) : next;
      if (token.isEdge && target is _NodeToken) {
        scan.edges.add(
          _Edge(
            from: lastId,
            to: target.id,
            label: next is _PipeToken ? next.label : token.label,
          ),
        );
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
  new(this.label, {required this.isEdge});

  /// Whether the run reads as an edge: it ends with a tip, closes a bare
  /// run's text label, or is an open link of three or more characters.
  final bool isEdge;

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
    if (id != null && _isLeadingHead(line, i, id, tokens)) {
      i = id.end;
      continue;
    }
    if (id != null) {
      final shape = _shapeRangeAt(line, id.end);
      tokens.add(
        _NodeToken(id[0]!, shape?.start ?? id.end, shape?.end ?? id.end),
      );
      i = shape?.end ?? id.end;
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
          isEdge: arrow.hasTip || closing != null || arrow.run >= _openLinkRun,
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
_Arrow? _arrowAt(String line, int i) {
  var end = i;
  while (end < line.length &&
      _arrowChars.codeUnits.contains(line.codeUnitAt(end))) {
    end++;
  }
  if (end - i < 2) return null;
  final hasTip =
      end < line.length &&
      (line.codeUnitAt(end) == 0x3E || _isHeadAt(line, end));
  return _Arrow(end: hasTip ? end + 1 : end, hasTip: hasTip, run: end - i);
}

/// Whether the `x` or `o` at [i] is the head of an arrow run: a lone letter,
/// followed by no other identifier character.
bool _isHeadAt(String line, int i) =>
    _headChars.codeUnits.contains(line.codeUnitAt(i)) &&
    (i + 1 == line.length || _idRun.matchAsPrefix(line, i + 1) == null);

/// Whether the lone `x` or `o` id [head] at [i] is the head that opens an
/// arrow run, such as the first `x` of `A x--x B`: it follows a node and a
/// space and leads an arrow run.
bool _isLeadingHead(String line, int i, Match head, List<_Token> tokens) =>
    head.end - i == 1 &&
    _headChars.contains(line[i]) &&
    i > 0 &&
    (line.codeUnitAt(i - 1) == 0x20 || line.codeUnitAt(i - 1) == 0x09) &&
    tokens.lastOrNull is _NodeToken &&
    _arrowAt(line, head.end) != null;

/// The tipped arrow run after [from], or null; a bare arrow's label is the
/// text up to its start.
TextRange? _tipArrowAfter(String line, int from) {
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
    if (arrow.hasTip) return TextRange(start: i, end: arrow.end);
    i = arrow.end;
  }
  return null;
}

/// The content range of the shape opening at [i], or null when none does.
///
/// The range starts past the opener and ends at the matching closer, a
/// quoted closer opaque; an unclosed shape runs to the line's end.
TextRange? _shapeRangeAt(String line, int i) {
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
      if (depth == 0) return TextRange(start: i + 1, end: j);
    }
  }
  return TextRange(start: i + 1, end: line.length);
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

/// Returns [content], a shape's inner text, without the paired delimiters
/// that make the shape (`((x))`, `([x])`, `[(x)]`, `[[x]]`, `{{x}}`).
String _withoutShapePairs(String content) {
  var text = content;
  while (text.length >= 2 &&
      _openers.contains(text[0]) &&
      text.endsWith(_closers[_openers.indexOf(text[0])])) {
    text = text.substring(1, text.length - 1);
  }
  return text;
}
