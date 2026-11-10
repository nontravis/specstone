import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/document_writing/batch_fault.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';

const _textBeforeFirstBlock = 'text before the first naming line';
const _namingLineWithoutBase =
    'the naming line holds no base of 12 lowercase hex characters';
const _byteOrderMark = '﻿';
final _blankLine = RegExp(r'^[ \t]*$');

/// Returns the text of the batch file at [path], read as UTF-8.
///
/// A relative [path] is read from [workingDirectory]. Throws a file-level
/// [BatchFault] `argument_invalid` when [path] is missing, unreadable, a
/// folder, or holds bytes that are not UTF-8 text.
String readBatchFile(String path, {required Directory workingDirectory}) {
  final file = File(path).isAbsolute
      ? File(path)
      : File('${workingDirectory.path}${Platform.pathSeparator}$path');
  try {
    return utf8.decode(file.readAsBytesSync());
  } on FileSystemException {
    throw BatchFault.fileLevel(path, 'cannot read $path');
  } on FormatException {
    throw BatchFault.fileLevel(path, 'cannot read $path');
  }
}

/// One block of a batch file: a naming line and the text under it.
final class BatchBlock {
  const new({
    required this.line,
    required this.naming,
    required this.text,
    required this.leavesFenceOpen,
  });

  /// The 1-based line number of the naming line in the file.
  final int line;

  /// What the naming line names, its base set.
  final NamingLine naming;

  /// The lines under the naming line, each with its LF end, less the trailing
  /// blank lines.
  final String text;

  /// Whether a fence opens in the block and stays open to the file's end.
  final bool leavesFenceOpen;
}

/// Splits [text], a batch file read from [path], into its blocks.
///
/// A block starts at each line outside fenced code that [readNamingLine]
/// reads, and runs to the next one. A leading byte order mark and CRLF line
/// ends are dropped first. `lineFaults` holds, in file order, one
/// `argument_invalid` entry per non-blank line before the first naming line
/// and per naming line without a base; the latter starts no block. Throws a
/// file-level [BatchFault] when [text] holds no naming line outside fenced
/// code.
({List<BatchBlock> blocks, List<BatchEntry> lineFaults}) parseBatchFile(
  String path,
  String text,
) {
  final lines = _linesOf(text);
  final scan = blockScan(lines);
  final heads = <(int, NamingLine)>[
    for (var i = 0; i < lines.length; i++)
      if (!scan.fenced[i])
        if (readNamingLine(lines[i]) case final naming?) (i, naming),
  ];
  if (heads.isEmpty) {
    throw BatchFault.fileLevel(path, '$path holds no block');
  }

  final lineFaults = <BatchEntry>[];
  void refuseLine(int index, String message) => lineFaults.add(
    BatchEntry(
      code: IndexFaultCode.argumentInvalid.wire,
      message: message,
      file: path,
      line: index + 1,
    ),
  );

  for (var i = 0; i < heads.first.$1; i++) {
    if (!_blankLine.hasMatch(lines[i])) refuseLine(i, _textBeforeFirstBlock);
  }
  final blocks = <BatchBlock>[];
  for (var h = 0; h < heads.length; h++) {
    final (index, naming) = heads[h];
    if (naming.base == null) {
      refuseLine(index, _namingLineWithoutBase);
      continue;
    }
    final isLast = h == heads.length - 1;
    final end = isLast ? lines.length : heads[h + 1].$1;
    blocks.add(
      BatchBlock(
        line: index + 1,
        naming: naming,
        text: _blockText(lines.sublist(index + 1, end)),
        leavesFenceOpen: isLast && scan.openFence != null,
      ),
    );
  }
  return (blocks: blocks, lineFaults: lineFaults);
}

/// Returns the lines of [text] with LF line ends, its BOM and the empty line
/// after its last line end dropped.
List<String> _linesOf(String text) {
  final withoutMark = text.startsWith(_byteOrderMark)
      ? text.substring(_byteOrderMark.length)
      : text;
  final lines = withoutMark.replaceAll('\r\n', '\n').split('\n');
  if (lines.last.isEmpty) lines.removeLast();
  return lines;
}

String _blockText(List<String> lines) {
  var end = lines.length;
  while (end > 0 && _blankLine.hasMatch(lines[end - 1])) {
    end--;
  }
  return [for (final line in lines.take(end)) '$line\n'].join();
}
