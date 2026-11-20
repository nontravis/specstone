import 'package:specstone_core/src/templates/models/migration_step.dart';
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

  test('a stamp_code_fingerprints step with no keys parses and '
      'touches no doc type', () {
    final step = parseMigrationsOf('''
- from: 1.6.0
  steps:
    - stamp_code_fingerprints: {}
''').single.steps.single;

    expect(step, isA<StampCodeFingerprints>());
    expect(step.kind, 'stamp_code_fingerprints');
    expect(step.touches('fr'), isFalse);
  });

  test('a stamp_code_fingerprints step with a key is '
      'unknown_key', () {
    expect(
      () => parseMigrationsOf(
        '- from: 1.6.0\n'
        '  steps:\n'
        '    - stamp_code_fingerprints: {note: x}\n',
      ),
      throwsA(
        _fault(
          FaultCode.unknownKey,
          key: 'migrations[0].steps[0].stamp_code_fingerprints.note',
        ),
      ),
    );
  });

  test('a restamp_code_fingerprints step with no keys parses and '
      'touches no doc type', () {
    final step = parseMigrationsOf('''
- from: 1.7.0
  steps:
    - restamp_code_fingerprints: {}
''').single.steps.single;

    expect(step, isA<RestampCodeFingerprints>());
    expect(step.kind, 'restamp_code_fingerprints');
    expect(step.touches('fr'), isFalse);
  });

  test('a restamp_code_fingerprints step with a key is '
      'unknown_key', () {
    expect(
      () => parseMigrationsOf(
        '- from: 1.7.0\n'
        '  steps:\n'
        '    - restamp_code_fingerprints: {note: x}\n',
      ),
      throwsA(
        _fault(
          FaultCode.unknownKey,
          key: 'migrations[0].steps[0].restamp_code_fingerprints.note',
        ),
      ),
    );
  });

  test('a strip_shared_copies step with no keys parses and touches no '
      'doc type', () {
    final step = parseMigrationsOf('''
- from: 1.12.0
  steps:
    - strip_shared_copies: {}
''').single.steps.single;

    expect(step, isA<StripSharedCopies>());
    expect(step.kind, 'strip_shared_copies');
    expect(step.touches('api'), isFalse);
  });

  test('a strip_shared_copies step with a key is unknown_key', () {
    expect(
      () => parseMigrationsOf(
        '- from: 1.12.0\n'
        '  steps:\n'
        '    - strip_shared_copies: {note: x}\n',
      ),
      throwsA(
        _fault(
          FaultCode.unknownKey,
          key: 'migrations[0].steps[0].strip_shared_copies.note',
        ),
      ),
    );
  });

  test('a drop_shared_lines step reads its ids', () {
    final step = parseMigrationsOf('''
- from: 1.12.0
  steps:
    - drop_shared_lines: {ids: [old_tone, Ghost-1]}
''').single.steps.single;

    expect(step, isA<DropSharedLines>());
    step as DropSharedLines;
    expect(step.kind, 'drop_shared_lines');
    expect(step.ids, ['old_tone', 'Ghost-1']);
    expect(step.touches('api'), isFalse);
    expect(step.touches('story'), isFalse);
  });

  for (final ids in ['[]', 'ghost', '[1]']) {
    test('a bad drop_shared_lines ids value is unknown_value: $ids', () {
      expect(
        () => parseMigrationsOf(
          '- from: 1.12.0\n'
          '  steps:\n'
          '    - drop_shared_lines: {ids: $ids}\n',
        ),
        throwsA(
          _fault(
            FaultCode.unknownValue,
            key: 'migrations[0].steps[0].drop_shared_lines.ids',
          ).having(
            (f) => f.message,
            'message',
            'drop_shared_lines holds no id',
          ),
        ),
      );
    });
  }

  test('a drop_shared_lines step with no ids is missing_key', () {
    expect(
      () => parseMigrationsOf(
        '- from: 1.12.0\n'
        '  steps:\n'
        '    - drop_shared_lines: {}\n',
      ),
      throwsA(
        _fault(
          FaultCode.missingKey,
          key: 'migrations[0].steps[0].drop_shared_lines.ids',
        ),
      ),
    );
  });

  test('a drop_shared_lines step with an extra key is unknown_key', () {
    expect(
      () => parseMigrationsOf(
        '- from: 1.12.0\n'
        '  steps:\n'
        '    - drop_shared_lines: {ids: [a], note: x}\n',
      ),
      throwsA(
        _fault(
          FaultCode.unknownKey,
          key: 'migrations[0].steps[0].drop_shared_lines.note',
        ),
      ),
    );
  });

  test('a bullet_lines step parses to BulletLines and touches its '
      'doc type', () {
    final step = parseMigrationsOf('''
- from: 1.9.0
  steps:
    - bullet_lines: {doc_type: project, section: goals, prefixes: ['**Serves:**']}
''').single.steps.single;

    expect(step, isA<BulletLines>());
    step as BulletLines;
    expect(step.kind, 'bullet_lines');
    expect(step.docType, 'project');
    expect(step.section, 'goals');
    expect(step.prefixes, ['**Serves:**']);
    expect(step.touches('project'), isTrue);
    expect(step.touches('feature'), isFalse);
  });

  test('a bullet_lines step missing a key is missing_key', () {
    for (final key in ['doc_type', 'section', 'prefixes']) {
      final keys = {
        'doc_type': 'project',
        'section': 'goals',
        'prefixes': "['**Serves:**']",
      }..remove(key);
      final body = keys.entries.map((e) => '${e.key}: ${e.value}').join(', ');
      expect(
        () => parseMigrationsOf(
          '- from: 1.9.0\n  steps:\n    - bullet_lines: {$body}\n',
        ),
        throwsA(
          _fault(
            FaultCode.missingKey,
            key: 'migrations[0].steps[0].bullet_lines.$key',
          ),
        ),
        reason: key,
      );
    }
  });

  test('a bullet_lines step with an extra key is unknown_key', () {
    expect(
      () => parseMigrationsOf(
        '- from: 1.9.0\n'
        '  steps:\n'
        '    - bullet_lines: {doc_type: project, section: goals,'
        " prefixes: ['**Serves:**'], note: x}\n",
      ),
      throwsA(
        _fault(
          FaultCode.unknownKey,
          key: 'migrations[0].steps[0].bullet_lines.note',
        ),
      ),
    );
  });

  test('a bullet_lines step with an empty prefixes list or an empty '
      'prefix is unknown_value', () {
    for (final prefixes in ['[]', "['']"]) {
      expect(
        () => parseMigrationsOf(
          '- from: 1.9.0\n'
          '  steps:\n'
          '    - bullet_lines: {doc_type: project, section: goals,'
          ' prefixes: $prefixes}\n',
        ),
        throwsA(
          _fault(
            FaultCode.unknownValue,
            key: 'migrations[0].steps[0].bullet_lines.prefixes',
          ),
        ),
        reason: prefixes,
      );
    }
  });

  test('a drop_default_lines step reads its doc type list', () {
    final step = parseMigrationsOf('''
- from: 1.13.0
  steps:
    - drop_default_lines: {doc_types: [domain, project_domain]}
''').single.steps.single;

    expect(step, isA<DropDefaultLines>());
    step as DropDefaultLines;
    expect(step.kind, 'drop_default_lines');
    expect(step.docTypes, ['domain', 'project_domain']);
    expect(step.touches('domain'), isTrue);
    expect(step.touches('project_domain'), isTrue);
    expect(step.touches('feature'), isFalse);
  });

  test('a drop_default_lines step with no doc types is missing_key', () {
    expect(
      () => parseMigrationsOf(
        '- from: 1.13.0\n  steps:\n    - drop_default_lines: {}\n',
      ),
      throwsA(
        _fault(
          FaultCode.missingKey,
          key: 'migrations[0].steps[0].drop_default_lines.doc_types',
        ),
      ),
    );
  });

  test('a mark_retrim step reads its doc types and sections', () {
    final step = parseMigrationsOf('''
- from: 1.14.0
  steps:
    - mark_retrim: {doc_types: [domain, project_domain], sections: [invariants]}
''').single.steps.single;

    expect(step, isA<MarkRetrim>());
    step as MarkRetrim;
    expect(step.kind, 'mark_retrim');
    expect(step.docTypes, ['domain', 'project_domain']);
    expect(step.sections, ['invariants']);
    expect(step.touches('domain'), isTrue);
    expect(step.touches('project_domain'), isTrue);
    expect(step.touches('feature'), isFalse);
  });

  test('a mark_retrim step with a missing, unknown, or empty key is refused '
      'at that key', () {
    expect(
      () => parseMigrationsOf(
        '- from: 1.14.0\n'
        '  steps:\n'
        '    - mark_retrim: {doc_types: [domain], sections: [invariants],'
        ' note: x}\n',
      ),
      throwsA(
        _fault(
          FaultCode.unknownKey,
          key: 'migrations[0].steps[0].mark_retrim.note',
        ),
      ),
    );
    const held = {'doc_types': '[domain]', 'sections': '[invariants]'};
    for (final missing in held.keys) {
      final body = [
        for (final MapEntry(:key, :value) in held.entries)
          if (key != missing) '$key: $value',
      ].join(', ');
      expect(
        () => parseMigrationsOf(
          '- from: 1.14.0\n  steps:\n    - mark_retrim: {$body}\n',
        ),
        throwsA(
          _fault(
            FaultCode.missingKey,
            key: 'migrations[0].steps[0].mark_retrim.$missing',
          ),
        ),
        reason: 'missing $missing',
      );
    }
    for (final empty in held.keys) {
      final body = [
        for (final MapEntry(:key, :value) in held.entries)
          '$key: ${key == empty ? '[]' : value}',
      ].join(', ');
      expect(
        () => parseMigrationsOf(
          '- from: 1.14.0\n  steps:\n    - mark_retrim: {$body}\n',
        ),
        throwsA(
          _fault(
            FaultCode.unknownValue,
            key: 'migrations[0].steps[0].mark_retrim.$empty',
          ),
        ),
        reason: 'empty $empty',
      );
    }
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
