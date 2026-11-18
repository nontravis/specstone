/// A `|` that a table row splits at: one preceded by an even run of
/// backslashes, zero included.
final tableCellPipe = RegExp(r'(?<=(?<!\\)(?:\\\\)*)\|');

final _bareCellPipe = RegExp(r'(?<!\\)((?:\\\\)*)\|');

/// Returns [text] with each `|` a table row would split at escaped as `\|`.
///
/// A `|` already escaped (an odd run of backslashes before it) stays as is.
String escapeTableCellPipes(String text) =>
    text.replaceAllMapped(_bareCellPipe, (match) => '${match[1]}\\|');
