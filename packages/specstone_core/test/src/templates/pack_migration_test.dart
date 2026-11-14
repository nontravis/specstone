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
  test('a migrations list parses into entries and typed steps', () {
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
  });

  test('a null migrations node parses to no entries', () {
    expect(parseMigrations(null, file: _file), isEmpty);
  });

  test('a from that is not MAJOR.MINOR.PATCH is pack_version_invalid', () {
    expect(
      () => parseMigrationsOf('- from: 1.0\n  steps: []\n'),
      throwsA(_fault(FaultCode.packVersionInvalid, key: 'migrations[0].from')),
    );
  });

  test('a step of an unknown kind is unknown_value', () {
    expect(
      () => parseMigrationsOf(
        '- from: 1.0.0\n  steps:\n    - delete_section: {doc_type: runbook}\n',
      ),
      throwsA(_fault(FaultCode.unknownValue, key: 'migrations[0].steps[0]')),
    );
  });

  test('a step missing a key is missing_key', () {
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

  test('a step with an unknown key is unknown_key', () {
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

  test('an entry with an unknown key is unknown_key', () {
    expect(
      () => parseMigrationsOf('- {from: 1.0.0, steps: [], why: x}'),
      throwsA(_fault(FaultCode.unknownKey, key: 'migrations[0].why')),
    );
  });

  test('a move_file whose to pattern holds other placeholders than its from is '
      'unknown_value', () {
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

  test('a move_file whose to pattern holds the from '
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

  test('an entry that is not a mapping is unknown_value', () {
    expect(
      () => parseMigrationsOf('- x\n'),
      throwsA(_fault(FaultCode.unknownValue, key: 'migrations[0]')),
    );
  });

  test('a step body that is not a mapping is '
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

  test('a rename_section from that is not a mapping is '
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

  test('a rename_section to that is not a mapping is '
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

  test('a rename_section side with an unknown key is '
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

  test('a step kind that is not a string is '
      'unknown_value', () {
    expect(
      () => parseMigrationsOf('- from: 1.0.0\n  steps:\n    - 1: {a: b}\n'),
      throwsA(_fault(FaultCode.unknownValue, key: 'migrations[0].steps[0]')),
    );
  });

  test('a move_to_record step parses into its doc types, '
      'fields, and record doc type', () {
    final step = parseMigrationsOf('''
- from: 1.4.0
  steps:
    - move_to_record: {doc_types: [user_story, fr], fields: [status, implements], to: implementation}
''').single.steps.single;

    expect(step, isA<MoveToRecord>());
    final move = step as MoveToRecord;
    expect(move.kind, 'move_to_record');
    expect(move.docTypes, ['user_story', 'fr']);
    expect(move.fields, ['status', 'implements']);
    expect(move.to, 'implementation');
    expect(move.touches('fr'), isTrue);
    expect(move.touches('architecture'), isFalse);
  });

  test('a move_to_record step missing a key is '
      'missing_key', () {
    for (final key in ['doc_types', 'fields', 'to']) {
      final keys = {
        'doc_types': '[fr]',
        'fields': '[status]',
        'to': 'implementation',
      }..remove(key);
      final body = keys.entries.map((e) => '${e.key}: ${e.value}').join(', ');
      expect(
        () => parseMigrationsOf(
          '- from: 1.4.0\n  steps:\n    - move_to_record: {$body}\n',
        ),
        throwsA(
          _fault(
            FaultCode.missingKey,
            key: 'migrations[0].steps[0].move_to_record.$key',
          ),
        ),
        reason: 'key $key',
      );
    }
  });

  test('a move_to_record step with an unknown key is '
      'unknown_key', () {
    expect(
      () => parseMigrationsOf(
        '- from: 1.4.0\n'
        '  steps:\n'
        '    - move_to_record: {doc_types: [fr], fields: [status],'
        ' to: implementation, note: x}\n',
      ),
      throwsA(
        _fault(
          FaultCode.unknownKey,
          key: 'migrations[0].steps[0].move_to_record.note',
        ),
      ),
    );
  });

  test('a move_to_record list that holds a non-string is '
      'unknown_value', () {
    expect(
      () => parseMigrationsOf(
        '- from: 1.4.0\n'
        '  steps:\n'
        '    - move_to_record: {doc_types: [fr], fields: [1],'
        ' to: implementation}\n',
      ),
      throwsA(
        _fault(
          FaultCode.unknownValue,
          key: 'migrations[0].steps[0].move_to_record.fields',
        ),
      ),
    );
  });
}
