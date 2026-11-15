import 'package:specstone_core/src/doc_model/doc.dart' show fencedLines;
import 'package:specstone_core/src/doc_model/markdown_lines.dart'
    show startsTable;

final _carriageReturn = RegExp(r'\r$');

/// Returns [body] cut to the lines before its first table, that table's
/// header and delimiter rows, and its first [rows] body rows, with the number
/// of lines that cut prints.
///
/// A table inside fenced code is no table. A body with no table stays whole,
/// and a table of fewer than [rows] body rows keeps every row. A table ends at
/// its first blank line.
({String body, int lineCount}) cutToRows(String body, int rows) {
  final lines = body.split('\n');
  final scanned = [
    for (final line in lines) line.replaceFirst(_carriageReturn, ''),
  ];
  final fenced = fencedLines(scanned);
  final header = _tableHeaderAt(scanned, fenced);
  if (header == null) {
    return (body: body, lineCount: _lineCountOf(body.trimRight()));
  }
  var end = header + 2;
  final lastRow = end + rows;
  while (end < lastRow &&
      end < lines.length &&
      scanned[end].trim().isNotEmpty &&
      !fenced[end]) {
    end++;
  }
  return (body: lines.take(end).join('\n'), lineCount: end);
}

/// Returns the index of the header line of the first table of [lines] outside
/// fenced code, or null when none starts.
int? _tableHeaderAt(List<String> lines, List<bool> fenced) {
  for (var at = 0; at + 1 < lines.length; at++) {
    if (fenced[at] || fenced[at + 1] || lines[at].trim().isEmpty) continue;
    if (startsTable(lines[at], lines[at + 1])) return at;
  }
  return null;
}

int _lineCountOf(String text) => '\n'.allMatches(text).length + 1;
