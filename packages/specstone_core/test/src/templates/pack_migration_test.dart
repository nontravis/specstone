import 'package:specstone_core/src/templates/pack_migration.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const _file = 'acme/pack.yaml';

List<PackMigration> parseMigrationsOf(String text) =>
    parseMigrations(loadYamlNode(text), file: _file);

TypeMatcher<TemplateFault> _fault(FaultCode code, {String? key}) =>
    isA<TemplateFault>()
        .having((f) => f.code, 'code', code)
        .having((f) => f.file, 'file', _file)
        .having((f) => f.key, 'key', key);

void main() {
  test(
    'f06/us02/fr01: a migrations list parses into entries and typed steps',
    () {
      final list = parseMigrations(
        loadYamlNode('''
- from: 1.0.0
  steps:
    - rename_section: {doc_type: runbook, from: {id: steps, header: Steps}, to: {id: procedure, header: Procedure}}
- from: 1.1.0
  steps:
    - rename_field: {doc_type: runbook, from: owner, to: on_call}
    - move_file: {doc_type: runbook, from: "prds/runbooks/{slug}/RUNBOOK.md", to: "ops/runbooks/{slug}.md"}
'''),
        file: 'acme/pack.yaml',
      );
      expect(list.map((m) => '${m.from}'), ['1.0.0', '1.1.0']);
      final section = list.first.steps.single as RenameSection;
      expect(
        [
          section.docType,
          section.fromId,
          section.fromHeader,
          section.toId,
          section.toHeader,
        ],
        ['runbook', 'steps', 'Steps', 'procedure', 'Procedure'],
      );
      expect(list.last.steps.map((s) => s.kind), ['rename_field', 'move_file']);
    },
  );

  test('f06/us02/fr01: a null migrations node parses to no entries', () {
    expect(parseMigrations(null, file: _file), isEmpty);
  });

  test('f06/us02/fr01/e06: a from that is not MAJOR.MINOR.PATCH is pack_version_invalid', () {
    expect(
      () => parseMigrationsOf('- from: 1.0\n  steps: []\n'),
      throwsA(_fault(FaultCode.packVersionInvalid, key: 'migrations[0].from')),
    );
  });

  test('f06/us02/fr01/e06: a step of an unknown kind is unknown_value', () {
    expect(
      () => parseMigrationsOf(
        '- from: 1.0.0\n  steps:\n    - delete_section: {doc_type: runbook}\n',
      ),
      throwsA(_fault(FaultCode.unknownValue, key: 'migrations[0].steps[0]')),
    );
  });

  test('f06/us02/fr01/e06: a step missing a key is missing_key', () {
    expect(
      () => parseMigrationsOf(
        '- from: 1.0.0\n'
        '  steps:\n'
        '    - rename_field: {doc_type: runbook, from: owner}\n',
      ),
      throwsA(
        _fault(
          FaultCode.missingKey,
          key: 'migrations[0].steps[0].rename_field.to',
        ),
      ),
    );
  });

  test('f06/us02/fr01/e06: a step with an unknown key is unknown_key', () {
    expect(
      () => parseMigrationsOf(
        '- from: 1.0.0\n'
        '  steps:\n'
        '    - rename_field: {doc_type: runbook, from: owner,'
        ' to: on_call, note: x}\n',
      ),
      throwsA(
        _fault(
          FaultCode.unknownKey,
          key: 'migrations[0].steps[0].rename_field.note',
        ),
      ),
    );
  });

  test('f06/us02/fr01/e06: an entry with an unknown key is unknown_key', () {
    expect(
      () => parseMigrationsOf('- {from: 1.0.0, steps: [], why: x}'),
      throwsA(_fault(FaultCode.unknownKey, key: 'migrations[0].why')),
    );
  });

  test('f06/us02/fr01/e06: a move_file whose to pattern holds other placeholders than its from is unknown_value', () {
    expect(
      () => parseMigrationsOf(
        '- from: 1.0.0\n  steps:\n    - move_file: {doc_type: runbook, from: "a/{slug}.md", to: "b/{nn}_{slug}.md"}\n',
      ),
      throwsA(
        _fault(
          FaultCode.unknownValue,
          key: 'migrations[0].steps[0].move_file.to',
        ),
      ),
    );
  });

  test('f06/us02/fr01/e06: a move_file whose to pattern holds the from '
      'placeholders in another order is unknown_value', () {
    expect(
      () => parseMigrationsOf(
        '- from: 1.0.0\n  steps:\n    - move_file: {doc_type: runbook, from: "a/{nn}_{slug}.md", to: "b/{slug}_{nn}.md"}\n',
      ),
      throwsA(
        _fault(
          FaultCode.unknownValue,
          key: 'migrations[0].steps[0].move_file.to',
        ),
      ),
    );
  });

  test(
    'f06/us02/fr01/e06: an entry that is not a mapping is unknown_value',
    () {
      expect(
        () => parseMigrationsOf('- x\n'),
        throwsA(_fault(FaultCode.unknownValue, key: 'migrations[0]')),
      );
    },
  );

  test('f06/us02/fr01/e06: a step body that is not a mapping is '
      'unknown_value', () {
    expect(
      () =>
          parseMigrationsOf('- from: 1.0.0\n  steps:\n    - rename_field: x\n'),
      throwsA(
        _fault(
          FaultCode.unknownValue,
          key: 'migrations[0].steps[0].rename_field',
        ),
      ),
    );
  });

  test('f06/us02/fr01/e06: a rename_section from that is not a mapping is '
      'unknown_value', () {
    expect(
      () => parseMigrationsOf(
        '- from: 1.0.0\n  steps:\n    - rename_section: {doc_type: runbook,'
        ' from: steps, to: {id: procedure, header: Procedure}}\n',
      ),
      throwsA(
        _fault(
          FaultCode.unknownValue,
          key: 'migrations[0].steps[0].rename_section.from',
        ),
      ),
    );
  });

  test('f06/us02/fr01/e06: a rename_section to that is not a mapping is '
      'unknown_value', () {
    expect(
      () => parseMigrationsOf(
        '- from: 1.0.0\n  steps:\n    - rename_section: {doc_type: runbook,'
        ' from: {id: steps, header: Steps}, to: procedure}\n',
      ),
      throwsA(
        _fault(
          FaultCode.unknownValue,
          key: 'migrations[0].steps[0].rename_section.to',
        ),
      ),
    );
  });

  test('f06/us02/fr01/e06: a rename_section side with an unknown key is '
      'unknown_key', () {
    expect(
      () => parseMigrationsOf(
        '- from: 1.0.0\n  steps:\n    - rename_section: {doc_type: runbook,'
        ' from: {id: steps, header: Steps, note: x},'
        ' to: {id: procedure, header: Procedure}}\n',
      ),
      throwsA(
        _fault(
          FaultCode.unknownKey,
          key: 'migrations[0].steps[0].rename_section.from.note',
        ),
      ),
    );
    expect(
      () => parseMigrationsOf(
        '- from: 1.0.0\n  steps:\n    - rename_section: {doc_type: runbook,'
        ' from: {id: steps, header: Steps},'
        ' to: {id: procedure, header: Procedure, note: x}}\n',
      ),
      throwsA(
        _fault(
          FaultCode.unknownKey,
          key: 'migrations[0].steps[0].rename_section.to.note',
        ),
      ),
    );
  });

  test('f06/us02/fr01/e06: a step kind that is not a string is '
      'unknown_value', () {
    expect(
      () => parseMigrationsOf('- from: 1.0.0\n  steps:\n    - 1: {a: b}\n'),
      throwsA(_fault(FaultCode.unknownValue, key: 'migrations[0].steps[0]')),
    );
  });
}
