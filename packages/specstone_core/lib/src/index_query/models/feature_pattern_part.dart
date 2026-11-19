import 'package:specstone_core/src/index_query/models/indexed_doc.dart';
import 'package:specstone_core/src/templates/models/checklist_item.dart';
import 'package:specstone_core/src/templates/models/feature_pattern.dart';

/// One feature pattern a design bundle prints right after its `lister`, the
/// doc that names it, with the `items` that part prints.
final class FeaturePatternPart {
  const new({required this.lister, required this.pattern, required this.items});

  final IndexedDoc lister;
  final FeaturePattern pattern;
  final List<ChecklistItem> items;
}
