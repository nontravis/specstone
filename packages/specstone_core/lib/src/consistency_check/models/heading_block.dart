import 'package:specstone_core/src/doc_model/models/body_line.dart';

/// A `###` block of a body: the key its heading names, and its lines, the
/// heading first.
final class HeadingBlock {
  const new({required this.key, required this.lines});

  final String key;
  final List<BodyLine> lines;
}
