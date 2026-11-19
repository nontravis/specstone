import 'package:specstone_core/src/doc_model/models/body_line.dart';

/// A `### PG-` block of a goal doc: its doc, ID, horizon, and lines.
final class GoalBlock {
  const new({
    required this.docPath,
    required this.key,
    required this.horizon,
    required this.lines,
  });

  final String docPath;
  final String key;
  final int horizon;
  final List<BodyLine> lines;
}
