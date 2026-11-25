import 'package:specstone_core/src/setup_migration/models/pack_step.dart';
import 'package:specstone_core/src/setup_migration/models/relink_rules.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/models/migration_step.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/pack_version.dart';

/// One pack's move from its pin to its available version, with the steps
/// between them.
final class PackUpgrade {
  const new({
    required this.pack,
    required this.pin,
    required this.target,
    required this.steps,
  });

  /// The pack name.
  final String pack;

  /// The version the project pins now.
  final PackVersion pin;

  /// The version the pin moves to.
  final PackVersion target;

  /// The steps to apply, each with the `from:` of the entry that holds it.
  final List<PackStep> steps;
}

/// Returns one [PackUpgrade] per pack whose pin is older than its available
/// version, in code point order of the pack name.
///
/// `steps` holds, for every entry with `pin <= from < target` in ascending
/// `from` order, its steps in list order; a pack with no such entry
/// changes its pin only.
///
/// A pin newer than the available version yields no upgrade: `chooseRun`
/// refuses `pack_pin_newer` before any upgrade is planned.
///
/// Throws [StateError] when a pinned pack has no available manifest; the
/// resolver refuses `pack_not_found` first, so that is a programming error.
List<PackUpgrade> selectUpgrades(
  Map<String, PackVersion> pins,
  Map<String, PackManifest> available,
) {
  final upgrades = <PackUpgrade>[];
  for (final pack in pins.keys.toList()..sort(compareCodePoints)) {
    final pin = pins[pack]!;
    final manifest = available[pack];
    if (manifest == null) {
      throw StateError('No available manifest for pinned pack "$pack".');
    }
    final target = manifest.version;
    if (pin.compareTo(target) >= 0) continue;
    upgrades.add(
      PackUpgrade(
        pack: pack,
        pin: pin,
        target: target,
        steps: _stepsBetween(manifest, pin, target),
      ),
    );
  }
  return upgrades;
}

/// The steps of each entry of [manifest] with `pin <= from < target`, in its
/// chain order.
///
/// A `relink_merged_docs` step carries the rules of every entry below its
/// own, whatever the pin, since a project past those entries runs them no
/// more.
List<PackStep> _stepsBetween(
  PackManifest manifest,
  PackVersion pin,
  PackVersion target,
) => [
  for (final index in manifest.chainOrder)
    if (manifest.migrations[index] case final migration
        when migration.from.compareTo(pin) >= 0 &&
            migration.from.compareTo(target) < 0)
      for (final step in migration.steps)
        PackStep(
          from: migration.from,
          step: step,
          relinkRules: step is RelinkMergedDocs
              ? _relinkRulesBelow(manifest, migration.from)
              : null,
        ),
];

/// The `merge_doc`, `drop_section`, and `rename_section` steps of each entry
/// of [manifest] whose `from` is below [from], in its chain order.
RelinkRules _relinkRulesBelow(PackManifest manifest, PackVersion from) {
  final earlier = [
    for (final index in manifest.chainOrder)
      if (manifest.migrations[index] case final migration
          when migration.from.compareTo(from) < 0)
        ...migration.steps,
  ];
  return RelinkRules(
    folds: earlier.whereType<MergeDoc>().toList(),
    drops: earlier.whereType<DropSection>().toList(),
    renames: earlier.whereType<RenameSection>().toList(),
  );
}
