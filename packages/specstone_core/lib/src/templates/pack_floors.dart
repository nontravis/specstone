import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/version.dart';

/// The oldest version of each shipped pack this Specstone reads.
///
/// A floor is the version Specstone 2.0.0 carried, so a personal pack has none.
final class PackFloors {
  new(Map<String, PackVersion> floors) : byPack = Map.unmodifiable(floors);

  /// The floors of the packs this binary ships.
  static final PackFloors shipped = PackFloors({
    for (final MapEntry(:key, :value) in _shippedFloorTexts.entries)
      key: PackVersion.parse(value, file: 'pack_floors.dart', key: key),
  });

  /// No floors, for a resolver built over fixture packs.
  static final PackFloors none = PackFloors({});

  /// The floor of each pack, by pack name.
  final Map<String, PackVersion> byPack;

  /// Returns `pack_pin_below_floor` for the first pack of [pins], in code
  /// point order, whose pin sits under its floor; null when none does.
  ///
  /// A pack with no floor never faults.
  TemplateFault? firstBelow(Map<String, PackVersion> pins) {
    final names = pins.keys.toList()..sort(compareCodePoints);
    for (final name in names) {
      final floor = byPack[name];
      final pin = pins[name]!;
      if (floor == null || pin.compareTo(floor) >= 0) continue;
      return TemplateFault(
        FaultCode.packPinBelowFloor,
        '$name $pin is below $floor, the oldest version Specstone '
        '$specstoneVersion reads; migrate the project with Specstone 2.0.x '
        'first',
        file: projectConfigPath,
        key: 'packs.$name',
      );
    }
    return null;
  }
}

const _shippedFloorTexts = {
  'agent-skills': '1.1.0',
  'marketing': '1.5.0',
  'personal-branding': '1.2.0',
  'prd-core': '1.31.0',
  'software-design-system': '1.4.0',
  'software-tech': '1.25.0',
};
