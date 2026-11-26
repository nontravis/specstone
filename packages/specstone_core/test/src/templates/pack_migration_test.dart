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

  for (final kind in const [
    'move_to_record',
    'stamp_code_fingerprints',
    'restamp_code_fingerprints',
    'strip_shared_copies',
    'drop_default_lines',
  ]) {
    test('a $kind step is unknown_value at its step key', () {
      expect(
        () => parseMigrationsOf('- from: 1.0.0\n  steps:\n    - $kind: {}\n'),
        throwsA(_fault(FaultCode.unknownValue, key: 'migrations[0].steps[0]')),
      );
    });
  }

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
    for (final (from, to) in [
      ('a/{slug}.md', 'b/{nn}_{slug}.md'),
      ('a/{nn}_{slug}.md', 'b/{slug}_{nn}.md'),
    ]) {
      expect(
        () => parseMigrationsOf(
          '- from: 1.0.0\n  steps:\n    - move_file: '
          '{doc_type: runbook, from: "$from", to: "$to"}\n',
        ),
        throwsA(
          _fault(
            FaultCode.unknownValue,
            key: 'migrations[0].steps[0].move_file.to',
          ),
        ),
        reason: '$from to $to',
      );
    }
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

  test('a relink_merged_docs step with no keys parses', () {
    final step = parseMigrationsOf('''
- from: 1.0.0
  steps:
    - relink_merged_docs: {}
''').single.steps.single;

    expect(step, isA<RelinkMergedDocs>());
    expect(step.kind, 'relink_merged_docs');
  });

  test('a relink_merged_docs step with a key is unknown_key', () {
    expect(
      () => parseMigrationsOf(
        '- from: 1.0.0\n'
        '  steps:\n'
        '    - relink_merged_docs: {from: x}\n',
      ),
      throwsA(
        _fault(
          FaultCode.unknownKey,
          key: 'migrations[0].steps[0].relink_merged_docs.from',
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

  group('regenerate', () {
    test('a regenerate step reads its generators and touches no doc type', () {
      final step = parseMigrationsOf('''
- from: 1.31.0
  steps:
    - regenerate: {generators: [feature_catalog, group_feature_catalog]}
''').single.steps.single;

      expect(step, isA<Regenerate>());
      step as Regenerate;
      expect(step.kind, 'regenerate');
      expect(step.generators, ['feature_catalog', 'group_feature_catalog']);
      expect(step.touches('feature'), isFalse);
    });

    test('an empty, missing, or extra key is refused at that key', () {
      const steps = '- from: 1.31.0\n  steps:\n    - regenerate: ';
      for (final (body, code, name) in [
        ('{generators: []}', FaultCode.unknownValue, 'generators'),
        ('{}', FaultCode.missingKey, 'generators'),
        (
          '{generators: [feature_catalog], note: x}',
          FaultCode.unknownKey,
          'note',
        ),
      ]) {
        expect(
          () => parseMigrationsOf('$steps$body\n'),
          throwsA(_fault(code, key: 'migrations[0].steps[0].regenerate.$name')),
          reason: body,
        );
      }
    });
  });

  group('drop_section', () {
    const body =
        '{doc_types: [architecture, project_architecture],'
        ' section: {id: design_references, header: Design references}}';

    test('drop_section parses its doc types, id, and header', () {
      final step = parseMigrationsOf(
        '- from: 1.16.0\n  steps:\n    - drop_section: $body\n',
      ).single.steps.single;

      expect(step, isA<DropSection>());
      step as DropSection;
      expect(step.kind, 'drop_section');
      expect(step.docTypes, ['architecture', 'project_architecture']);
      expect(step.sectionId, 'design_references');
      expect(step.sectionHeader, 'Design references');
      expect(step.touches('architecture'), isTrue);
      expect(step.touches('project_architecture'), isTrue);
      expect(step.touches('feature'), isFalse);
    });

    test('drop_section refuses an unknown key in the step or in section', () {
      const cases = {
        'migrations[0].steps[0].drop_section.note':
            '{doc_types: [architecture],'
            ' section: {id: design_references, header: Design references},'
            ' note: x}',
        'migrations[0].steps[0].drop_section.section.note':
            '{doc_types: [architecture],'
            ' section: {id: design_references, header: Design references,'
            ' note: x}}',
      };
      for (final MapEntry(:key, value: text) in cases.entries) {
        expect(
          () => parseMigrationsOf(
            '- from: 1.16.0\n  steps:\n    - drop_section: $text\n',
          ),
          throwsA(_fault(FaultCode.unknownKey, key: key)),
          reason: key,
        );
      }
    });

    test('drop_section refuses each missing key', () {
      const missingBodies = {
        'doc_types':
            '{section: {id: design_references, header: Design references}}',
        'section': '{doc_types: [architecture]}',
        'section.id':
            '{doc_types: [architecture], section: {header: Design references}}',
        'section.header':
            '{doc_types: [architecture], section: {id: design_references}}',
      };
      for (final MapEntry(key: missing, value: text) in missingBodies.entries) {
        expect(
          () => parseMigrationsOf(
            '- from: 1.16.0\n  steps:\n    - drop_section: $text\n',
          ),
          throwsA(
            _fault(
              FaultCode.missingKey,
              key: 'migrations[0].steps[0].drop_section.$missing',
            ),
          ),
          reason: 'missing $missing',
        );
      }
    });

    test('drop_section refuses an empty doc_types list', () {
      expect(
        () => parseMigrationsOf(
          '- from: 1.16.0\n  steps:\n    - drop_section:'
          ' {doc_types: [], section: {id: design_references,'
          ' header: Design references}}\n',
        ),
        throwsA(
          _fault(
            FaultCode.unknownValue,
            key: 'migrations[0].steps[0].drop_section.doc_types',
          ),
        ),
      );
    });
  });

  group('drop_doc_type', () {
    const body = '{id: topic, path: "specs/topics/{slug}.md"}';

    test('drop_doc_type parses its id and path and touches no doc type', () {
      final step = parseMigrationsOf(
        '- from: 1.19.0\n  steps:\n    - drop_doc_type: $body\n',
      ).single.steps.single;

      expect(step, isA<DropDocType>());
      step as DropDocType;
      expect(step.kind, 'drop_doc_type');
      expect(step.id, 'topic');
      expect(step.path, 'specs/topics/{slug}.md');
      expect(step.touches('topic'), isFalse);
    });

    test('drop_doc_type refuses an unknown key and each missing key', () {
      const cases = {
        FaultCode.unknownKey: {
          'note': '{id: topic, path: "specs/{slug}.md", note: x}',
        },
        FaultCode.missingKey: {
          'id': '{path: "specs/{slug}.md"}',
          'path': '{id: topic}',
        },
      };
      for (final MapEntry(key: code, value: bodies) in cases.entries) {
        for (final MapEntry(:key, value: text) in bodies.entries) {
          expect(
            () => parseMigrationsOf(
              '- from: 1.19.0\n  steps:\n    - drop_doc_type: $text\n',
            ),
            throwsA(
              _fault(code, key: 'migrations[0].steps[0].drop_doc_type.$key'),
            ),
            reason: '$code $key',
          );
        }
      }
    });
  });

  group('merge_doc', () {
    const body =
        '{from: {id: error, path: "specs/f{nn}_{slug}/ERROR.md"},'
        ' to: api,'
        ' sections: [ '
        '{from: {id: error_catalog, header: Error catalog}, to: errors},'
        ' {from: {id: retry_policy, header: Retry policy}, to: retry}'
        ' ]}';

    List<PackMigration> parseBody(String text) =>
        parseMigrationsOf('- from: 1.19.0\n  steps:\n    - merge_doc: $text\n');

    test('merge_doc parses its from type, to type, and sections in file '
        'order', () {
      final step = parseBody(body).single.steps.single;

      expect(step, isA<MergeDoc>());
      step as MergeDoc;
      expect(step.kind, 'merge_doc');
      expect(step.fromId, 'error');
      expect(step.fromPath, 'specs/f{nn}_{slug}/ERROR.md');
      expect(step.toId, 'api');
      expect(step.sections.map((s) => s.fromId), [
        'error_catalog',
        'retry_policy',
      ]);
      expect(step.sections.map((s) => s.fromHeader), [
        'Error catalog',
        'Retry policy',
      ]);
      expect(step.sections.map((s) => s.toId), ['errors', 'retry']);
      expect(step.touches('api'), isTrue);
      expect(step.touches('error'), isFalse);
    });

    test('merge_doc refuses each missing key', () {
      const missingBodies = {
        'from': '{to: api, sections: [{from: {id: a, header: A}, to: b}]}',
        'from.id':
            '{from: {path: p}, to: api,'
            ' sections: [{from: {id: a, header: A}, to: b}]}',
        'from.path':
            '{from: {id: error}, to: api,'
            ' sections: [{from: {id: a, header: A}, to: b}]}',
        'to':
            '{from: {id: error, path: p},'
            ' sections: [{from: {id: a, header: A}, to: b}]}',
        'sections': '{from: {id: error, path: p}, to: api}',
        'sections[0].from':
            '{from: {id: error, path: p}, to: api, sections: [{to: b}]}',
        'sections[0].from.header':
            '{from: {id: error, path: p}, to: api,'
            ' sections: [{from: {id: a}, to: b}]}',
        'sections[0].to':
            '{from: {id: error, path: p}, to: api,'
            ' sections: [{from: {id: a, header: A}}]}',
      };
      for (final MapEntry(key: missing, value: text) in missingBodies.entries) {
        expect(
          () => parseBody(text),
          throwsA(
            _fault(
              FaultCode.missingKey,
              key: 'migrations[0].steps[0].merge_doc.$missing',
            ),
          ),
          reason: 'missing $missing',
        );
      }
    });

    test('merge_doc refuses an unknown key at each level', () {
      const unknownBodies = {
        'note':
            '{from: {id: error, path: p}, to: api,'
            ' sections: [{from: {id: a, header: A}, to: b}], note: x}',
        'from.note':
            '{from: {id: error, path: p, note: x}, to: api,'
            ' sections: [{from: {id: a, header: A}, to: b}]}',
        'sections[0].note':
            '{from: {id: error, path: p}, to: api,'
            ' sections: [{from: {id: a, header: A}, to: b, note: x}]}',
        'sections[0].from.note':
            '{from: {id: error, path: p}, to: api,'
            ' sections: [{from: {id: a, header: A, note: x}, to: b}]}',
      };
      for (final MapEntry(key: unknown, value: text) in unknownBodies.entries) {
        expect(
          () => parseBody(text),
          throwsA(
            _fault(
              FaultCode.unknownKey,
              key: 'migrations[0].steps[0].merge_doc.$unknown',
            ),
          ),
          reason: 'unknown $unknown',
        );
      }
    });

    test('merge_doc refuses an empty sections list', () {
      expect(
        () => parseBody('{from: {id: error, path: p}, to: api, sections: []}'),
        throwsA(
          _fault(
            FaultCode.unknownValue,
            key: 'migrations[0].steps[0].merge_doc.sections',
          ),
        ),
      );
    });
  });
}
