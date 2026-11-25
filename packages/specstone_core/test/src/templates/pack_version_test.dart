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
    test('reads major, minor, and patch', () {
      final version = _parse('2.10.3');

      expect(version.major, 2);
      expect(version.minor, 10);
      expect(version.patch, 3);
      expect(version.toString(), '2.10.3');
    });

    test('a leading zero is pack_version_invalid', () {
      for (final (text, reason) in [
        ('01.2.0', 'leading zero'),
        ('1.2', 'two parts'),
        ('1.2.0-beta', 'pre-release tag'),
        ('', 'empty text'),
      ]) {
        expect(() => _parse(text), throwsA(_invalid()), reason: reason);
      }
    });

    test('a number past the int range is '
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

    test('reads a plain scalar', () {
      expect(read('v: 1.2.0\n').toString(), '1.2.0');
    });

    test('a YAML double keeps its written form', () {
      expect(() => read('v: 1.10\n'), throwsA(_invalid()));
    });

    test('a list is pack_version_invalid', () {
      for (final (text, reason) in [
        ('v: [1, 2, 3]\n', 'list'),
        ('v: {a: 1}\n', 'mapping'),
      ]) {
        expect(() => read(text), throwsA(_invalid()), reason: reason);
      }
    });
  });

  group('PackVersion ordering', () {
    test('compares by semver precedence', () {
      final ordered = ['1.0.0', '1.0.1', '1.1.0', '2.0.0'].map(_parse).toList();

      for (var i = 0; i < ordered.length - 1; i++) {
        expect(ordered[i].compareTo(ordered[i + 1]), lessThan(0));
        expect(ordered[i + 1].compareTo(ordered[i]), greaterThan(0));
      }
    });

    test('compares numbers, not text', () {
      expect(_parse('1.10.0').compareTo(_parse('1.9.0')), greaterThan(0));
    });

    test('equal versions are equal with equal hash codes', () {
      expect(_parse('1.2.3'), _parse('1.2.3'));
      expect(_parse('1.2.3').hashCode, _parse('1.2.3').hashCode);
      expect(_parse('1.2.3') == _parse('1.2.4'), isFalse);
    });
  });
}
