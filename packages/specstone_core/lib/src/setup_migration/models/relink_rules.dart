import 'package:specstone_core/src/templates/models/migration_step.dart';

/// The link rules a `relink_merged_docs` step reads from the earlier entries
/// of its pack, each list in chain order.
final class RelinkRules {
  const new({required this.folds, required this.drops, required this.renames});

  final List<MergeDoc> folds;

  final List<DropSection> drops;

  final List<RenameSection> renames;

  /// Whether no rule is held, so the step changes nothing.
  bool get isEmpty => folds.isEmpty && drops.isEmpty && renames.isEmpty;
}
