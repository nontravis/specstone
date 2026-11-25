import 'dart:convert';

import 'package:specstone_core/src/templates/pack_floors.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/version.dart';
import 'package:test/test.dart';

PackVersion _version(String text) =>
    PackVersion.parse(text, file: 'test', key: 'version');

void main() {
  group('PackFloors.shipped', () {
    test('holds the six floors of Specstone 2.0.0', () {
      expect(
        {
          for (final MapEntry(:key, :value)
              in PackFloors.shipped.byPack.entries)
            key: value.toString(),
        },
        {
          'prd-core': '1.31.0',
          'software-tech': '1.25.0',
          'agent-skills': '1.1.0',
          'software-design-system': '1.4.0',
          'marketing': '1.5.0',
          'personal-branding': '1.2.0',
        },
      );
    });

    test('holds only shipped pack names', () {
      final shippedNames = {
        for (final key in shippedPackFiles.keys) key.split('/').first,
      };

      expect(PackFloors.shipped.byPack.keys.toSet(), shippedNames);
    });

    test('each carried pack version is at or above its floor', () {
      for (final MapEntry(:key, :value) in PackFloors.shipped.byPack.entries) {
        final carried = PackManifest.parse(
          utf8.decode(shippedPackFiles['$key/pack.yaml']!),
          file: 'packs/$key/pack.yaml',
        ).version;

        expect(carried.compareTo(value), greaterThanOrEqualTo(0), reason: key);
      }
    });
  });

  group('PackFloors.firstBelow', () {
    final floors = PackFloors({
      'prd-core': _version('1.31.0'),
      'software-tech': _version('1.25.0'),
    });

    test('returns null when every pin is at or above its floor', () {
      expect(
        floors.firstBelow({
          'prd-core': _version('1.31.0'),
          'software-tech': _version('1.26.0'),
        }),
        isNull,
      );
    });

    test('returns null for a pack with no floor', () {
      expect(floors.firstBelow({'nont-software': _version('0.1.0')}), isNull);
    });

    test('names the first pack in code point order under its floor', () {
      final fault = floors.firstBelow({
        'software-tech': _version('1.24.0'),
        'prd-core': _version('1.30.0'),
      })!;

      expect(fault.code, FaultCode.packPinBelowFloor);
      expect(fault.file, '.specstone/config.yaml');
      expect(fault.key, 'packs.prd-core');
      expect(
        fault.message,
        'prd-core 1.30.0 is below 1.31.0, the oldest version Specstone '
        '$specstoneVersion reads; migrate the project with Specstone 2.0.x '
        'first',
      );
    });
  });

  test('PackFloors.none holds no floor', () {
    expect(PackFloors.none.byPack, isEmpty);
    expect(PackFloors.none.firstBelow({'prd-core': _version('0.0.1')}), isNull);
  });
}
