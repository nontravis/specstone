import 'package:specstone_core/src/templates/models/migration_step.dart';
import 'package:specstone_core/src/templates/pack_version.dart';

/// One migration step, and the `from:` of the entry that holds it.
final class PackStep {
  const new({required this.from, required this.step});

  final PackVersion from;

  final MigrationStep step;
}
