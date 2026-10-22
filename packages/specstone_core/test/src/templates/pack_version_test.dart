import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const _file = 'packs/x/pack.yaml';

PackVersion _parse(String text) =>
    PackVersion.parse(text, file: _file, key: 'version');

TypeMatcher<TemplateFault> _invalid() => isA<TemplateFault>()
    .having((f) => f.code, 'code', FaultCode.packVersionInvalid)
    .having((f) => f.file, 'file', _file)
    .having((f) => f.key, 'key', 'version');

void main() {
  group('PackVersion.parse', () {
    test('f03/us04/fr01: reads major, minor, and patch', () {
      final version = _parse('2.10.3');

      expect(version.major, 2);
      expect(version.minor, 10);
      expect(version.patch, 3);
      expect(version.toString(), '2.10.3');
    });

    test(
      'f03/us04/fr01/e06, s03/inv16: a leading zero is pack_version_invalid',
      () {
        expect(() => _parse('01.2.0'), throwsA(_invalid()));
      },
    );

    test(
      'f03/us04/fr01/e06, s03/inv16: two parts are pack_version_invalid',
      () {
        expect(() => _parse('1.2'), throwsA(_invalid()));
      },
    );

    test(
      'f03/us05/fr01/e06, s03/inv16: a pre-release tag is pack_version_invalid',
      () {
        expect(() => _parse('1.2.0-beta'), throwsA(_invalid()));
      },
    );

    test('f03/us04/fr01/e06: empty text is pack_version_invalid', () {
      expect(() => _parse(''), throwsA(_invalid()));
    });

    test('f03/us05/fr01, s03/inv16: a number past the int range is '
        'pack_version_invalid', () {
      expect(() => _parse('99999999999999999999.0.0'), throwsA(_invalid()));
      expect(() => _parse('1.99999999999999999999.0'), throwsA(_invalid()));
      expect(() => _parse('1.0.99999999999999999999'), throwsA(_invalid()));
    });
  });

  group('PackVersion.fromYaml', () {
    PackVersion read(String text) {
      final map = loadYaml(text) as YamlMap;
      return PackVersion.fromYaml(map.nodes['v']!, file: _file, key: 'version');
    }

    test('f03/us04/fr01: reads a plain scalar', () {
      expect(read('v: 1.2.0\n').toString(), '1.2.0');
    });

    test('f03/us04/fr01: reads a quoted string without its quotes', () {
      expect(read("v: '1.2.0'\n").toString(), '1.2.0');
    });

    test('f03/us04/fr01/e06: a YAML double keeps its written form', () {
      expect(() => read('v: 1.10\n'), throwsA(_invalid()));
    });

    test('f03/us04/fr01/e06: a list is pack_version_invalid', () {
      expect(() => read('v: [1, 2, 3]\n'), throwsA(_invalid()));
    });

    test('f03/us04/fr01/e06: a mapping is pack_version_invalid', () {
      expect(() => read('v: {a: 1}\n'), throwsA(_invalid()));
    });
  });

  group('PackVersion ordering', () {
    test('s03/inv16: compares by semver precedence', () {
      final ordered = ['1.0.0', '1.0.1', '1.1.0', '2.0.0'].map(_parse).toList();

      for (var i = 0; i < ordered.length - 1; i++) {
        expect(ordered[i].compareTo(ordered[i + 1]), lessThan(0));
        expect(ordered[i + 1].compareTo(ordered[i]), greaterThan(0));
      }
    });

    test('s03/inv16: compares numbers, not text', () {
      expect(_parse('1.10.0').compareTo(_parse('1.9.0')), greaterThan(0));
    });

    test('equal versions are equal with equal hash codes', () {
      expect(_parse('1.2.3'), _parse('1.2.3'));
      expect(_parse('1.2.3').hashCode, _parse('1.2.3').hashCode);
      expect(_parse('1.2.3') == _parse('1.2.4'), isFalse);
    });
  });
}
