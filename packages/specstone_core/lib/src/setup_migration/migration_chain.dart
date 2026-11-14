import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/pack_migration.dart';
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
  final List<({PackVersion from, MigrationStep step})> steps;
}

/// Returns one [PackUpgrade] per pack whose pin is older than its available
/// version, in code point order of the pack name.
///
/// `steps` holds, for every entry with `pin <= from < target` in ascending
/// `from` order, its steps in list order (INV-10); a pack with no such entry
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
        steps: _stepsBetween(manifest.migrations, pin, target),
      ),
    );
  }
  return upgrades;
}

List<({PackVersion from, MigrationStep step})> _stepsBetween(
  List<PackMigration> migrations,
  PackVersion pin,
  PackVersion target,
) {
  // List.sort is not stable; the file index keeps equal `from` in file order.
  final inRange =
      [
        for (final (index, migration) in migrations.indexed)
          if (migration.from.compareTo(pin) >= 0 &&
              migration.from.compareTo(target) < 0)
            (index: index, migration: migration),
      ]..sort((a, b) {
        final byFrom = a.migration.from.compareTo(b.migration.from);
        return byFrom != 0 ? byFrom : a.index.compareTo(b.index);
      });
  return [
    for (final (:migration, index: _) in inRange)
      for (final step in migration.steps) (from: migration.from, step: step),
  ];
}

/// The pack whose release names tests in the records.
const testNamePack = 'software-tech';

/// The [testNamePack] version from which a record holds `tests` lines, so the
/// upgrade that reaches it moves each test name's ID into them.
final PackVersion testNamePassSince = PackVersion.parse(
  '1.6.0',
  file: 'migration_chain.dart',
  key: testNamePack,
);

/// Whether [upgrades] move the [testNamePack] pin from below [since] to [since]
/// or later: the one trigger of the test-name pass.
///
/// [since] defaults to [testNamePassSince].
bool runsTestNamePass(List<PackUpgrade> upgrades, {PackVersion? since}) {
  final floor = since ?? testNamePassSince;
  return upgrades.any(
    (upgrade) =>
        upgrade.pack == testNamePack &&
        upgrade.pin.compareTo(floor) < 0 &&
        upgrade.target.compareTo(floor) >= 0,
  );
}

/// Whether a legacy run, which pins each carried pack at its available
/// version from no pin at all, chains through the test-name pass: the pin it
/// writes for [testNamePack] is [since] or later.
bool legacyRunsTestNamePass(
  Map<String, PackVersion> pins, {
  PackVersion? since,
}) {
  final pin = pins[testNamePack];
  return pin != null && pin.compareTo(since ?? testNamePassSince) >= 0;
}
