import 'package:specstone_core/src/doc_model/doc.dart' show fencedLines;
import 'package:specstone_core/src/doc_model/doc_items.dart' show firstTableOf;
import 'package:specstone_core/src/doc_model/models/body_line.dart';
import 'package:specstone_core/src/index_query/html_comments.dart';

final _carriageReturn = RegExp(r'\r$');

/// Returns [body] cut to the lines before its first table, that table's
/// header and delimiter rows, and its first [rows] body rows, with the number
/// of lines that cut prints.
///
/// The first table is the one the doc model reads: outside fenced code and
/// HTML comments, in a blockquote or a list item as anywhere else. A body
/// with no table stays whole, and a table of fewer than [rows] body rows
/// keeps every row.
({String body, int lineCount}) cutToRows(String body, int rows) {
  final lines = body.split('\n');
  final tableEnd = firstTableOf(_scannedLines(body, lines), rows);
  if (tableEnd == null) {
    return (body: body, lineCount: _lineCountOf(body.trimRight()));
  }
  return (body: lines.take(tableEnd).join('\n'), lineCount: tableEnd);
}

/// Returns the lines of [body] as the doc model reads them, each comment
/// blanked in place so every line count stays.
List<BodyLine> _scannedLines(String body, List<String> lines) {
  final scanned = _blankComments(body).split('\n');
  final plain = [
    for (final line in scanned) line.replaceFirst(_carriageReturn, ''),
  ];
  final fenced = fencedLines([
    for (final line in lines) line.replaceFirst(_carriageReturn, ''),
  ]);
  return [
    for (var at = 0; at < lines.length; at++)
      BodyLine(text: plain[at], line: at + 1, fenced: fenced[at]),
  ];
}

String _blankComments(String text) {
  final blanked = StringBuffer();
  var from = 0;
  for (final (:start, :end) in commentRangesOf(text)) {
    blanked
      ..write(text.substring(from, start))
      ..write(text.substring(start, end).replaceAll(RegExp(r'[^\n]'), ' '));
    from = end;
  }
  return (blanked..write(text.substring(from))).toString();
}

int _lineCountOf(String text) => '\n'.allMatches(text).length + 1;
