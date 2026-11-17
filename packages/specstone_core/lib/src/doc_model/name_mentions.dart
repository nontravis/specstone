import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/doc.dart' show Doc, fenceScan;
import 'package:specstone_core/src/doc_model/reference_grammar.dart';

/// A doc-name mention: a code span whose whole text, less an optional
/// `#<section key>`, reads as a DocAddress of the no-lookup class, or a token
/// of that class in a `mermaid` block.
///
/// `line` is 1-based and `column` the 0-based offset of the first character
/// of `text` in its line, after the opening backticks.
typedef NameMention = ({int line, int column, String text, DocAddress address});

/// The info word that marks a fenced block as a Mermaid diagram.
const _mermaidInfo = 'mermaid';

/// The doc-name mentions of [lf], a doc body or a markdown file, read from its
/// code spans outside fenced code and from the tokens of its `mermaid` blocks,
/// each line alone.
List<NameMention> nameMentionsInMarkdown(String lf) {
  if (!lf.contains('`') && !lf.contains(_mermaidInfo)) return const [];
  return _readLines(
    lf.split('\n'),
    1,
    _mentionsOnLine,
    onMermaidLine: _tokenMentionsOnLine,
  );
}

Iterable<NameMention> _tokenMentionsOnLine(
  String line,
  int number, {
  required bool isSequence,
}) => [
  for (final token in mermaidTokensIn(line, isSequence: isSequence))
    (
      line: number,
      column: token.column,
      text: token.text,
      address: token.address,
    ),
];

Iterable<NameMention> _noMentions(
  String line,
  int number, {
  required bool isSequence,
}) => const [];

/// Reads the tokens of one line of a `mermaid` block; `isSequence` tells a
/// `sequenceDiagram` block.
typedef _MermaidLineReader = Iterable<NameMention> Function(
  String line,
  int number, {
  required bool isSequence,
});

/// The mentions [onLine] reads from the lines of [lines] outside fenced code
/// and [onMermaidLine] from those between the fences of a `mermaid` block,
/// the first of them at line [firstLine].
List<NameMention> _readLines(
  List<String> lines,
  int firstLine,
  Iterable<NameMention> Function(String line, int number) onLine, {
  _MermaidLineReader onMermaidLine = _noMentions,
}) {
  final scan = fenceScan(lines);
  final mermaid = _mermaidLines(lines, scan.fenced, scan.opens, scan.closes);
  return [
    for (var i = 0; i < lines.length; i++)
      if (!scan.fenced[i])
        ...onLine(lines[i], firstLine + i)
      else if (mermaid[i] != _Diagram.none)
        ...onMermaidLine(
          lines[i],
          firstLine + i,
          isSequence: mermaid[i] == _Diagram.sequence,
        ),
  ];
}

/// What a line is to the `mermaid` reader.
enum _Diagram { none, flow, sequence }

/// The `mermaid` line that names a sequence diagram, as the first line of
/// the block after its frontmatter, blank lines, and `%%` comments.
const _sequenceHead = 'sequenceDiagram';

/// Returns, per line, the kind of `mermaid` block it sits between the fences
/// of, `none` outside one; fence lines are `none`.
List<_Diagram> _mermaidLines(
  List<String> lines,
  List<bool> fenced,
  List<String?> opens,
  List<bool> closes,
) {
  final kinds = <_Diagram>[];
  var inMermaid = false;
  var head = _BlockHead.start;
  var kind = _Diagram.flow;
  for (var i = 0; i < fenced.length; i++) {
    final opened = opens[i];
    if (opened != null) {
      inMermaid = opened == _mermaidInfo;
      head = _BlockHead.start;
      kind = _Diagram.flow;
    }
    if (!fenced[i]) inMermaid = false;
    final inBlock = inMermaid && opened == null && !closes[i];
    if (inBlock && head != _BlockHead.done) {
      (head, kind) = _afterHeadLine(head, lines[i].trim());
    }
    kinds.add(inBlock ? kind : _Diagram.none);
  }
  return kinds;
}

/// Where a `mermaid` block stands before its first diagram line.
enum _BlockHead { start, frontmatter, done }

(_BlockHead, _Diagram) _afterHeadLine(_BlockHead head, String line) {
  if (head == _BlockHead.frontmatter) {
    return (line == '---' ? _BlockHead.start : head, _Diagram.flow);
  }
  if (line.isEmpty || line.startsWith('%%')) return (head, _Diagram.flow);
  if (line == '---') return (_BlockHead.frontmatter, _Diagram.flow);
  return (
    _BlockHead.done,
    line.startsWith(_sequenceHead) ? _Diagram.sequence : _Diagram.flow,
  );
}

Iterable<NameMention> _mentionsOnLine(String line, int number) =>
    _spansOnLine(line, number, (address) => address.isReferenceWithoutLookup);

/// The code spans of [line] whose address [accepts].
Iterable<NameMention> _spansOnLine(
  String line,
  int number,
  bool Function(DocAddress address) accepts,
) sync* {
  for (final (:start, :end, :ticks) in codeSpansOf(line)) {
    final text = line.substring(start + ticks, end - ticks);
    final address = readDocAddress(text);
    if (!accepts(address)) continue;
    yield (line: number, column: start + ticks, text: text, address: address);
  }
}

/// The extension that marks a file as markdown, read as a doc is.
const markdownExtension = '.md';

/// The line-comment mark of each extension whose files hold comment lines;
/// any other extension has none.
const _commentMarks = {
  '.dart': '//',
  '.js': '//',
  '.ts': '//',
  '.sh': '#',
  '.ps1': '#',
  '.yaml': '#',
  '.yml': '#',
  '.py': '#',
};

/// The extension of [path], a `/`-separated path from a code root: the last
/// `.` of its file name and what follows, empty when the name has none or
/// starts with its only `.`.
String extensionOfCodePath(String path) {
  final name = path.substring(path.lastIndexOf('/') + 1);
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? '' : name.substring(dot);
}

/// Whether a file of [extension], a `.` and its letters, holds doc-name
/// mentions: markdown, or a type with a line-comment mark.
bool readsNameMentions(String extension) =>
    extension == markdownExtension || _commentMarks.containsKey(extension);

/// Whether [line] of a file of [extension] is a comment line: its text after
/// the indent opens with the extension's line-comment mark.
///
/// An end-of-line comment is no comment line, and an extension with no mark
/// holds none.
bool isCommentLine(String line, String extension) {
  final mark = _commentMarks[extension];
  return mark != null && line.trimLeft().startsWith(mark);
}

/// The doc-name mentions in the comment lines of [lf], a file of [extension]
/// that is not markdown, each line alone.
List<NameMention> nameMentionsInComments(String lf, String extension) {
  if (!lf.contains('`')) return const [];
  final lines = lf.split('\n');
  return [
    for (var i = 0; i < lines.length; i++)
      if (isCommentLine(lines[i], extension))
        ..._mentionsOnLine(lines[i], i + 1),
  ];
}

/// The doc-name mentions of [lf], a file of [extension] under the `code:`
/// roots or a doc, and the doc paths it writes, each at its line of the file.
///
/// Markdown is read after its frontmatter and outside fenced code, as a doc
/// is; any other file by its comment lines. A path mention's text is the path
/// as written, less any `#anchor`, line suffix, and closing mark, and its
/// address is no reference without lookup.
///
/// With [withMermaid], markdown also yields the tokens of its `mermaid`
/// blocks, as [nameMentionsInMarkdown] does; a doc's reference readers set it,
/// a code file's or a cite's reader does not.
List<NameMention> nameMentionsInFile(
  String lf,
  String extension, {
  bool withMermaid = false,
}) {
  final holdsTokens = withMermaid && lf.contains(_mermaidInfo);
  if (!lf.contains('`') && !lf.contains(markdownExtension) && !holdsTokens) {
    return const [];
  }
  return _readFile(
    lf,
    extension,
    _namesAndPathsOnLine,
    onMermaidLine: withMermaid ? _tokenMentionsOnLine : _noMentions,
  );
}

/// The addresses that sit inside longer code spans of [lf], a markdown doc,
/// read after its frontmatter and outside fenced code.
///
/// Each entry is one no-lookup address found in a span whose whole text is no
/// such address; `text` is the whole span and `address` the one it holds, so a
/// span holding several addresses yields several entries at one `column`.
List<NameMention> longerSpanMentionsInMarkdown(String lf) {
  if (!lf.contains('`')) return const [];
  return _readFile(lf, markdownExtension, _longerSpansOnLine);
}

Iterable<NameMention> _longerSpansOnLine(String line, int number) sync* {
  for (final (:start, :end, :ticks) in codeSpansOf(line)) {
    final text = line.substring(start + ticks, end - ticks);
    if (readDocAddress(text).isReferenceWithoutLookup) continue;
    for (final address in referencesWithoutLookupIn(text)) {
      yield (line: number, column: start + ticks, text: text, address: address);
    }
  }
}

List<NameMention> _namesAndPathsOnLine(String line, int number) =>
    _ordered(_mentionsOnLine(line, number), _pathsOnLine(line, number));

List<NameMention> _ordered(
  Iterable<NameMention> spans,
  Iterable<NameMention> paths,
) {
  final found = [...spans, ...paths];
  if (found.length > 1) found.sort((a, b) => a.column.compareTo(b.column));
  return found;
}

/// The characters, besides whitespace, that end a path written in prose.
final Set<int> _pathBreaks = {...'`\'"()[]<>{}|,;*~!?='.codeUnits};

/// Whether the code unit [code] ends a doc path or the `#key` after it when
/// written in prose.
bool endsDocPath(int code) => code <= 0x20 || _pathBreaks.contains(code);

/// The doc paths written on [line]: each run of path characters that ends in
/// `.md`, less its `#anchor`, line suffix, and closing mark.
Iterable<NameMention> _pathsOnLine(String line, int number) sync* {
  var readTo = 0;
  for (
    var at = line.indexOf(markdownExtension);
    at >= 0;
    at = line.indexOf(markdownExtension, at + 1)
  ) {
    if (at < readTo) continue;
    var start = at;
    while (start > 0 && !endsDocPath(line.codeUnitAt(start - 1))) {
      start--;
    }
    var end = at + markdownExtension.length;
    while (end < line.length && !endsDocPath(line.codeUnitAt(end))) {
      end++;
    }
    readTo = end;
    final path = _docPathOf(line.substring(start, end));
    if (path == null) continue;
    yield (
      line: number,
      column: start,
      text: path,
      address: readDocAddress(path),
    );
  }
}

/// The path part of [token], or null when it does not end in a doc file name.
String? _docPathOf(String token) {
  final path = proseTrimmedPath(readDocAddress(token).docPart);
  return path.length > markdownExtension.length &&
          path.endsWith(markdownExtension)
      ? path
      : null;
}

/// The mentions [onLine] reads from the lines of [lf] that a file of
/// [extension] holds: markdown's text after its frontmatter and outside
/// fenced code, any other file's comment lines. Markdown's `mermaid` block
/// lines go to [onMermaidLine].
List<NameMention> _readFile(
  String lf,
  String extension,
  Iterable<NameMention> Function(String line, int number) onLine, {
  _MermaidLineReader onMermaidLine = _noMentions,
}) {
  if (extension != markdownExtension) {
    final lines = lf.split('\n');
    return [
      for (var i = 0; i < lines.length; i++)
        if (isCommentLine(lines[i], extension)) ...onLine(lines[i], i + 1),
    ];
  }
  final body = Doc.parse(lf).afterFrontmatter;
  final bodyStart = _breaksIn(lf.substring(0, lf.length - body.length));
  return _readLines(
    body.split('\n'),
    bodyStart + 1,
    onLine,
    onMermaidLine: onMermaidLine,
  );
}

int _breaksIn(String text) => '\n'.allMatches(text).length;
