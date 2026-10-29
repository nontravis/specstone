import 'dart:io';

import 'package:specstone_core/src/document_writing/move_journal.dart'
    show MoveStep;
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/run_plan.dart';
import 'package:specstone_core/src/setup_migration/upgrade_plan.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/posix_modes.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';

const _runbookDoc = '''
---
owner: sre
---
# Deploy

## Steps

Run it.
''';

const _runbookPackYaml = '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - rename_section: {doc_type: runbook, from: {id: steps, header: Steps}, to: {id: procedure, header: Procedure}}
  - from: 1.1.0
    steps:
      - rename_field: {doc_type: runbook, from: owner, to: on_call}
''';

const _runbookType = '''
id: runbook
description: A runbook.
path: prds/runbooks/{slug}/RUNBOOK.md
fields:
  - {id: on_call, type: string}
sections:
  - {id: procedure, header: Procedure, required: true}
''';

const _overridePath = '.specstone/templates/runbook.yaml';
const _override =
    'sections: [{id: steps, required: true, description: Kept.}]\n';

String _config(String acmePin) => '${shippedPinsConfig()}  acme: $acmePin\n';

Future<({Directory project, Directory home})> _fixture({
  String acmePin = '1.0.0',
  String packYaml = _runbookPackYaml,
  String runbookType = _runbookType,
  Map<String, String> docs = const {
    'prds/runbooks/deploy/RUNBOOK.md': _runbookDoc,
  },
  Map<String, String> overrides = const {_overridePath: _override},
}) async {
  final home = await writeTree({
    '.specstone/packs/acme/pack.yaml': packYaml,
    for (final type in runbookType.split('---\n'))
      '.specstone/packs/acme/${_idOf(type) ?? 'runbook'}.yaml': type,
  });
  final project = await writeTree({
    '.specstone/config.yaml': _config(acmePin),
    for (final MapEntry(:key, :value) in docs.entries) 'docs/$key': value,
    ...overrides,
  });
  return (project: project, home: home);
}

RunPlan _plan(({Directory project, Directory home}) fixture) => planUpgradeRun(
  fixture.project,
  templates: TemplateResolver(),
  homeDirectory: fixture.home,
);

/// The `id:` value of a doc-type text, or null.
String? _idOf(String type) =>
    RegExp(r'^id: (\S+)$', multiLine: true).firstMatch(type)?.group(1);

PlannedRewrite _rewriteAt(RunPlan plan, String path) =>
    plan.rewrites.singleWhere((rewrite) => rewrite.path == path);

void main() {
  test('f06/us02/fr02/e08: a move onto a staying doc refuses before anything '
      'prints', () async {
    const packYaml = '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - move_file: {doc_type: runbook, from: "prds/runbooks/{slug}/RUNBOOK.md", to: "prds/runbooks/{slug}/PLAYBOOK.md"}
''';
    const type = '''
id: runbook
description: A runbook.
path: prds/runbooks/{slug}/PLAYBOOK.md
sections:
  - {id: steps, header: Steps, required: true}
''';
    final fixture = await _fixture(
      packYaml: packYaml,
      runbookType: type,
      overrides: const {},
      docs: const {
        'prds/runbooks/deploy/RUNBOOK.md': '# Deploy\n\n## Steps\n\nx\n',
        'prds/runbooks/deploy/PLAYBOOK.md': '# Kept\n\n## Steps\n\ny\n',
      },
    );

    await expectLater(
      () => _plan(fixture),
      throwsA(
        isA<MigrateFault>()
            .having((f) => f.code, 'code', MigrateFaultCode.upgradeCollision)
            .having((f) => f.exitStatus, 'exitStatus', 65)
            .having(
              (f) => f.toText(),
              'text',
              'prds/runbooks/deploy/RUNBOOK.md: move_file of runbook moves '
                  'prds/runbooks/{slug}/RUNBOOK.md to '
                  'prds/runbooks/{slug}/PLAYBOOK.md, which the doc already '
                  'there holds; move, rename, or merge each listed doc or '
                  'entry so the step no longer lands on it, then run '
                  'specstone migrate again',
            ),
      ),
    );
    expect(
      File.fromUri(
        fixture.project.uri.resolve('docs/prds/runbooks/deploy/PLAYBOOK.md'),
      ).readAsStringSync(),
      '# Kept\n\n## Steps\n\ny\n',
    );
  });

  test('f06/us02/fr02/e08: two docs moved onto one path refuse once, each on '
      'its own line', () async {
    const packYaml = '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - move_file: {doc_type: runbook, from: "prds/runbooks/{slug}/RUNBOOK.md", to: "prds/runbooks/{slug}/NOTES.md"}
      - move_file: {doc_type: runbook, from: "prds/ops/{slug}/RUNBOOK.md", to: "prds/runbooks/{slug}/NOTES.md"}
''';
    const type = '''
id: runbook
description: A runbook.
path: prds/runbooks/{slug}/NOTES.md
sections:
  - {id: steps, header: Steps, required: true}
''';
    final fixture = await _fixture(
      packYaml: packYaml,
      runbookType: type,
      overrides: const {},
      docs: const {
        'prds/runbooks/deploy/RUNBOOK.md': '# Deploy\n\n## Steps\n\nx\n',
        'prds/ops/deploy/RUNBOOK.md': '# Live\n\n## Steps\n\ny\n',
      },
    );

    await expectLater(
      () => _plan(fixture),
      throwsA(
        isA<MigrateFault>()
            .having((f) => f.more, 'more', hasLength(1))
            .having(
              (f) => f.toText(),
              'text',
              'prds/ops/deploy/RUNBOOK.md: move_file of runbook moves '
                  'prds/ops/{slug}/RUNBOOK.md to '
                  'prds/runbooks/{slug}/NOTES.md, which '
                  'prds/runbooks/deploy/RUNBOOK.md also moves to; move, '
                  'rename, or merge each listed doc or entry so the step no '
                  'longer lands on it, then run specstone migrate again\n'
                  'prds/runbooks/deploy/RUNBOOK.md: move_file of runbook moves '
                  'prds/runbooks/{slug}/RUNBOOK.md to '
                  'prds/runbooks/{slug}/NOTES.md, which '
                  'prds/ops/deploy/RUNBOOK.md also moves to; move, rename, '
                  'or merge each listed doc or entry so the step no longer '
                  'lands on it, then run specstone migrate again',
            ),
      ),
    );
  });

  group(
    'f06/us02/fr02/e08, final M5: upgrade_collision lists each doc once',
    () {
      /// The DocPath each line of [fault] starts with.
      List<String?> filesOf(MigrateFault fault) => [
        fault.file,
        for (final next in fault.more) next.file,
      ];

      test('f06/us02/fr02/e08: three docs moved onto one path print one line '
          'each', () async {
        const packYaml = '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - move_file: {doc_type: runbook, from: "prds/runbooks/{slug}/RUNBOOK.md", to: "prds/runbooks/{slug}/NOTES.md"}
      - move_file: {doc_type: runbook, from: "prds/ops/{slug}/RUNBOOK.md", to: "prds/runbooks/{slug}/NOTES.md"}
      - move_file: {doc_type: runbook, from: "prds/old/{slug}/RUNBOOK.md", to: "prds/runbooks/{slug}/NOTES.md"}
''';
        const type = '''
id: runbook
description: A runbook.
path: prds/runbooks/{slug}/NOTES.md
sections:
  - {id: steps, header: Steps, required: true}
''';
        final fixture = await _fixture(
          packYaml: packYaml,
          runbookType: type,
          overrides: const {},
          docs: const {
            'prds/runbooks/deploy/RUNBOOK.md': '# A\n\n## Steps\n\nx\n',
            'prds/ops/deploy/RUNBOOK.md': '# B\n\n## Steps\n\ny\n',
            'prds/old/deploy/RUNBOOK.md': '# C\n\n## Steps\n\nz\n',
          },
        );

        expect(
          () => _plan(fixture),
          throwsA(
            isA<MigrateFault>().having(filesOf, 'files', [
              'prds/old/deploy/RUNBOOK.md',
              'prds/ops/deploy/RUNBOOK.md',
              'prds/runbooks/deploy/RUNBOOK.md',
            ]),
          ),
        );
      });

      test('f06/us02/fr02/e08: a doc whose section and field renames both '
          'collide prints one line', () async {
        final fixture = await _fixture(
          overrides: const {},
          docs: const {
            'prds/runbooks/deploy/RUNBOOK.md':
                '---\nowner: sre\non_call: ops\n---\n# Deploy\n\n## Steps\n\n'
                'x\n\n## Procedure\n\ny\n',
          },
        );

        expect(
          () => _plan(fixture),
          throwsA(
            isA<MigrateFault>().having(filesOf, 'files', [
              'prds/runbooks/deploy/RUNBOOK.md',
            ]),
          ),
        );
      });
    },
  );

  test('f06/us02/fr02/e05: a chained move_file path ends at the last step, '
      'one move from the original path', () async {
    const packYaml = '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - move_file: {doc_type: runbook, from: "prds/runbooks/{slug}/RUNBOOK.md", to: "prds/runbooks/{slug}/OLD.md"}
  - from: 1.1.0
    steps:
      - move_file: {doc_type: runbook, from: "prds/runbooks/{slug}/OLD.md", to: "ops/runbooks/{slug}/RUNBOOK.md"}
''';
    const type = '''
id: runbook
description: A runbook.
path: ops/runbooks/{slug}/RUNBOOK.md
sections:
  - {id: steps, header: Steps, required: true}
''';
    final plan = _plan(
      await _fixture(
        packYaml: packYaml,
        runbookType: type,
        overrides: const {},
        docs: const {'prds/runbooks/deploy/RUNBOOK.md': _runbookDoc},
      ),
    );

    expect(plan.moves, [
      (
        from: 'prds/runbooks/deploy/RUNBOOK.md',
        to: 'ops/runbooks/deploy/RUNBOOK.md',
      ),
    ]);
  });

  test(
    'f06/us02/fr02/e08: a swap composes onto one path and refuses',
    () async {
      const packYaml = '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - move_file: {doc_type: runbook, from: "prds/runbooks/{slug}/RUNBOOK.md", to: "prds/runbooks/{slug}/NOTES.md"}
      - move_file: {doc_type: runbook, from: "prds/runbooks/{slug}/NOTES.md", to: "prds/runbooks/{slug}/RUNBOOK.md"}
''';
      const type = '''
id: runbook
description: A runbook.
path: prds/runbooks/{slug}/RUNBOOK.md
sections:
  - {id: steps, header: Steps, required: true}
''';
      final fixture = await _fixture(
        packYaml: packYaml,
        runbookType: type,
        overrides: const {},
        docs: const {
          'prds/runbooks/deploy/RUNBOOK.md': '# Deploy\n\n## Steps\n\nx\n',
          'prds/runbooks/deploy/NOTES.md': '# Notes\n\n## Steps\n\ny\n',
        },
      );
      await expectLater(
        () => _plan(fixture),
        throwsA(
          isA<MigrateFault>().having(
            (f) => f.code,
            'code',
            MigrateFaultCode.upgradeCollision,
          ),
        ),
      );
    },
  );

  test('f06/us02/fr02/e08: Scenario B orders a move onto the old path of '
      'another doc after the move that frees it', () async {
    const swapPack = '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - move_file: {doc_type: runbook, from: "prds/ops/{slug}/RUNBOOK.md", to: "prds/runbooks/{slug}/RUNBOOK.md"}
      - move_file: {doc_type: runbook, from: "prds/runbooks/{slug}/NOTES.md", to: "prds/ops/{slug}/RUNBOOK.md"}
''';
    const types = '''
id: runbook
description: A runbook.
path: prds/runbooks/{slug}/RUNBOOK.md
sections:
  - {id: steps, header: Steps, required: true}
''';
    final fixture = await _fixture(
      packYaml: swapPack,
      runbookType: types,
      overrides: const {},
      docs: const {
        'prds/ops/deploy/RUNBOOK.md': '# Deploy\n\n## Steps\n\nx\n',
        'prds/runbooks/deploy/NOTES.md': '# Notes\n\n## Steps\n\ny\n',
      },
    );
    final plan = _plan(fixture);

    expect(
      [for (final move in plan.moves) (move.from, move.to)],
      [
        ('prds/ops/deploy/RUNBOOK.md', 'prds/runbooks/deploy/RUNBOOK.md'),
        ('prds/runbooks/deploy/NOTES.md', 'prds/ops/deploy/RUNBOOK.md'),
      ],
    );
  });

  test('f06/us02/fr02/e08, F6-D34: a rotation through a temporary name plans '
      'the final paths and parks one doc in the stage', () async {
    const rotationPack = '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - move_file: {doc_type: runbook, from: "prds/runbooks/{slug}/RUNBOOK.md", to: "prds/runbooks/{slug}/TMP.md"}
      - move_file: {doc_type: runbook, from: "prds/runbooks/{slug}/NOTES.md", to: "prds/runbooks/{slug}/RUNBOOK.md"}
      - move_file: {doc_type: runbook, from: "prds/runbooks/{slug}/TMP.md", to: "prds/runbooks/{slug}/NOTES.md"}
''';
    const types = '''
id: runbook
description: A runbook.
path: prds/runbooks/{slug}/RUNBOOK.md
sections:
  - {id: steps, header: Steps, required: true}
''';
    const runbook = 'prds/runbooks/deploy/RUNBOOK.md';
    const notes = 'prds/runbooks/deploy/NOTES.md';
    final fixture = await _fixture(
      packYaml: rotationPack,
      runbookType: types,
      overrides: const {},
      docs: const {
        runbook: '# Deploy\n\n## Steps\n\nx\n',
        notes: '# Notes\n\n## Steps\n\ny\n',
      },
    );

    final plan = _plan(fixture);

    expect(
      [for (final move in plan.moves) (move.from, move.to)],
      [(runbook, notes), (notes, runbook)],
    );
    expect(plan.toText(), isNot(contains('.specstone/trash')));
    expect(
      [
        for (final step in plan.journalSteps(base: 'abc'))
          if (step is MoveStep) step.describe(),
      ],
      [
        'move docs/$runbook -> .specstone/trash/stage/0',
        'move docs/$notes -> docs/$runbook',
        'move .specstone/trash/stage/0 -> docs/$notes',
      ],
    );
  });

  test('f06/us02/fr02/e08: one refusal lists a move collision and a rename '
      'collision together', () async {
    const packYaml = '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - move_file: {doc_type: runbook, from: "prds/runbooks/{slug}/RUNBOOK.md", to: "prds/runbooks/{slug}/PLAYBOOK.md"}
      - rename_field: {doc_type: runbook, from: owner, to: on_call}
''';
    const type = '''
id: runbook
description: A runbook.
path: prds/runbooks/{slug}/PLAYBOOK.md
fields:
  - {id: on_call, type: string}
sections:
  - {id: steps, header: Steps, required: true}
''';
    final fixture = await _fixture(
      packYaml: packYaml,
      runbookType: type,
      overrides: const {},
      docs: const {
        'prds/runbooks/deploy/RUNBOOK.md': '# Deploy\n\n## Steps\n\nx\n',
        'prds/runbooks/deploy/PLAYBOOK.md': '# Kept\n\n## Steps\n\ny\n',
        'prds/runbooks/other/PLAYBOOK.md':
            '---\nowner: sre\non_call: ira\n---\n# Other\n\n## Steps\n\nz\n',
      },
    );

    await expectLater(
      () => _plan(fixture),
      throwsA(
        isA<MigrateFault>()
            .having((f) => f.code, 'code', MigrateFaultCode.upgradeCollision)
            .having((f) => f.more, 'more', hasLength(1))
            .having(
              (f) => f.toText(),
              'text',
              'prds/runbooks/deploy/RUNBOOK.md: move_file of runbook moves '
                  'prds/runbooks/{slug}/RUNBOOK.md to '
                  'prds/runbooks/{slug}/PLAYBOOK.md, which the doc already '
                  'there holds; move, rename, or merge each listed doc or '
                  'entry so the step no longer lands on it, then run '
                  'specstone migrate again\n'
                  'prds/runbooks/other/PLAYBOOK.md: rename_field of runbook '
                  'renames owner to on_call, which the doc already holds; '
                  'move, rename, or merge each listed doc or entry so the '
                  'step no longer lands on it, then run specstone migrate '
                  'again',
            ),
      ),
    );
  });

  test('f06/us02/fr02, f06/us02/s2: the s02 upgrade plan', () async {
    final plan = _plan(await _fixture());

    expect(
      plan.toText(),
      'pack upgrade: acme 1.0.0 -> 1.2.0\n'
      'commit 2, rewrites:\n'
      '  from 1.0.0: rename_section runbook steps -> procedure: '
      'prds/runbooks/deploy/RUNBOOK.md, .specstone/templates/runbook.yaml\n'
      '  from 1.1.0: rename_field runbook owner -> on_call: '
      'prds/runbooks/deploy/RUNBOOK.md\n'
      '  .specstone/config.yaml: acme 1.2.0\n',
    );
    expect(plan.moves, isEmpty);
    expect(plan.commit1Message, 'move docs to their new pack paths');
    expect(plan.commit2Message, 'upgrade pack pins');
    expect(plan.closingLine, isNull);
    expect(plan.left, isEmpty);
  });

  test('f06/us02/fr02/e02: the override takes the new id and keeps every '
      'other key', () async {
    final plan = _plan(await _fixture());

    expect(
      _rewriteAt(plan, _overridePath).text,
      'sections: [{id: procedure, required: true, description: Kept.}]\n',
    );
  });

  test('f06/us02/fr02/e02: an after naming the renamed id takes the new id, '
      'every other byte stays', () async {
    final plan = _plan(
      await _fixture(
        overrides: {
          _overridePath:
              '# mine\n'
              'sections:\n'
              '  - id: "steps"   # kept\n'
              '    required: true\n'
              '  - id: extra\n'
              '    header: Extra\n'
              '    after: steps\n',
        },
      ),
    );

    expect(
      _rewriteAt(plan, _overridePath).text,
      '# mine\n'
      'sections:\n'
      '  - id: "procedure"   # kept\n'
      '    required: true\n'
      '  - id: extra\n'
      '    header: Extra\n'
      '    after: procedure\n',
    );
  });

  test('f06/us02/fr02/e03: an override field with the old id takes the new '
      'id and keeps every other key', () async {
    final plan = _plan(
      await _fixture(
        overrides: const {
          _overridePath:
              'fields:\n'
              '  - id: owner\n'
              '    type: string\n'
              '    description: Kept.\n',
        },
      ),
    );

    expect(
      _rewriteAt(plan, _overridePath).text,
      'fields:\n'
      '  - id: on_call\n'
      '    type: string\n'
      '    description: Kept.\n',
    );
    expect(
      plan.toText(),
      contains(
        'from 1.1.0: rename_field runbook owner -> on_call: '
        'prds/runbooks/deploy/RUNBOOK.md, .specstone/templates/runbook.yaml\n',
      ),
    );
  });

  test('f06/us02/fr02, final I2: every step skips a doc that is not UTF-8, '
      'and the others still change', () async {
    final fixture = await _fixture(
      docs: const {
        'prds/runbooks/deploy/RUNBOOK.md': _runbookDoc,
        'prds/runbooks/legacy/RUNBOOK.md': '',
      },
    );
    // `## Steps` then `é` in Windows-1252: 0xe9 is no UTF-8 sequence.
    File.fromUri(
      fixture.project.uri.resolve('docs/prds/runbooks/legacy/RUNBOOK.md'),
    ).writeAsBytesSync([...'## Steps\n'.codeUnits, 0xe9, 0x0a]);

    final plan = _plan(fixture);

    expect(plan.rewrites.map((r) => r.path), [
      'docs/prds/runbooks/deploy/RUNBOOK.md',
      _overridePath,
      '.specstone/config.yaml',
    ]);
  });

  test('f06/us02/fr02, final I2: a doc that cannot be read refuses '
      'output_not_writable naming it', () async {
    final fixture = await _fixture();
    final runbook = File.fromUri(
      fixture.project.uri.resolve('docs/prds/runbooks/deploy/RUNBOOK.md'),
    );
    expect(Process.runSync('chmod', ['000', runbook.path]).exitCode, 0);
    addTearDown(() => Process.runSync('chmod', ['644', runbook.path]));

    expect(
      () => _plan(fixture),
      throwsA(
        isA<RenderFault>()
            .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
            .having(
              (f) => f.message,
              'message',
              startsWith('cannot read prds/runbooks/deploy/RUNBOOK.md: '),
            ),
      ),
    );
  }, skip: unreadablePathSkipReason());

  test('f06/us02/fr02/e03: a renamed field keeps its value', () async {
    final plan = _plan(await _fixture());

    final text = _rewriteAt(plan, 'docs/prds/runbooks/deploy/RUNBOOK.md').text;
    expect(text, contains('on_call: sre\n'));
    expect(text, isNot(contains('owner')));
    expect(text, contains('## Procedure\n'));
  });

  test('f06/us02/fr02/e05: two chained renames end in the last name, written '
      'once', () async {
    const packYaml = '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - rename_section: {doc_type: runbook, from: {id: a, header: A}, to: {id: b, header: B}}
  - from: 1.1.0
    steps:
      - rename_section: {doc_type: runbook, from: {id: b, header: B}, to: {id: c, header: C}}
''';
    const type = '''
id: runbook
description: A runbook.
path: prds/runbooks/{slug}/RUNBOOK.md
sections:
  - {id: c, header: C, required: true}
''';
    final plan = _plan(
      await _fixture(
        packYaml: packYaml,
        runbookType: type,
        overrides: const {},
        docs: const {
          'prds/runbooks/deploy/RUNBOOK.md': '# Deploy\n\n## A\n\nx\n',
        },
      ),
    );

    final writes = plan.rewrites.where(
      (rewrite) => rewrite.path == 'docs/prds/runbooks/deploy/RUNBOOK.md',
    );
    expect(writes, hasLength(1));
    expect(writes.single.text, '# Deploy\n\n## C\n\nx\n');
  });

  test(
    'f06/us02/fr02/e07: a doc already lacking the section is unchanged',
    () async {
      final plan = _plan(
        await _fixture(
          overrides: const {},
          docs: const {
            'prds/runbooks/deploy/RUNBOOK.md': '# Deploy\n\n## Rollback\n\nx\n',
          },
        ),
      );

      expect(plan.rewrites.map((rewrite) => rewrite.path), [
        '.specstone/config.yaml',
      ]);
      expect(
        plan.toText(),
        contains('rename_section runbook steps -> procedure: no doc changes\n'),
      );
    },
  );

  test("f06/us02/fr01/e04, f06/us02/s4: the older release's steps print "
      'first', () async {
    final both = _plan(await _fixture()).toText();
    final newer = _plan(await _fixture(acmePin: '1.1.0', overrides: const {}))
        .toText();

    expect(both.indexOf('from 1.0.0:'), lessThan(both.indexOf('from 1.1.0:')));
    expect(newer, isNot(contains('from 1.0.0:')));
    expect(newer, contains('from 1.1.0: rename_field'));
  });

  test(
    'f06/us02/fr02/e01: a release with no step changes the pin only',
    () async {
      final plan = _plan(
        await _fixture(
          packYaml: 'name: acme\nversion: 1.2.0\nextends: software-tech\n',
          overrides: const {},
        ),
      );

      expect(plan.toText(), '''
pack upgrade: acme 1.0.0 -> 1.2.0
commit 2, rewrites:
  .specstone/config.yaml: acme 1.2.0
''');
      expect(_rewriteAt(plan, '.specstone/config.yaml').text, _config('1.2.0'));
      expect(plan.moves, isEmpty);
      expect(plan.prunes, isEmpty);
    },
  );

  test('f06/us02/fr02/e04: a move_file step keeps the placeholder values and '
      'points links at the new path', () async {
    const packYaml = '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - move_file: {doc_type: runbook, from: "prds/runbooks/{slug}/RUNBOOK.md", to: "ops/runbooks/{slug}/RUNBOOK.md"}
''';
    const type = '''
id: runbook
description: A runbook.
path: ops/runbooks/{slug}/RUNBOOK.md
sections:
  - {id: steps, header: Steps, required: true}
''';
    final plan = _plan(
      await _fixture(
        packYaml: packYaml,
        runbookType: type,
        overrides: const {},
        docs: const {
          'prds/runbooks/deploy/RUNBOOK.md': '# Deploy\n\n## Steps\n\nx\n',
          'prds/notes.md': '# Notes\n\n[run](runbooks/deploy/RUNBOOK.md)\n',
        },
      ),
    );

    expect(plan.moves, [
      (
        from: 'prds/runbooks/deploy/RUNBOOK.md',
        to: 'ops/runbooks/deploy/RUNBOOK.md',
      ),
    ]);
    expect(plan.prunes, ['docs/prds/runbooks/deploy']);
    expect(
      _rewriteAt(plan, 'docs/prds/notes.md').text,
      '# Notes\n\n[run](../ops/runbooks/deploy/RUNBOOK.md)\n',
    );
    expect(
      plan.toText(),
      'pack upgrade: acme 1.0.0 -> 1.2.0\n'
      'commit 1, moves:\n'
      '  prds/runbooks/deploy/RUNBOOK.md -> ops/runbooks/deploy/RUNBOOK.md\n'
      'commit 2, rewrites:\n'
      '  from 1.0.0: move_file runbook prds/runbooks/{slug}/RUNBOOK.md -> '
      'ops/runbooks/{slug}/RUNBOOK.md: ops/runbooks/deploy/RUNBOOK.md\n'
      '  prds/notes.md: 1 link\n'
      '  .specstone/config.yaml: acme 1.2.0\n',
    );
  });
}
