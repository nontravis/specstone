const _byteOrderMark = '﻿';

final _edgeBlanks = RegExp(r'^[ \t]+|[ \t]+$');

/// One report file: the path as the call named it and its decoded text.
final class ReportFile {
  const new({required this.path, required this.text});

  final String path;
  final String text;

  /// The last segment of [path], for the reasons that name a file.
  String get name => path.split(RegExp(r'[/\\]')).last;
}

/// Splits [text] into lines, dropping a leading byte order mark and each
/// trailing `\r`.
List<String> reportLinesOf(String text) {
  final body = text.startsWith(_byteOrderMark) ? text.substring(1) : text;
  return [
    for (final line in body.split('\n'))
      if (line.endsWith('\r')) line.substring(0, line.length - 1) else line,
  ];
}

/// Returns [line] without its leading and trailing spaces and tabs.
String trimmedReportLine(String line) => line.replaceAll(_edgeBlanks, '');
