import 'dart:io';

import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart'
    show MoveStep;
import 'package:specstone_core/src/plan_hash.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/setup_migration/agent_files.dart'
    show agentMdText;
import 'package:specstone_core/src/setup_migration/agent_targets.dart'
    show agentFilesSince;
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/run_plan.dart';
import 'package:specstone_core/src/setup_migration/upgrade_plan.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart'
    show shippedPackVersions;
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:specstone_core/src/version.dart';
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
  _agentFilesTests();
  _renumberTests();

  test('agentFilesSince matches the shipped versions of its packs', () {
    final shipped = shippedPackVersions();
    for (final entry in agentFilesSince.entries) {
      expect(shipped[entry.key], entry.value.toString());
    }
  });

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
        for (final step in plan.journalSteps(
          base: 'abc',
          projectRoot: Directory.systemTemp,
        ))
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

  test('setup_migration/upgrade_pack_pins/apply_steps_and_pins E11: pins equal '
      'and two docs off their layout plan the layout pass alone', () async {
    final plan = _plan(
      await _fixture(
        acmePin: '1.2.0',
        overrides: const {},
        docs: const {
          'prds/GNFR.md': '## Reliability\n\nr\n\n## Performance\n\np\n',
          'prds/PROJECT.md': '## Project vision\n\nv\n\n## Project name\n\nn\n',
          'prds/features/f01_a/FEATURE.md':
              '## Problem\n\nn\n\n## Benefit hypothesis\n\ng\n',
        },
      ),
    );

    expect(
      plan.toText(),
      'pack upgrade: pins unchanged, layout only\n'
      'commit 2, rewrites:\n'
      '  format layout: prds/GNFR.md, prds/PROJECT.md\n',
    );
    expect(plan.commit2Message, 'lay docs out as format writes them');
    expect(plan.moves, isEmpty);
    expect(plan.rewrites.map((rewrite) => rewrite.path), [
      'docs/prds/GNFR.md',
      'docs/prds/PROJECT.md',
    ]);
  });

  test('setup_migration/upgrade_pack_pins/chain_migration_steps E07: a doc a '
      'step renames and a doc no step touches are each laid out once, a '
      'laid-out doc is not rewritten, a refused doc is left', () async {
    final plan = _plan(
      await _fixture(
        docs: const {
          'prds/runbooks/deploy/RUNBOOK.md':
              '---\nowner: sre\n---\n# Deploy\n\n## Steps\n\nRun it.   \n',
          'prds/features/f01_a/FEATURE.md':
              '## Benefit hypothesis\n\ng\n\n\n## Problem\n\nn\n',
          'prds/features/f02_b/FEATURE.md':
              '## Problem\n\nn\n\n## Benefit hypothesis\n\ng\n',
          'prds/features/f03_c/FEATURE.md': '## Notes\nx   \n',
        },
      ),
    );

    expect(
      _rewriteAt(plan, 'docs/prds/runbooks/deploy/RUNBOOK.md').text,
      '---\non_call: sre\n---\n# Deploy\n\n## Procedure\n\nRun it.\n',
    );
    expect(
      _rewriteAt(plan, 'docs/prds/features/f01_a/FEATURE.md').text,
      '## Problem\n\nn\n\n## Benefit hypothesis\n\ng\n',
    );
    expect(
      plan.rewrites.map((rewrite) => rewrite.path),
      isNot(
        contains(
          anyOf(
            'docs/prds/features/f02_b/FEATURE.md',
            'docs/prds/features/f03_c/FEATURE.md',
          ),
        ),
      ),
    );
    expect(
      plan.toText(),
      contains(
        '  format layout: prds/features/f01_a/FEATURE.md, '
        'prds/runbooks/deploy/RUNBOOK.md\n'
        '  .specstone/config.yaml: acme 1.2.0\n',
      ),
    );
  });

  test('setup_migration/upgrade_pack_pins/apply_steps_and_pins E01: an older '
      'pin with no selected step lays out an off-layout doc beside the new '
      'pin', () async {
    final plan = _plan(
      await _fixture(
        packYaml: 'name: acme\nversion: 1.2.0\nextends: software-tech\n',
        overrides: const {},
        docs: const {
          'prds/features/f01_a/FEATURE.md':
              '## Benefit hypothesis\n\ng\n\n\n## Problem\n\nn\n',
        },
      ),
    );

    expect(
      plan.toText(),
      'pack upgrade: acme 1.0.0 -> 1.2.0\n'
      'commit 2, rewrites:\n'
      '  format layout: prds/features/f01_a/FEATURE.md\n'
      '  .specstone/config.yaml: acme 1.2.0\n',
    );
    expect(plan.commit2Message, 'upgrade pack pins');
  });
}

const _fr = 'setup_migration/upgrade_pack_pins/apply_steps_and_pins';
const _begin = '<!-- BEGIN specstone v$specstoneVersion -->';
const _staleBlock = '$_begin\nold rules\n<!-- END specstone -->\n';
const _belowSince = 'packs:\n  prd-core: 1.0.0\n  software-tech: 1.0.0\n';

Directory _canonical(Directory directory) =>
    Directory(directory.resolveSymbolicLinksSync());

RunPlan _planAt(Directory project) => planUpgradeRun(
  _canonical(project),
  templates: TemplateResolver(),
  homeDirectory: null,
);

void _agentFilesTests() {
  group('agent files step', () {
    test('$_fr E14: a pin below agentFilesSince writes every agent file once, '
        'the Owner rules kept', () async {
      final project = await writeTree({
        '.specstone/config.yaml': _belowSince,
        'CLAUDE.md': '# Owner rules\n',
      });

      final plan = _planAt(project);

      final agents = plan.agentFiles!;
      expect(agents.rootWrites.map((write) => write.path), [
        '.specstone/AGENT.md',
        'CLAUDE.md',
      ]);
      expect(agents.rootWrites.last.text, startsWith('# Owner rules\n'));
      expect(agents.rootWrites.last.text, contains(_begin));
      expect(
        plan.toText(),
        contains('agent files: .specstone/AGENT.md, CLAUDE.md'),
      );
    });

    test('$_fr E14: a pin equal to agentFilesSince refreshes, never the '
        'one-time write', () async {
      final project = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
        'AGENTS.md': '# Owner rules\n',
      });

      final plan = _planAt(project);

      // Refresh-only: no rules file gains a block and no file is created.
      expect(plan.agentFiles!.rootWrites, isEmpty);
      expect(plan.agentFiles!.topWrites, isEmpty);
      expect(plan.agentFiles!.addedRoots, isEmpty);
    });

    test('$_fr E14: a later upgrade never adds a deleted block or the rules '
        'file', () async {
      final project = await writeTree({
        '.specstone/config.yaml': _config('1.0.0'),
        'CLAUDE.md': '# Owner rules\n',
      });
      final home = await writeTree({
        '.specstone/packs/acme/pack.yaml': _runbookPackYaml,
        '.specstone/packs/acme/runbook.yaml': _runbookType,
      });

      final plan = planUpgradeRun(
        _canonical(project),
        templates: TemplateResolver(),
        homeDirectory: home,
      );

      expect(plan.agentFiles!.isEmpty, isTrue);
      expect(plan.toText(), isNot(contains('agent files:')));
    });

    test('$_fr E12, E14: the agent files line prints after the steps and '
        'before the pins', () async {
      final fixture = await _fixture(docs: const {}, overrides: const {});
      final projectPath = fixture.project.path;
      Directory('$projectPath/code/.git').createSync(recursive: true);
      File('$projectPath/.specstone/config.yaml')
          .writeAsStringSync('${_config('1.0.0')}code_root: code\n');

      final plan = _plan(fixture);

      final text = plan.toText();
      final stepAt = text.indexOf('from 1.1.0: rename_field');
      final agentsAt = text.indexOf('agent files: code/AGENTS.md');
      final pinAt = text.indexOf('.specstone/config.yaml: acme 1.2.0');
      expect(stepAt, greaterThan(0), reason: 'the steps print');
      expect(agentsAt, greaterThan(stepAt), reason: 'agent files after steps');
      expect(pinAt, greaterThan(agentsAt), reason: 'pins after agent files');
    });

    test('$_fr E12: every pin equal and a stale block gives the agent-only '
        'plan', () async {
      final project = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
        '.specstone/AGENT.md': agentMdText,
        'CLAUDE.md': '# Owner rules\n\n$_staleBlock',
      });

      final plan = _planAt(project);

      expect(
        plan.toText(),
        'pack upgrade: pins unchanged, agent files only\n'
        'commit 2, rewrites:\n'
        '  agent files: CLAUDE.md\n',
      );
      expect(plan.commit2Message, 'refresh the Specstone agent files');
      expect(plan.rewrites, isEmpty);
      expect(plan.moves, isEmpty);
    });

    test('$_fr E11, E12: every pin equal, a doc off its layout, and a stale '
        'block print the layout line, then the agent files line', () async {
      final project = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
        '.specstone/AGENT.md': agentMdText,
        'CLAUDE.md': '# Owner rules\n\n$_staleBlock',
        'docs/prds/GNFR.md': '## Reliability\n\nr\n\n## Performance\n\np\n',
      });

      final plan = _planAt(project);

      expect(
        plan.toText(),
        'pack upgrade: pins unchanged, layout and agent files\n'
        'commit 2, rewrites:\n'
        '  format layout: prds/GNFR.md\n'
        '  agent files: CLAUDE.md\n',
      );
      expect(
        plan.commit2Message,
        'lay docs out and refresh the Specstone agent files',
      );
      expect(plan.rewrites.map((rewrite) => rewrite.path), [
        'docs/prds/GNFR.md',
      ]);
    });

    test('$_fr E17: a repository top unlisted in agent_file_roots takes its '
        'files outside the commits and joins the config', () async {
      final project = await writeTree({
        '.specstone/config.yaml': '${shippedPinsConfig()}code_root: code\n',
        'code/.git/HEAD': 'ref: refs/heads/main\n',
      });

      final plan = _planAt(project);

      final agents = plan.agentFiles!;
      expect(agents.topWrites.map((write) => write.path), ['code/AGENTS.md']);
      expect(agents.addedRoots, ['code']);
      expect(plan.toText(), contains('  agent files: code/AGENTS.md\n'));
      expect(
        _rewriteAt(plan, '.specstone/config.yaml').text,
        '${shippedPinsConfig()}code_root: code\nagent_file_roots:\n'
        '  - code\n',
      );
      expect(_rewriteAt(plan, '.specstone/config.yaml').changes, [
        'agent_file_roots',
      ]);
    });

    test(
      '$_fr E17: a bare agent_file_roots key rewrites to a valid list',
      () async {
        final project = await writeTree({
          '.specstone/config.yaml':
              '${shippedPinsConfig()}code_root: code\nagent_file_roots:\n',
          'code/.git/HEAD': 'ref: refs/heads/main\n',
        });

        final plan = _planAt(project);

        expect(
          _rewriteAt(plan, '.specstone/config.yaml').text,
          '${shippedPinsConfig()}code_root: code\n'
          'agent_file_roots:\n  - code\n',
        );
      },
    );

    test(
      '$_fr E17: a replaced agent_file_roots drops an end-of-line comment',
      () async {
        final project = await writeTree({
          '.specstone/config.yaml':
              '${shippedPinsConfig()}code_root: code\n'
              'agent_file_roots: [other] # keep\n',
          'code/.git/HEAD': 'ref: refs/heads/main\n',
        });

        final plan = _planAt(project);

        expect(
          _rewriteAt(plan, '.specstone/config.yaml').text,
          '${shippedPinsConfig()}code_root: code\n'
          'agent_file_roots:\n  - other\n  - code\n',
        );
      },
    );

    test('$_fr E17: the config rewrite replaces a listed agent_file_roots '
        'and keeps every other key', () async {
      final project = await writeTree({
        '.specstone/config.yaml':
            'packs:\n  prd-core: 1.0.0\n  software-tech: 1.0.0\n'
            'agent_file_roots:\n  - old\ncode_root: code\n',
        'code/.git/HEAD': 'ref: refs/heads/main\n',
        'old/.git/HEAD': 'ref: refs/heads/main\n',
      });

      final plan = _planAt(project);

      final text = _rewriteAt(plan, '.specstone/config.yaml').text;
      expect(text, contains('code_root: code\n'));
      expect(text, contains('  - old\n'));
      expect(text, contains('  - code\n'));
      expect(text, isNot(contains('prd-core: 1.0.0')));
    });

    test(
      '$_fr E16: a malformed block refuses before the plan returns',
      () async {
        final project = await writeTree({
          '.specstone/config.yaml': _belowSince,
          'AGENTS.md': '$_begin\nbody\n',
        });

        expect(
          () => _planAt(project),
          throwsA(
            isA<MigrateFault>().having(
              (fault) => fault.code,
              'code',
              MigrateFaultCode.agentBlockMalformed,
            ),
          ),
        );
      },
    );
  });
}

const _storyPath = 'prds/features/f01_a/us01_b/USER_STORY.md';
const _topicPath = 'specs/topics/doc_model.md';
const _lettered = '### Scenario 6a — [edge] lettered\n- **Given** g\n';
const _renumbered = '### Scenario 9 — [edge] lettered\n\n- **Given** g';

const _topic = '''
# Doc model

## Rules

- **RULE-1** — One.
- **RULE-7a** — Lettered.
- **RULE-30** — Thirty.
''';

const _story = '''
# B

## Acceptance Criteria

### Scenario 1 — [happy] one

- **Given** g

### Scenario 8 — [error] eight

- **Given** g

$_lettered''';

String _tracingFr(String fingerprint, {String body = ''}) =>
    '---\ntraced_from:\n  - S6a\nconfirmed:\n  - S6a $fingerprint\n---\n'
    '# C\n$body';

/// The E18 tree under `docs/`: the topic and story with lettered IDs, two FRs
/// tracing Scenario 6a, one matched and one suspect, and a domain doc citing
/// the topic by path.
Map<String, String> _e18Docs({String topic = _topic}) => {
  _topicPath: topic,
  'specs/topics/other_topic.md':
      '# Other topic\n\n## Rules\n\n- **RULE-1** — One.\n',
  _storyPath: _story,
  'prds/features/f01_a/us01_b/fr01_c.md': _tracingFr(
    fingerprintOf(_lettered),
    body: '\n## Statement\n\n`doc_model` RULE-7a\n`other_topic` RULE-7a\n',
  ),
  'prds/features/f01_a/us01_b/fr02_g.md': _tracingFr('000000000000'),
  'specs/f01_a/DOMAIN.md':
      '# A\n\n## Invariants\n\n[rules](../topics/doc_model.md) RULE-7a\n'
      '`../topics/doc_model.md` RULE-7a\n',
};

Future<Directory> _belowSinceTree(Map<String, String> docs) => writeTree({
  '.specstone/config.yaml': _belowSince,
  for (final MapEntry(:key, :value) in docs.entries) 'docs/$key': value,
});

String _docText(RunPlan plan, String docPath) =>
    _rewriteAt(plan, 'docs/$docPath').text;

ProcessResult _missingGit(
  List<String> arguments, {
  required String workingDirectory,
}) => throw const ProcessException('git', []);

void _renumberTests() {
  group('renumber pass', () {
    test('$_fr E18: the upgrade renumbers each lettered ID once and rewrites '
        'every reference, listed on one renumber ids line', () async {
      final plan = _planAt(await _belowSinceTree(_e18Docs()));

      final text = plan.toText();
      const line =
          '  renumber ids: $_storyPath Scenario 6a -> Scenario 9, '
          '$_topicPath RULE-7a -> RULE-31; references: '
          'prds/features/f01_a/us01_b/fr01_c.md, '
          'prds/features/f01_a/us01_b/fr02_g.md, specs/f01_a/DOMAIN.md\n';
      expect(text, contains(line));
      expect(text.indexOf(line), lessThan(text.indexOf('  format layout: ')));
      expect(text.indexOf(line), lessThan(text.indexOf('  agent files: ')));
      expect(
        _docText(plan, _topicPath),
        contains('- **RULE-31** — Lettered.\n'),
      );
      expect(_docText(plan, _storyPath), contains('$_renumbered\n'));
      expect(
        _docText(plan, 'prds/features/f01_a/us01_b/fr01_c.md'),
        allOf(
          startsWith(
            '---\ntraced_from:\n  - S9\nconfirmed:\n'
            '  - S9 ${fingerprintOf(_renumbered)}\n---\n',
          ),
          contains('`doc_model` RULE-31\n`other_topic` RULE-7a\n'),
        ),
      );
      expect(
        _docText(plan, 'specs/f01_a/DOMAIN.md'),
        contains(
          '[rules](../topics/doc_model.md) RULE-31\n'
          '`../topics/doc_model.md` RULE-31\n',
        ),
      );
    });

    test('$_fr E18: a confirmed entry already suspect keeps its fingerprint '
        'and takes the new label', () async {
      final plan = _planAt(await _belowSinceTree(_e18Docs()));

      expect(
        _docText(plan, 'prds/features/f01_a/us01_b/fr02_g.md'),
        startsWith(
          '---\ntraced_from:\n  - S9\nconfirmed:\n  - S9 000000000000\n',
        ),
      );
    });

    test('$_fr E18: the plan hash changes with the renumbered set', () async {
      final both = await _belowSinceTree(_e18Docs());
      final storyOnly = await _belowSinceTree(
        _e18Docs(topic: _topic.replaceFirst('RULE-7a', 'RULE-7')),
      );

      final bothText = _planAt(both).toText();
      final storyOnlyText = _planAt(storyOnly).toText();

      expect(storyOnlyText, isNot(contains('RULE-7a -> RULE-31')));
      expect(
        planHashOf(bothText, both, _missingGit),
        isNot(planHashOf(storyOnlyText, storyOnly, _missingGit)),
      );
    });

    test('$_fr E19: two lettered scenarios renumber in document order to the '
        'numbers check names', () async {
      const story = '''
# B

## Acceptance Criteria

### Scenario 7 — [happy] seven

- **Given** g

### Scenario 6a — [edge] a

- **Given** g

### Scenario 6b — [error] b

- **Given** g
''';

      final plan = _planAt(await _belowSinceTree({_storyPath: story}));

      expect(
        plan.toText(),
        contains(
          '  renumber ids: $_storyPath Scenario 6a -> Scenario 8, '
          '$_storyPath Scenario 6b -> Scenario 9\n',
        ),
      );
      expect(
        _docText(plan, _storyPath),
        allOf(
          contains('### Scenario 8 — [edge] a\n'),
          contains('### Scenario 9 — [error] b\n'),
        ),
      );
    });

    test('$_fr E14: an upgrade that moves no pin from below agentFilesSince '
        'renumbers nothing', () async {
      final plan = _plan(await _fixture(docs: const {_topicPath: _topic}));

      expect(plan.toText(), isNot(contains('renumber ids')));
      expect(
        plan.rewrites.map((rewrite) => rewrite.text),
        everyElement(isNot(contains('RULE-31'))),
      );
    });

    test('$_fr E18: the pass reads each doc after the selected steps, so a '
        'section a step renames is read under its template', () async {
      const packYaml = '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - rename_section: {doc_type: user_story, from: {id: scenarios, header: Scenarios}, to: {id: acceptance_criteria, header: Acceptance Criteria}}
''';
      final home = await writeTree({
        '.specstone/packs/acme/pack.yaml': packYaml,
        '.specstone/packs/acme/runbook.yaml': _runbookType,
      });
      final project = await writeTree({
        '.specstone/config.yaml': '$_belowSince  acme: 1.0.0\n',
        'docs/$_storyPath':
            '# B\n\n## Scenarios\n\n### Scenario 1 — [happy] one\n\n'
            '- **Given** g\n\n### Scenario 1a — [edge] a\n\n- **Given** g\n',
      });

      final plan = planUpgradeRun(
        _canonical(project),
        templates: TemplateResolver(),
        homeDirectory: home,
      );

      expect(
        plan.toText(),
        contains('  renumber ids: $_storyPath Scenario 1a -> Scenario 2\n'),
      );
      expect(
        _docText(plan, _storyPath),
        contains(
          '## Acceptance Criteria\n\n### Scenario 1 — [happy] one\n\n'
          '- **Given** g\n\n### Scenario 2 — [edge] a\n',
        ),
      );
    });

    test(
      '$_fr E18: a CRLF story with a byte order mark keeps both, its FR and '
      'journey step follow it, and a second upgrade changes nothing',
      () async {
        final bom = String.fromCharCode(0xFEFF);
        const lettered = '### Scenario 6a — [edge] x\n\n- **Given** g';
        final story =
            '$bom# B\r\n\r\n## Acceptance Criteria\r\n\r\n'
            '### Scenario 1 — [happy] one\r\n\r\n- **Given** g\r\n\r\n'
            '${lettered.replaceAll('\n', '\r\n')}\r\n';
        final fingerprint = fingerprintOf(lettered);
        final project = await _belowSinceTree({
          _storyPath: story,
          'prds/features/f01_a/us01_b/fr01_c.md': _tracingFr(fingerprint),
          'prds/journeys/go/JOURNEY.md':
              '---\nconfirmed:\n  - a/b#S6a $fingerprint\n---\n# Go\n\n'
              '## Steps\n\n### 1. Start\n\nstep: a/b S6a\n',
        });

        final plan = _planAt(project);

        const renumbered = '### Scenario 2 — [edge] x\n\n- **Given** g';
        expect(
          _docText(plan, _storyPath),
          allOf(
            startsWith('$bom# B\r\n'),
            contains('${renumbered.replaceAll('\n', '\r\n')}\r\n'),
            isNot(matches(RegExp('[^\r]\n'))),
          ),
        );
        expect(
          _docText(plan, 'prds/features/f01_a/us01_b/fr01_c.md'),
          contains('  - S2\nconfirmed:\n  - S2 ${fingerprintOf(renumbered)}\n'),
        );
        expect(
          _docText(plan, 'prds/journeys/go/JOURNEY.md'),
          allOf(
            contains('  - a/b#S2 ${fingerprintOf(renumbered)}\n'),
            contains('step: a/b S2\n'),
          ),
        );

        for (final rewrite in plan.rewrites) {
          File.fromUri(project.uri.resolve(rewrite.path))
              .writeAsStringSync(rewrite.text);
        }
        final second = _planAt(project);

        expect(second.toText(), isNot(contains('renumber ids')));
        expect(
          second.rewrites.map((rewrite) => rewrite.path),
          everyElement(isNot(startsWith('docs/'))),
        );
      },
    );
  });
}
