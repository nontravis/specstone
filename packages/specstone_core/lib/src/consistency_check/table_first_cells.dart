import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/doc_model/markdown_lines.dart'
    show tableCellRanges, tableHeadCells;
import 'package:specstone_core/src/doc_model/models/body_line.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';

/// Returns the first cell of each body row of the section [sectionId] of
/// [doc], one pair of backticks dropped.
Iterable<String> firstCellsOf(
  CheckContext context,
  IndexedDoc doc,
  String sectionId,
) sync* {
  final index = context.heldIndexOf(doc, sectionId);
  if (index == null) return;
  for (final table in tablesOf(context.bodyLinesOf(doc, index))) {
    for (final row in table.rows) {
      final cell = cellAt(row.text, 0);
      if (cell != null && cell.isNotEmpty) yield unquoted(cell);
    }
  }
}

/// Returns each table of [body]: its header cells and body rows.
List<BodyTable> tablesOf(List<BodyLine> body) {
  final tables = <BodyTable>[];
  var k = 0;
  while (k + 1 < body.length) {
    if (body[k].fenced || body[k + 1].fenced) {
      k++;
      continue;
    }
    final cells = tableHeadCells(body[k].text, body[k + 1].text);
    if (cells == null) {
      k++;
      continue;
    }
    var end = k + 2;
    while (end < body.length && _isRow(body[end])) {
      end++;
    }
    tables.add(
      BodyTable(
        header: [
          for (final cell in cells)
            body[k].text.substring(cell.start, cell.end).trim(),
        ],
        rows: body.sublist(k + 2, end),
      ),
    );
    k = end;
  }
  return tables;
}

bool _isRow(BodyLine line) => !line.fenced && line.text.trim().startsWith('|');

/// Returns the trimmed cell [at] of the table [row], or null when [at] is
/// negative or past the row's last cell.
String? cellAt(String row, int at) {
  if (at < 0) return null;
  final cells = tableCellRanges(row);
  return at < cells.length
      ? row.substring(cells[at].start, cells[at].end).trim()
      : null;
}

/// Returns [cell] without one pair of backticks around it.
String unquoted(String cell) =>
    cell.length > 1 && cell.startsWith('`') && cell.endsWith('`')
    ? cell.substring(1, cell.length - 1)
    : cell;

/// A table of a body: its header cells and its body rows.
final class BodyTable {
  const new({required this.header, required this.rows});

  final List<String> header;
  final List<BodyLine> rows;
}
