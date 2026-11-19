import 'dart:convert';
import 'dart:typed_data';

import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/temp_tree.dart';

const _file = 'packs/x/pack.yaml';

PackManifest _parse(String text) => PackManifest.parse(text, file: _file);

TypeMatcher<TemplateFault> _fault(FaultCode code, {String? key, int? line}) =>
    isA<TemplateFault>()
        .having((f) => f.code, 'code', code)
        .having((f) => f.file, 'file', _file)
        .having((f) => f.key, 'key', key)
        .having((f) => f.line, 'line', line);

const _personalFile = '~/.specstone/packs/x/pack.yaml';

/// Returns the fault a template load raises for a listed personal pack `x`
/// whose home `pack.yaml` holds [text].
Future<TemplateFault> _faultOf(String text) async {
  final project = await writeTree({
    '.specstone/config.yaml': 'packs:\n  prd-core: 1.1.0\n  x: 1.0.0\n',
  });
  final home = await writeTree({'.specstone/packs/x/pack.yaml': text});
  final resolver = TemplateResolver(
    shippedFiles: {
      'prd-core/pack.yaml': Uint8List.fromList(
        utf8.encode('name: prd-core\nversion: 1.1.0\n'),
      ),
    },
  );
  try {
    resolver.resolve(workingDirectory: project, homeDirectory: home);
  } on TemplateFault catch (fault) {
    return fault;
  }
  fail('expected a TemplateFault');
}

void main() {
  group('PackManifest.parse', () {
    test('reads name, version, and file', () {
      final manifest = _parse('name: software-tech\nversion: 1.2.0\n');

      expect(manifest.name, 'software-tech');
      expect(manifest.version.toString(), '1.2.0');
      expect(manifest.extendsPack, isNull);
      expect(manifest.file, _file);
    });

    test('reads the extends key', () {
      final manifest = _parse(
        'name: team\nversion: 1.0.0\nextends: software-tech\n',
      );

      expect(manifest.extendsPack, 'software-tech');
    });

    test('a manifest without version is missing_key', () {
      expect(
        () => _parse('name: x\n'),
        throwsA(_fault(FaultCode.missingKey, key: 'version')),
      );
    });

    test('a manifest without name is missing_key', () {
      expect(
        () => _parse('version: 1.0.0\n'),
        throwsA(_fault(FaultCode.missingKey, key: 'name')),
      );
    });

    test('a list version is invalid', () {
      expect(
        () => _parse('name: x\nversion: [1.0.0]\n'),
        throwsA(_fault(FaultCode.packVersionInvalid, key: 'version')),
      );
    });

    test('shared_lines and shared_fields parse into shared in file order', () {
      final manifest = _parse('''
name: team
version: 1.0.0
shared_lines:
  - id: b_line
    text: Second by name, first in the file.
  - id: a_line
    text: First by name, second in the file.
shared_fields:
  - id: b_field
    type: string
    for_doc_types: [story]
  - id: a_field
    type: string
    for_doc_types: [story]
''');

      expect(manifest.shared.lines.map((l) => l.id), ['b_line', 'a_line']);
      expect(manifest.shared.fields.map((f) => f.id), ['b_field', 'a_field']);
      expect(manifest.shared.lines.first.file, _file);
    });

    test('a manifest with neither shared key holds no shared entries', () {
      final manifest = _parse('name: x\nversion: 1.0.0\n');

      expect(manifest.shared.lines, isEmpty);
      expect(manifest.shared.fields, isEmpty);
    });

    test('a leading zero in version is invalid', () {
      expect(
        () => _parse('name: x\nversion: 01.2.0\n'),
        throwsA(_fault(FaultCode.packVersionInvalid, key: 'version')),
      );
    });

    test('an unquoted double version is invalid', () {
      expect(
        () => _parse('name: x\nversion: 1.2\n'),
        throwsA(_fault(FaultCode.packVersionInvalid, key: 'version')),
      );
    });

    test('a YAML syntax error carries its line', () {
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

    test('an unknown key is unknown_key', () {
      expect(
        () => _parse('name: x\nversion: 1.0.0\nowner: me\n'),
        throwsA(_fault(FaultCode.unknownKey, key: 'owner')),
      );
    });

    test('an unknown key wins over a missing key', () {
      expect(
        () => _parse('owner: me\n'),
        throwsA(_fault(FaultCode.unknownKey, key: 'owner')),
      );
    });

    test('a personal pack.yaml with no name or no version refuses with '
        'status 78', () async {
      for (final (text, key) in [
        ('version: 1.0.0\n', 'name'),
        ('name: x\n', 'version'),
      ]) {
        final fault = await _faultOf(text);
        expect(fault.code, FaultCode.missingKey, reason: text);
        expect(fault.key, key, reason: text);
        expect(fault.file, _personalFile, reason: text);
        expect(fault.exitStatus, 78, reason: text);
      }
    });

    test('a personal pack.yaml version with a pre-release or build suffix '
        'refuses with status 78', () async {
      for (final version in ['1.0.0-beta.1', '1.0.0+build5']) {
        final fault = await _faultOf('name: x\nversion: $version\n');
        expect(fault.code, FaultCode.packVersionInvalid, reason: version);
        expect(fault.key, 'version', reason: version);
        expect(fault.file, _personalFile, reason: version);
        expect(fault.exitStatus, 78, reason: version);
      }
    });

    test('a personal pack.yaml that is no YAML or holds an unknown key '
        'refuses with status 78', () async {
      final syntax = await _faultOf('name: [\n');
      expect(syntax.code, FaultCode.yamlSyntax);
      expect(syntax.line, isNotNull);
      expect(syntax.exitStatus, 78);

      final unknown = await _faultOf('name: x\nversion: 1.0.0\nowner: me\n');
      expect(unknown.code, FaultCode.unknownKey);
      expect(unknown.key, 'owner');
      expect(unknown.file, _personalFile);
      expect(unknown.exitStatus, 78);
    });

    test('a pack.yaml with no migrations key has none', () {
      final manifest = _parse('name: p\nversion: 1.0.0\n');

      expect(manifest.migrations, isEmpty);
    });

    test('pack.yaml accepts migrations', () {
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

    test('migrations that is not a list is unknown_value', () {
      expect(
        () => _parse('name: p\nversion: 1.0.0\nmigrations: {}\n'),
        throwsA(_fault(FaultCode.unknownValue, key: 'migrations')),
      );
    });
  });
}
