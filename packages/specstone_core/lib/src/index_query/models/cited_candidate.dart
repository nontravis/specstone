import 'package:specstone_core/src/index_query/models/cited_by.dart';
import 'package:specstone_core/src/index_query/models/line_range.dart';

/// An item or `###` block of a section that other docs cite: its ID or
/// anchor, the file lines it spans, and the lines that cite it.
final class CitedCandidate {
  const new({required this.id, required this.extent, required this.by});

  final String id;
  final LineRange extent;
  final List<CitedBy> by;
}
