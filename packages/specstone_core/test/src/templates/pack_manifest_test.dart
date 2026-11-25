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
      for (final (text, key) in [
        ('name: x\n', 'version'),
        ('version: 1.0.0\n', 'name'),
      ]) {
        expect(
          () => _parse(text),
          throwsA(_fault(FaultCode.missingKey, key: key)),
          reason: key,
        );
      }
    });

    test('a list version is invalid', () {
      for (final (reason, version) in [
        ('list', '[1.0.0]'),
        ('leading zero', '01.2.0'),
        ('unquoted double', '1.2'),
      ]) {
        expect(
          () => _parse('name: x\nversion: $version\n'),
          throwsA(_fault(FaultCode.packVersionInvalid, key: 'version')),
          reason: reason,
        );
      }
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
      expect(manifest.shared.patterns, isEmpty);
    });

    test('shared banned and required pattern keys parse into shared', () {
      final manifest = _parse('''
name: team
version: 1.0.0
shared_banned_patterns:
  - {id: no_todo, pattern: TODO, message: m, for_doc_types: [story]}
shared_required_patterns:
  - id: has_owner
    pattern: Owner
    message: m
    for_doc_types: [story]
    sections: [use_case]
''');

      expect(manifest.shared.patterns.map((p) => p.id), [
        'no_todo',
        'has_owner',
      ]);
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

    test('a drop of a line the pack.yaml declares is unknown_value', () {
      expect(
        () => _parse('''
name: p
version: 1.0.0
shared_lines:
  - id: old_tone
    text: Keep it short.
migrations:
  - from: 0.9.0
    steps:
      - drop_shared_lines: {ids: [gone, old_tone]}
'''),
        throwsA(
          _fault(
            FaultCode.unknownValue,
            key: 'migrations[0].steps[0].drop_shared_lines.ids',
          ).having(
            (f) => f.message,
            'message',
            'drop_shared_lines names a line the pack defines: old_tone',
          ),
        ),
      );
    });

    test('a bad extends is reported before a bad migration', () {
      expect(
        () => _parse('''
name: p
version: 1.0.0
extends: [5]
migrations: {}
'''),
        throwsA(_fault(FaultCode.unknownValue, key: 'extends')),
      );
    });

    test('migrations that is not a list is unknown_value', () {
      expect(
        () => _parse('name: p\nversion: 1.0.0\nmigrations: {}\n'),
        throwsA(_fault(FaultCode.unknownValue, key: 'migrations')),
      );
    });

    test('leftover_homes parses a section entry and a path entry in file '
        'order', () {
      final homes = _parse('''
name: p
version: 1.0.0
leftover_homes:
  - doc_types: [architecture]
    section: {id: interaction, header: Interaction}
    to: [fr]
    home: x
  - path: 'specs/topics/{slug}.md'
    to: [fr]
    home: y
''').leftoverHomes;

      expect(homes, hasLength(2));
      expect(homes[0].docTypes, ['architecture']);
      expect(homes[0].sectionId, 'interaction');
      expect(homes[0].header, 'Interaction');
      expect(homes[0].path, isNull);
      expect(homes[0].to, ['fr']);
      expect(homes[0].home, 'x');
      expect(homes[1].docTypes, isEmpty);
      expect(homes[1].sectionId, isNull);
      expect(homes[1].header, isNull);
      expect(homes[1].path, 'specs/topics/{slug}.md');
      expect(homes[1].to, ['fr']);
      expect(homes[1].home, 'y');
    });

    test('a leftover_homes entry with no home is missing_key', () {
      expect(
        () => _parse('''
name: p
version: 1.0.0
leftover_homes:
  - path: 'specs/topics/{slug}.md'
    to: [fr]
'''),
        throwsA(_fault(FaultCode.missingKey, key: 'leftover_homes[0].home')),
      );
    });

    test('a leftover_homes entry key outside its format is unknown_key', () {
      expect(
        () => _parse('''
name: p
version: 1.0.0
leftover_homes:
  - path: 'specs/topics/{slug}.md'
    to: [fr]
    home: y
    where: z
'''),
        throwsA(_fault(FaultCode.unknownKey, key: 'leftover_homes[0].where')),
      );
    });
  });
}
