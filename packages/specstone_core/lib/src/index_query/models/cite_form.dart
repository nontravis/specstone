import 'package:specstone_core/src/index_query/models/cite_candidate.dart';
import 'package:specstone_core/src/index_query/models/cite_item_at.dart';

/// A cite candidate with its place on its line, which the cite pass rewrites.
///
/// `start` and `end` are the 0-based columns the doc part spans, its code
/// span's backticks, `#key`, and header span included; `runAt` is the column
/// of the first ID of its run, a lettered one included, or `end` when the run
/// is empty; `items` holds each item ID it owns, repeats included.
final class CiteForm {
  const new({
    required this.candidate,
    required this.start,
    required this.end,
    required this.runAt,
    required this.items,
  });

  final CiteCandidate candidate;
  final int start;
  final int end;
  final int runAt;
  final List<CiteItemAt> items;
}
