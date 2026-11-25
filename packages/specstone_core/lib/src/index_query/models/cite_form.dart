import 'package:specstone_core/src/index_query/models/cite_candidate.dart';
import 'package:specstone_core/src/index_query/models/cite_item_at.dart';

/// A cite candidate with the item IDs it owns, repeats included.
final class CiteForm {
  const new({required this.candidate, required this.items});

  final CiteCandidate candidate;
  final List<CiteItemAt> items;
}
