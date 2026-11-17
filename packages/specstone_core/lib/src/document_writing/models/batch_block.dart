import 'package:specstone_core/src/index_query/read_answer.dart';

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
