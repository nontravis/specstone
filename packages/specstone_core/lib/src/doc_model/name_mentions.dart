import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/doc.dart' show Doc, blockScan;
import 'package:specstone_core/src/doc_model/reference_grammar.dart';

/// A doc-name mention: a code span whose whole text, less an optional
/// `#<section key>`, reads as a DocAddress of the no-lookup class (RULE-11).
///
/// `line` is 1-based and `column` the 0-based offset of the first character
/// of `text` in its line, after the opening backticks.
typedef NameMention = ({int line, int column, String text, DocAddress address});

/// The doc-name mentions of [lf], a doc body or a markdown file, read from its
/// code spans outside fenced code, each line alone.
List<NameMention> nameMentionsInMarkdown(String lf) {
  if (!lf.contains('`')) return const [];
  final lines = lf.split('\n');
  final fenced = blockScan(lines).fenced;
  return [
    for (var i = 0; i < lines.length; i++)
      if (!fenced[i]) ..._mentionsOnLine(lines[i], i + 1),
  ];
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

/// The line-comment mark of each extension whose files hold comment lines
/// (RULE-11); any other extension has none.
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
List<NameMention> nameMentionsInFile(String lf, String extension) {
  if (!lf.contains('`') && !lf.contains(markdownExtension)) return const [];
  return _readFile(lf, extension, _namesAndPathsOnLine);
}

/// The bare one-slug code spans of [lf], a file of [extension], each at its
/// line of the file, read where [nameMentionsInFile] reads.
///
/// Such a span is a mention only when a doc carries its Name, which the
/// caller looks up.
List<NameMention> bareNameMentionsInFile(String lf, String extension) {
  if (!lf.contains('`')) return const [];
  return _readFile(lf, extension, _bareSlugsOnLine);
}

Iterable<NameMention> _bareSlugsOnLine(String line, int number) => _spansOnLine(
  line,
  number,
  (address) =>
      address.typeId == null &&
      address.isName &&
      !address.isReferenceWithoutLookup,
);

List<NameMention> _namesAndPathsOnLine(String line, int number) {
  final found = [
    ..._mentionsOnLine(line, number),
    ..._pathsOnLine(line, number),
  ];
  if (found.length > 1) found.sort((a, b) => a.column.compareTo(b.column));
  return found;
}

/// The characters, besides whitespace, that end a path written in prose.
final Set<int> _pathBreaks = {...'`\'"()[]<>{}|,;*~!?='.codeUnits};

bool _endsPath(int code) => code <= 0x20 || _pathBreaks.contains(code);

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
    while (start > 0 && !_endsPath(line.codeUnitAt(start - 1))) {
      start--;
    }
    var end = at + markdownExtension.length;
    while (end < line.length && !_endsPath(line.codeUnitAt(end))) {
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
/// fenced code, any other file's comment lines.
List<NameMention> _readFile(
  String lf,
  String extension,
  Iterable<NameMention> Function(String line, int number) onLine,
) {
  if (extension != markdownExtension) {
    final lines = lf.split('\n');
    return [
      for (var i = 0; i < lines.length; i++)
        if (isCommentLine(lines[i], extension)) ...onLine(lines[i], i + 1),
    ];
  }
  final body = Doc.parse(lf).afterFrontmatter;
  final bodyStart = _breaksIn(lf.substring(0, lf.length - body.length));
  final lines = body.split('\n');
  final fenced = blockScan(lines).fenced;
  return [
    for (var i = 0; i < lines.length; i++)
      if (!fenced[i]) ...onLine(lines[i], bodyStart + i + 1),
  ];
}

int _breaksIn(String text) => '\n'.allMatches(text).length;
