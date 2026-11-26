import 'package:specstone_core/src/setup_migration/models/relink_rules.dart';
import 'package:specstone_core/src/templates/models/migration_step.dart';
import 'package:specstone_core/src/templates/pack_version.dart';

/// One migration step, and the `from:` of the entry that holds it.
final class PackStep {
  const new({
    required this.from,
    required this.step,
    required this.file,
    required this.entryIndex,
    required this.stepIndex,
    this.relinkRules,
  });

  final PackVersion from;

  /// The `pack.yaml` the step was read from, as pack load faults print it.
  final String file;

  /// The index of the step's entry in the pack's `migrations:` list.
  final int entryIndex;

  /// The index of the step in its entry.
  final int stepIndex;

  final MigrationStep step;

  /// The link rules of the pack's earlier entries, set only on a
  /// [RelinkMergedDocs] step.
  final RelinkRules? relinkRules;
}
