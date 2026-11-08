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

Iterable<NameMention> _mentionsOnLine(String line, int number) sync* {
  for (final (:start, :end, :ticks) in codeSpansOf(line)) {
    final text = line.substring(start + ticks, end - ticks);
    final address = readDocAddress(text);
    if (!address.isReferenceWithoutLookup) continue;
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
/// roots or a doc, each at its line of the file.
///
/// Markdown is read after its frontmatter, as a doc is; any other file by
/// its comment lines.
List<NameMention> nameMentionsInFile(String lf, String extension) {
  if (extension != markdownExtension) {
    return nameMentionsInComments(lf, extension);
  }
  if (!lf.contains('`')) return const [];
  final body = Doc.parse(lf).afterFrontmatter;
  final bodyStart = _breaksIn(lf.substring(0, lf.length - body.length));
  return [
    for (final m in nameMentionsInMarkdown(body))
      (
        line: bodyStart + m.line,
        column: m.column,
        text: m.text,
        address: m.address,
      ),
  ];
}

int _breaksIn(String text) => '\n'.allMatches(text).length;
