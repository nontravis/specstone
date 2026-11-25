/// What a [SectionItem] is.
enum SectionItemKind { listItem, tableRow, paragraph, heading }

/// One item of a section, with what a rule reads.
///
/// `line` is its first file line; `head` its first line after any `>` mark,
/// list marker, `### `, or a table row's opening pipe and its blanks;
/// `firstLine` that line with its marker, after any
/// `>` marks; `text` its own lines as written, nested items aside. `nested`
/// is true for an item that opens indented. A table row carries its table's
/// `header` cells and its own `cells`, both trimmed; every other kind carries
/// null for both.
final class SectionItem {
  const new({
    required this.line,
    required this.kind,
    required this.nested,
    required this.head,
    required this.firstLine,
    required this.text,
    required this.header,
    required this.cells,
  });

  final int line;
  final SectionItemKind kind;
  final bool nested;
  final String head;
  final String firstLine;
  final String text;
  final List<String>? header;
  final List<String>? cells;
}
