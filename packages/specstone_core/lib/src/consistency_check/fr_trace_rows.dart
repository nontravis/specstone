/// One body line of a section: its text, file line, and fenced flag.
typedef TraceBodyLine = ({String text, int line, bool fenced});

/// One tracked row of an FR trace table: its first cell and file line.
typedef FrTraceRow = ({String cell, int line});

final _separatorCell = RegExp(r'^:?-+:?$');

/// Returns the rows of an FR trace table that `check` tracks.
///
/// [body] holds the section's lines. The first table row is the header; a
/// separator row and a fenced line are skipped. A cell is trimmed with one pair
/// of backticks dropped.
List<FrTraceRow> readFrTraceRows(List<TraceBodyLine> body) {
  final rows = <FrTraceRow>[];
  var sawHeader = false;
  for (final line in body) {
    final text = line.text.trim();
    if (line.fenced || !text.startsWith('|')) continue;
    final cell = _firstCell(text);
    if (!sawHeader) {
      sawHeader = true;
      continue;
    }
    if (_separatorCell.hasMatch(cell)) continue;
    rows.add((cell: _unquoted(cell), line: line.line));
  }
  return rows;
}

String _firstCell(String row) {
  final inner = row.substring(1);
  final end = inner.indexOf('|');
  return (end < 0 ? inner : inner.substring(0, end)).trim();
}

String _unquoted(String cell) =>
    cell.length > 1 && cell.startsWith('`') && cell.endsWith('`')
    ? cell.substring(1, cell.length - 1)
    : cell;
