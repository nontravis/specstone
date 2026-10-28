import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:test/test.dart';

const _file = 'packs/x/pack.yaml';

PackManifest _parse(String text) => PackManifest.parse(text, file: _file);

TypeMatcher<TemplateFault> _fault(FaultCode code, {String? key, int? line}) =>
    isA<TemplateFault>()
        .having((f) => f.code, 'code', code)
        .having((f) => f.file, 'file', _file)
        .having((f) => f.key, 'key', key)
        .having((f) => f.line, 'line', line);

void main() {
  group('PackManifest.parse', () {
    test('f03/us04/fr01: reads name, version, and file', () {
      final manifest = _parse('name: software-tech\nversion: 1.2.0\n');

      expect(manifest.name, 'software-tech');
      expect(manifest.version.toString(), '1.2.0');
      expect(manifest.extendsPack, isNull);
      expect(manifest.file, _file);
    });

    test('f03/us04/fr01: reads the extends key', () {
      final manifest = _parse(
        'name: team\nversion: 1.0.0\nextends: software-tech\n',
      );

      expect(manifest.extendsPack, 'software-tech');
    });

    test(
      'f03/us04/fr01/e04, s03/inv10: a manifest without version is missing_key',
      () {
        expect(
          () => _parse('name: x\n'),
          throwsA(_fault(FaultCode.missingKey, key: 'version')),
        );
      },
    );

    test(
      'f03/us04/fr01/e04, s03/inv10: a manifest without name is missing_key',
      () {
        expect(
          () => _parse('version: 1.0.0\n'),
          throwsA(_fault(FaultCode.missingKey, key: 'name')),
        );
      },
    );

    test('f03/us04/fr01/e06, s03/inv16: a list version is invalid', () {
      expect(
        () => _parse('name: x\nversion: [1.0.0]\n'),
        throwsA(_fault(FaultCode.packVersionInvalid, key: 'version')),
      );
    });

    test(
      'f03/us04/fr01/e06, s03/inv16: a leading zero in version is invalid',
      () {
        expect(
          () => _parse('name: x\nversion: 01.2.0\n'),
          throwsA(_fault(FaultCode.packVersionInvalid, key: 'version')),
        );
      },
    );

    test('f03/us04/fr01/e06: an unquoted double version is invalid', () {
      expect(
        () => _parse('name: x\nversion: 1.2\n'),
        throwsA(_fault(FaultCode.packVersionInvalid, key: 'version')),
      );
    });

    test('f03/us04/fr01/e08: a YAML syntax error carries its line', () {
      expect(
        () => _parse('name: [\n'),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.yamlSyntax)
              .having((f) => f.file, 'file', _file)
              .having((f) => f.line, 'line', isNotNull),
        ),
      );
    });

    test('f03/us04/fr01/e08: an unknown key is unknown_key', () {
      expect(
        () => _parse('name: x\nversion: 1.0.0\nowner: me\n'),
        throwsA(_fault(FaultCode.unknownKey, key: 'owner')),
      );
    });

    test('f03/us04/fr01/e08: an unknown key wins over a missing key', () {
      expect(
        () => _parse('owner: me\n'),
        throwsA(_fault(FaultCode.unknownKey, key: 'owner')),
      );
    });

    test('f06/us02/fr01/e02: a pack.yaml with no migrations key has none', () {
      final manifest = _parse('name: p\nversion: 1.0.0\n');

      expect(manifest.migrations, isEmpty);
    });

    test('f06/us02/fr01: pack.yaml accepts migrations', () {
      final manifest = _parse('''
name: p
version: 1.0.0
migrations:
  - from: 1.0.0
    steps:
      - rename_section: {doc_type: runbook, from: {id: steps, header: Steps}, to: {id: procedure, header: Procedure}}
  - from: 1.1.0
    steps:
      - rename_field: {doc_type: runbook, from: owner, to: on_call}
      - move_file: {doc_type: runbook, from: "prds/runbooks/{slug}/RUNBOOK.md", to: "ops/runbooks/{slug}.md"}
''');

      expect(manifest.migrations.map((m) => '${m.from}'), ['1.0.0', '1.1.0']);
    });

    test(
      'f06/us02/fr01/e06: migrations that is not a list is unknown_value',
      () {
        expect(
          () => _parse('name: p\nversion: 1.0.0\nmigrations: {}\n'),
          throwsA(_fault(FaultCode.unknownValue, key: 'migrations')),
        );
      },
    );
  });
}
