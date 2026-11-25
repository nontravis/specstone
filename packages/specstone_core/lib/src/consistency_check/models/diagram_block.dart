import 'package:specstone_core/src/doc_model/models/body_line.dart';

/// One `mermaid` diagram block: its opening-fence line and body lines.
final class DiagramBlock {
  const new({required this.fenceLine, required this.lines});

  final int fenceLine;
  final List<BodyLine> lines;
}
