import 'dart:io';

import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/doc_model/doc.dart' show Doc;
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/document_writing/approval.dart'
    show approvalHashOf, withApprovalHash;
import 'package:specstone_core/src/document_writing/move_journal.dart'
    show MoveStep, WriteStep, textHashOf;
import 'package:specstone_core/src/git_process.dart' show RunGit;
import 'package:specstone_core/src/index_query/indexed_doc.dart'
    show frontmatterValuesOf;
import 'package:specstone_core/src/plan_hash.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/setup_migration/agent_files.dart'
    show agentMdText;
import 'package:specstone_core/src/setup_migration/agent_targets.dart'
    show agentFilesSince;
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/record_placement.dart'
    show typeBeforeMoves;
import 'package:specstone_core/src/setup_migration/run_plan.dart';
import 'package:specstone_core/src/setup_migration/upgrade_plan.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/pack_migration.dart'
    show MoveToRecord;
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart'
    show shippedPackVersions;
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:specstone_core/src/version.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' show withApprovalHashes;
import '../../helpers/posix_modes.dart';
import '../../helpers/record_fixture.dart'
    show oneTargetConfig, recordLayer, recordText, twinConfig;
import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';

const _apply = 'setup_migration/upgrade_pack_pins/apply_steps_and_pins';

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
  _labelTests();
  _stampTests();
  _moveToRecordTests();
  _treeMoveTests();
  _planInputTests();

  test('agentFilesSince stays at the fixed versions, none past a shipped '
      'version, so software-tech 1.4.0 to 1.5.0 runs no one-time pass', () {
    final shipped = shippedPackVersions();
    for (final entry in agentFilesSince.entries) {
      final carried = PackVersion.parse(
        shipped[entry.key]!,
        file: 'shipped_pack_files',
        key: entry.key,
      );
      expect(carried.compareTo(entry.value), greaterThanOrEqualTo(0));
    }
    expect(agentFilesSince['software-tech'].toString(), '1.4.0');
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

  test('f06/us02/fr02/e08: two docs whose new paths differ only in letter case '
      'collide', () async {
    const packYaml = '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - move_file: {doc_type: runbook, from: "prds/runbooks/{slug}/RUNBOOK.md", to: "prds/runbooks/{slug}/BOOK.md"}
      - move_file: {doc_type: runbook, from: "prds/ops/{slug}/RUNBOOK.md", to: "prds/runbooks/{slug}/book.md"}
''';
    const type = '''
id: runbook
description: A runbook.
path: prds/runbooks/{slug}/BOOK.md
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
            .having((f) => f.code, 'code', MigrateFaultCode.upgradeCollision)
            .having((f) => f.more, 'more', hasLength(1)),
      ),
    );
  });

  test('f06/us02/fr02/e08: a move onto a staying doc that differs only in '
      'letter case collides', () async {
    const packYaml = '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - move_file: {doc_type: runbook, from: "prds/runbooks/{slug}/RUNBOOK.md", to: "prds/runbooks/{slug}/Book.md"}
''';
    const type = '''
id: runbook
description: A runbook.
path: prds/runbooks/{slug}/Book.md
sections:
  - {id: steps, header: Steps, required: true}
''';
    final fixture = await _fixture(
      packYaml: packYaml,
      runbookType: type,
      overrides: const {},
      docs: const {
        'prds/runbooks/deploy/RUNBOOK.md': '# Deploy\n\n## Steps\n\nx\n',
        'prds/runbooks/deploy/book.md': '# Kept\n\n## Steps\n\ny\n',
      },
    );

    await expectLater(
      () => _plan(fixture),
      throwsA(
        isA<MigrateFault>()
            .having((f) => f.code, 'code', MigrateFaultCode.upgradeCollision)
            .having((f) => f.more, 'more', hasLength(0)),
      ),
    );
  });

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

  test('$_apply E30: an upgrade past the one-time run re-stamps an approved '
      'doc its steps rewrite, so it stays approved', () async {
    final draftFixture = await _fixture(overrides: const {});
    final set = TemplateResolver().resolveCarried(
      packNames: ProjectConfig.read(draftFixture.project).pins.keys,
      homeDirectory: draftFixture.home,
    );
    const path = 'prds/runbooks/deploy/RUNBOOK.md';
    final type = switch (DocTypeMatcher(
      set,
      targetNames: const [],
    ).match(path)) {
      MatchedDocType(:final docType) => docType,
      _ => null,
    };
    final approved = withApprovalHash(_runbookDoc, type);
    final fixture = await _fixture(overrides: const {}, docs: {path: approved});

    final plan = _plan(fixture);

    final written = plan.rewrites.singleWhere((r) => r.path == 'docs/$path');
    expect(written.text, contains('## Procedure'));
    expect(
      RegExp(
        r'^approved: "(\w+)"$',
        multiLine: true,
      ).firstMatch(written.text)!.group(1),
      approvalHashOf(written.text, type),
    );
    final approvedLine = RegExp(
      r'^approved: .*$',
      multiLine: true,
    ).stringMatch(approved);
    expect(approvedLine, isNotNull);
    expect(written.text, isNot(contains(approvedLine)));
    expect(
      plan.toText(),
      contains('  stamps: 1 approval hashes, 0 fingerprints\n'),
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
          'prds/notes.md':
              '# Notes\n\n[run](runbooks/deploy/RUNBOOK.md) and '
              '`runbooks/deploy/RUNBOOK.md`\n',
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
      '# Notes\n\n[run](../ops/runbooks/deploy/RUNBOOK.md) and '
      '`../ops/runbooks/deploy/RUNBOOK.md`\n',
    );
    expect(
      plan.toText(),
      'pack upgrade: acme 1.0.0 -> 1.2.0\n'
      'commit 1, moves:\n'
      '  prds/runbooks/deploy/RUNBOOK.md -> ops/runbooks/deploy/RUNBOOK.md\n'
      'commit 2, rewrites:\n'
      '  from 1.0.0: move_file runbook prds/runbooks/{slug}/RUNBOOK.md -> '
      'ops/runbooks/{slug}/RUNBOOK.md: ops/runbooks/deploy/RUNBOOK.md\n'
      '  prds/notes.md: 1 link, 1 mention\n'
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

    test('$_fr E14: software-tech moving up from 1.3.0 with prd-core already '
        'at 1.7.0 writes every agent file once', () async {
      final project = await writeTree({
        '.specstone/config.yaml':
            'packs:\n  prd-core: 1.7.0\n  software-tech: 1.3.0\n',
        'CLAUDE.md': '# Owner rules\n',
      });

      final plan = _planAt(project);

      expect(plan.agentFiles!.rootWrites.map((write) => write.path), [
        '.specstone/AGENT.md',
        'CLAUDE.md',
      ]);
      expect(plan.toText(), contains('software-tech 1.3.0 -> 1.6.0'));
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
    _withoutStamp(_stampedDocText(plan, docPath));

String _stampedDocText(RunPlan plan, String docPath) =>
    _rewriteAt(plan, 'docs/$docPath').text;

final _approvedLine = RegExp(
  r'^approved: "[0-9a-f]{12}"\r?\n',
  multiLine: true,
);
final _emptyFrontmatter = RegExp(r'^(\uFEFF?)---\r?\n---\r?\n(?:\r?\n)?');

/// [text] without the approval hash the stamp pass wrote, for a test about
/// what the other passes wrote.
String _withoutStamp(String text) => text
    .replaceAll(_approvedLine, '')
    .replaceFirstMapped(_emptyFrontmatter, (match) => match.group(1)!);

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

    test('$_fr E18 (W3): an untyped doc, whose links check reads too, takes '
        'the new slug of a renumbered heading it links', () async {
      const notesPath = 'prds/notes.md';
      const link = 'See [it](features/f01_a/us01_b/USER_STORY.md#scenario-';
      final plan = _planAt(
        await _belowSinceTree({
          ..._e18Docs(),
          notesPath: '# Notes\n\n${link}6a--edge-lettered).\n',
        }),
      );

      expect(
        _docText(plan, notesPath),
        '# Notes\n\n${link}9--edge-lettered).\n',
      );
      expect(
        plan.toText(),
        contains('fr02_g.md, $notesPath, specs/f01_a/DOMAIN.md\n'),
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

      final bothPlan = _planAt(both);
      final storyOnlyPlan = _planAt(storyOnly);

      expect(storyOnlyPlan.toText(), isNot(contains('RULE-7a -> RULE-31')));
      expect(_hashOf(bothPlan), isNot(_hashOf(storyOnlyPlan)));
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

const _labelFeature = 'prds/features/f01_a/FEATURE.md';
const _labelFr = 'prds/features/f01_a/us01_b/fr01_c.md';
const _techStackPath = 'specs/TECH_STACK.md';

/// A fake `git` that lists [tracked] for `ls-files` and records its calls.
RunGit _tracking(Set<String> tracked, [List<List<String>>? calls]) =>
    (arguments, {required workingDirectory, environment}) {
      calls?.add([workingDirectory, ...arguments]);
      return ProcessResult(0, 0, tracked.map((path) => '$path\x00').join(), '');
    };

RunPlan _planWith(Directory project, [RunGit? runGit]) => planUpgradeRun(
  _canonical(project),
  templates: TemplateResolver(),
  homeDirectory: null,
  runGit: runGit ?? _tracking({}),
);

Future<Directory> _labelTree(
  Map<String, String> docs, {
  Map<String, String> code = const {},
  String pins = _belowSince,
}) => writeTree({
  '.specstone/config.yaml': pins,
  'docs/$_labelFeature': '# A\n',
  'docs/prds/features/f01_a/us01_b/USER_STORY.md': '# B\n',
  'docs/$_labelFr': '# C\n',
  'docs/$_techStackPath':
      '---\ncode:\n  - lib/\n  - vendor/\n---\n# Tech stack\n',
  for (final MapEntry(:key, :value) in docs.entries) 'docs/$key': value,
  ...code,
});

void _labelTests() {
  group('label pass', () {
    test('$_fr E26: the upgrade converts each label in a doc and lists the '
        'doc after the renumber line', () async {
      final project = await writeTree({
        '.specstone/config.yaml': _belowSince,
        for (final MapEntry(:key, :value) in _e18Docs().entries)
          'docs/$key': value,
        'docs/specs/topics/labelled.md':
            '# Labelled\n\n## Rules\n\nSee F-01 US-01 FR-01 and FR-09.\n',
      });

      final plan = _planAt(project);

      final text = plan.toText();
      expect(
        _docText(plan, 'specs/topics/labelled.md'),
        contains('See `a/b/c` and FR-09.'),
      );
      final lines = text.split('\n');
      final renumber = lines.indexWhere((l) => l.startsWith('  renumber ids:'));
      final labels = lines.indexWhere((l) => l.startsWith('  number labels:'));
      expect(renumber, isNonNegative);
      expect(labels, greaterThan(renumber));
      expect(
        lines[labels],
        '  number labels: specs/topics/labelled.md; left: '
        'specs/topics/labelled.md:9 FR-09',
      );
      expect(lines[labels + 1], startsWith('  '));
      expect(
        lines.indexWhere((l) => l.startsWith('  .specstone/config.yaml:')),
        greaterThan(labels),
      );
    });

    test('$_fr E26: a doc keeps its line ending, byte order mark, and link '
        'destinations', () async {
      final project = await _labelTree({
        'specs/topics/labelled.md': '\uFEFF# L\r\n\r\n## Rules\r\n\r\n[F-01 US-01](../../prds/features/f01_a/us01_b/USER_STORY.md) and F-01.\r\n',
      });

      final text = _docText(_planWith(project), 'specs/topics/labelled.md');

      expect(
        text,
        '\uFEFF# L\r\n\r\n## Rules\r\n\r\n[`a/b`](../../prds/features/f01_a/us01_b/USER_STORY.md) and `feature:a`.\r\n',
      );
    });

    test(
      '$_fr E26: a run that is no one-time pass leaves every label',
      () async {
        final project = await _labelTree({
          'specs/topics/labelled.md': '# L\n\nF-01 here.\n',
        }, pins: shippedPinsConfig());

        final plan = _planWith(project);

        expect(plan.toText(), isNot(contains('number labels:')));
        expect(
          plan.rewrites.where((r) => r.path.contains('labelled')),
          isEmpty,
        );
      },
    );

    test('$_fr E26: a tracked file under the code roots converts, a partial '
        'label in it stays listed, and line ending and mark stay', () async {
      final project = await _labelTree(
        {},
        code: {
          'lib/a.dart': '\uFEFF// See F-01 US-01 and FR-01\r\nint a = 0;\r\n',
        },
      );
      final calls = <List<String>>[];

      final plan = _planWith(project, _tracking({'lib/a.dart'}, calls));

      final rewrite = plan.rewrites.singleWhere((r) => r.path == 'lib/a.dart');
      expect(rewrite.text, '\uFEFF// See `a/b` and FR-01\r\nint a = 0;\r\n');
      expect(
        plan.toText(),
        contains('  number labels: lib/a.dart; left: lib/a.dart:1 FR-01\n'),
      );
      expect(calls.single.first, _canonical(project).path);
      expect(calls.single, containsAll(['ls-files', '-z']));
    });

    test(
      '$_fr E27: a file git does not track keeps every label, listed',
      () async {
        final project = await _labelTree(
          {},
          code: {'vendor/b.dart': '// F-01 US-01\n'},
        );

        final plan = _planWith(project);

        expect(
          plan.rewrites.map((r) => r.path),
          isNot(contains('vendor/b.dart')),
        );
        expect(
          plan.toText(),
          contains('  number labels: ; left: vendor/b.dart:1 F-01 US-01\n'),
        );
      },
    );

    test('$_fr E26: a code file with mixed line ends keeps every byte but '
        'the converted label', () async {
      final project = await _labelTree(
        {},
        code: {'lib/m.dart': '\uFEFF// A F-01 US-01\n// B F-01\r\nint a;\r\n'},
      );

      final plan = _planWith(project, _tracking({'lib/m.dart'}));

      expect(
        plan.rewrites.singleWhere((r) => r.path == 'lib/m.dart').text,
        '\uFEFF// A `a/b`\n// B `feature:a`\r\nint a;\r\n',
      );
    });

    test('$_fr E26: with two targets each code root is walked for labels, '
        'and a file under a nested target root converts once', () async {
      const techStack = '---\ncode:\n  - ./\n---\n# Tech stack\n';
      final project = await writeTree({
        '.specstone/config.yaml':
            '${_belowSince}targets:\n'
            '  outer:\n    code_root: ws\n'
            '  inner:\n    code_root: ws/inner\n'
            '  apart:\n    code_root: other\n',
        'docs/$_labelFeature': '# A\n',
        'docs/prds/features/f01_a/us01_b/USER_STORY.md': '# B\n',
        'docs/$_labelFr': '# C\n',
        'docs/specs/outer/TECH_STACK.md': techStack,
        'docs/specs/inner/TECH_STACK.md': techStack,
        'docs/specs/apart/TECH_STACK.md': techStack,
        'ws/a.dart': '// F-01 US-01\n',
        'ws/inner/b.dart': '// F-01 US-01\n',
        'other/c.dart': '// F-01 US-01\n',
      });

      final plan = _planWith(
        project,
        _tracking({'ws/a.dart', 'ws/inner/b.dart', 'other/c.dart'}),
      );

      expect(
        plan.rewrites.where((r) => r.path.endsWith('.dart')).map((r) => r.path),
        ['other/c.dart', 'ws/a.dart', 'ws/inner/b.dart'],
      );
    });

    test('$_fr E27: a code entry that leaves the code root lists no file, so '
        'none reaches git or the plan, and an in-repo file converts', () async {
      final project = await _labelTree({}, code: {'lib/a.dart': '// F-01\n'});
      final outside = Directory('${project.path}_outside')..createSync();
      addTearDown(() => outside.deleteSync(recursive: true));
      final name = outside.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      File('${outside.path}/x.dart').writeAsStringSync('// F-01 US-01\n');
      File('${project.path}/docs/$_techStackPath').writeAsStringSync(
        '---\ncode:\n  - lib/\n  - ../$name/\n---\n# Tech stack\n',
      );
      final calls = <List<String>>[];

      final plan = _planWith(project, _tracking({'lib/a.dart'}, calls));

      expect(plan.rewrites.map((r) => r.path), contains('lib/a.dart'));
      expect(plan.toText(), contains('  number labels: lib/a.dart\n'));
      expect(plan.toText(), isNot(contains('x.dart')));
      expect(calls.single.where((a) => a.startsWith('..')), isEmpty);
    });

    test("$_fr E27: with code_root .. and code ./ the project's own docs "
        'are docs, never code files left with labels', () async {
      final base = await writeTree({
        'specs/.specstone/config.yaml': '${_belowSince}code_root: ..\n',
        'specs/docs/$_labelFeature': '# A\n',
        'specs/docs/prds/features/f01_a/us01_b/USER_STORY.md': '# B\n',
        'specs/docs/$_labelFr': '# C\n',
        'specs/docs/$_techStackPath': '---\ncode:\n  - ./\n---\n# Tech stack\n',
        'specs/docs/notes/plan.md': 'See F-01 US-01.\n',
        'lib/a.dart': '// F-01\n',
      });
      final project = Directory('${base.path}/specs');

      final plan = _planWith(project);

      expect(plan.toText(), isNot(contains('../specs/docs/')));
      expect(_docText(plan, 'notes/plan.md'), contains('`a/b`'));
    });

    test('$_fr E27: a code entry that is not a relative / path lists no file '
        'and does not blank what git tracks', () async {
      final project = await _labelTree({}, code: {'lib/a.dart': '// F-01\n'});
      File('${project.path}/docs/$_techStackPath').writeAsStringSync(
        '---\ncode:\n  - lib/\n  - ..\\shared\\\n  - C:/x/\n---\n# Tech stack\n',
      );
      final calls = <List<String>>[];

      final plan = _planWith(project, _tracking({'lib/a.dart'}, calls));

      expect(plan.rewrites.map((r) => r.path), contains('lib/a.dart'));
      expect(calls.single.skip(1), ['ls-files', '-z']);
    });

    test('$_fr E26: an agent file the label pass converts gets one write '
        'that holds the conversion and the Specstone block', () async {
      final project = await _labelTree(
        {},
        code: {'AGENTS.md': 'Current work: `F-01 US-01`\n'},
      );
      File('${project.path}/docs/$_techStackPath')
          .writeAsStringSync('---\ncode:\n  - ./\n---\n# Tech stack\n');

      final plan = _planWith(project, _tracking({'AGENTS.md'}));

      expect(plan.rewrites.map((r) => r.path), isNot(contains('AGENTS.md')));
      final write = plan.agentFiles!.rootWrites.singleWhere(
        (w) => w.path == 'AGENTS.md',
      );
      expect(write.text, startsWith('Current work: `a/b`\n'));
      expect(write.text, contains('<!-- BEGIN specstone v'));
      expect(write.before, textHashOf('Current work: `F-01 US-01`\n'));
      expect(plan.toText(), contains('  number labels: AGENTS.md'));
      final steps = plan.journalSteps(base: 'HEAD', projectRoot: project);
      expect(
        steps.whereType<WriteStep>().where((s) => s.path == 'AGENTS.md'),
        hasLength(1),
      );
    });

    test('$_fr E26: a left label is cited at its line in the text the run '
        'writes, after the stamp adds its line', () async {
      final project = await _labelTree({
        'specs/topics/t.md': '---\ntraced_from: [S1]\n---\n# T\n\nSee FR-07.\n',
      });

      final plan = _planWith(project);

      final written = _stampedDocText(plan, 'specs/topics/t.md');
      final line =
          written.split('\n').indexWhere((l) => l.contains('FR-07')) + 1;
      expect(written, contains('approved: "'));
      expect(line, greaterThan(6));
      expect(plan.toText(), contains('specs/topics/t.md:$line FR-07'));
    });

    test('$_fr E26: a binary code file is skipped', () async {
      final project = await _labelTree({});
      File('${project.path}/lib/bin.dart').createSync(recursive: true);
      File('${project.path}/lib/bin.dart').writeAsBytesSync([
        0x2F,
        0x2F,
        0x20,
        0x46,
        0x2D,
        0x30,
        0x31,
        0xC3,
        0x28,
        0x0A,
      ]);

      final plan = _planWith(project, _tracking({'lib/bin.dart'}));

      expect(plan.toText(), isNot(contains('number labels:')));
      expect(plan.rewrites.map((r) => r.path), isNot(contains('lib/bin.dart')));
    });

    test(
      '$_fr E26: git is asked only when a code file holds a label',
      () async {
        final project = await _labelTree({}, code: {'lib/a.dart': 'int a;\n'});
        final calls = <List<String>>[];

        _planWith(project, _tracking({'lib/a.dart'}, calls));

        expect(calls, isEmpty);
      },
    );
  });
}

void _stampTests() {
  group('stamp pass', () {
    const frPath = 'prds/features/f01_a/us01_b/fr01_c.md';
    final matched = fingerprintOf(_lettered);

    test('$_fr E30, E31: the upgrade stamps each doc that counted as '
        'approved and each matched entry once, after the layout pass, and '
        'lists them on one stamps line', () async {
      final plan = _planAt(await _belowSinceTree(_e18Docs()));

      final text = plan.toText();
      const line = '  stamps: 6 approval hashes, 1 fingerprints\n';
      expect(text, contains(line));
      expect(text.indexOf(line), greaterThan(text.indexOf('  renumber ids: ')));
      expect(text.indexOf(line), lessThan(text.indexOf('  agent files: ')));
      final fr = _stampedDocText(plan, frPath);
      expect(fr, contains('  - S9 ${fingerprintOf(_renumbered)}\n'));
      expect(
        fr,
        matches(RegExp(r'^approved: "[0-9a-f]{12}"$', multiLine: true)),
      );
    });

    test('$_fr E30: a doc the upgrade leaves a draft is not stamped, and a '
        'tree with nothing to stamp prints no stamps line', () async {
      final plan = _planAt(
        await _belowSinceTree({
          _storyPath: '---\ndraft: true\n---\n# B\n',
          frPath: _tracingFr(matched)
              .replaceFirst('---\n', '---\ndraft: true\n'),
        }),
      );

      expect(plan.toText(), isNot(contains('stamps:')));
    });

    test('$_fr E30: no later upgrade stamps', () async {
      final plan = _plan(await _fixture(docs: const {_topicPath: _topic}));

      expect(plan.toText(), isNot(contains('stamps:')));
      expect(
        plan.rewrites.map((rewrite) => rewrite.text),
        everyElement(isNot(contains('approved: "'))),
      );
    });
  });
}

String _hashOf(RunPlan plan) => planHashOf(plan.toText(), plan.inputs);

void _planInputTests() {
  group('plan inputs', () {
    /// Plans, appends [edit] to the file at [path], and plans again; the plan
    /// text stays, so only the recorded input can move the hash.
    Future<void> expectEditMoves(
      String path,
      String edit, {
      required RunPlan Function() plan,
      String? recordedAs,
    }) async {
      final before = plan();
      expect(before.inputs.lines, contains(recordedAs ?? '$path '));

      final file = File(path);
      file.writeAsStringSync('${file.readAsStringSync()}$edit');
      final after = plan();

      expect(after.toText(), before.toText());
      expect(_hashOf(after), isNot(_hashOf(before)));
    }

    test(
      '$_fr INV-4: an edit to .specstone/config.yaml changes the hash',
      () async {
        final fixture = await _fixture();

        await expectEditMoves(
          '${fixture.project.path}/.specstone/config.yaml',
          '# edited\n',
          plan: () => _plan(fixture),
          recordedAs: '.specstone/config.yaml ',
        );
      },
    );

    test(
      '$_fr INV-4: an edit to a project-layer template changes the hash',
      () async {
        final fixture = await _fixture();

        await expectEditMoves(
          '${fixture.project.path}/$_overridePath',
          '# edited\n',
          plan: () => _plan(fixture),
          recordedAs: '$_overridePath ',
        );
      },
    );

    test("$_fr INV-4: an edit to a personal pack's home pack.yaml changes "
        'the hash', () async {
      final fixture = await _fixture();
      // A path outside the project is recorded as the code builds it, native.
      final separator = Platform.pathSeparator;
      final packFile = [
        '',
        '.specstone',
        'packs',
        'acme',
        'pack.yaml',
      ].join(separator);

      await expectEditMoves(
        '${fixture.home.path}$packFile',
        '# edited\n',
        plan: () => _plan(fixture),
        recordedAs: '$packFile ',
      );
    });

    test('$_fr INV-4: an edit to an agent file changes the hash', () async {
      final project = _canonical(
        await writeTree({
          '.specstone/config.yaml': _belowSince,
          'CLAUDE.md': '# Owner rules\n',
        }),
      );

      await expectEditMoves(
        '${project.path}/CLAUDE.md',
        'more rules\n',
        plan: () => _planAt(project),
        recordedAs: 'CLAUDE.md ',
      );
    });

    test('$_fr INV-4: an edit to a code file the label pass reads changes '
        'the hash, and its tracked answer joins as one more line', () async {
      final project = await _labelTree(
        {},
        code: {'lib/a.dart': '// See F-01 US-01\n'},
      );
      final tracked = _tracking({'lib/a.dart'});

      await expectEditMoves(
        '${project.path}/lib/a.dart',
        '// more\n',
        plan: () => _planWith(project, tracked),
        recordedAs: 'lib/a.dart ',
      );
      expect(
        _planWith(project, tracked).inputs.lines,
        contains('lib/a.dart tracked\n'),
      );
    });

    test('$_fr INV-4: a tracked file the label pass never asked about leaves '
        'the hash', () async {
      final project = await _labelTree(
        {},
        code: {'lib/a.dart': '// See F-01 US-01\n'},
      );

      final before = _planWith(project, _tracking({'lib/a.dart'}));
      final after = _planWith(
        project,
        _tracking({'lib/a.dart', 'notes.txt', 'src/b.dart'}),
      );

      expect(_hashOf(after), _hashOf(before));
      expect(after.inputs.lines, isNot(contains('notes.txt')));
    });

    test('$_fr INV-4: a labelled file git does not track enters as '
        'untracked', () async {
      final project = await _labelTree(
        {},
        code: {'lib/a.dart': '// See F-01 US-01\n'},
      );

      expect(
        _planWith(project, _tracking({})).inputs.lines,
        contains('lib/a.dart untracked\n'),
      );
    });

    test('$_fr INV-4: the plan hash starts no git', () async {
      final fixture = await _fixture();
      final calls = <List<String>>[];
      final plan = planUpgradeRun(
        fixture.project,
        templates: TemplateResolver(),
        homeDirectory: fixture.home,
        runGit: _tracking({}, calls),
      );
      calls.clear();

      _hashOf(plan);

      expect(calls, isEmpty);
    });
  });
}

const _recordPackYaml = '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - move_to_record: {doc_types: [user_story, fr], fields: [status, implements], to: implementation}
''';

const _featurePath = 'prds/features/f01_login/FEATURE.md';
const _loginStoryPath =
    'prds/features/f01_login/us01_email_login/USER_STORY.md';
const _loginFrPath =
    'prds/features/f01_login/us01_email_login/fr01_validate_credentials.md';
const _recordPath = 'specs/f01_login/IMPLEMENTATION.md';
const _overrideFile = '.specstone/templates/implementation.yaml';

const _implementedStory =
    '---\nvision:\n  - PV-01\nstatus: implemented\nimplements:\n'
    '  - app/lib/login/sign_in.dart:SignIn\n---\n# Email login\n';
const _plannedFr = '---\nstatus: planned\n---\n# Validate credentials\n';
const Map<String, String> _loginDocs = {
  _featurePath: '# Login\n',
  _loginStoryPath: _implementedStory,
  _loginFrPath: _plannedFr,
};

Future<({Directory project, Directory home})> _recordFixture({
  Map<String, String> docs = _loginDocs,
  Map<String, String> extra = const {},
  Map<String, String> packFiles = const {},
}) async => (
  home: await writeTree({
    '.specstone/packs/acme/pack.yaml': _recordPackYaml,
    '.specstone/packs/acme/implementation.yaml': recordLayer,
    ...packFiles,
  }),
  project: await writeTree({
    '.specstone/config.yaml': _config('1.0.0'),
    for (final MapEntry(:key, :value) in docs.entries) 'docs/$key': value,
    ...extra,
  }),
);

MigrateFault _refusedPlan(({Directory project, Directory home}) fixture) {
  try {
    _plan(fixture);
  } on MigrateFault catch (fault) {
    return fault;
  }
  fail('expected the plan to refuse');
}

Map<String, Object?> _valuesOf(String text) =>
    frontmatterValuesOf(Doc.parse(text));

/// [lf] stamped with the approval hash it has under the shipped packs as
/// they stood before the `move_to_record` step: the type still declared
/// `implements`, a field the hash leaves out.
String _approvedUnderShipped(String lf, String docTypeId) => withApprovalHash(
  lf,
  typeBeforeMoves(
    TemplateResolver()
        .resolveCarried(
          packNames: const ['prd-core', 'software-tech'],
          homeDirectory: null,
        )
        .lookup(docTypeId)!,
    [
      MoveToRecord(
        docTypes: [docTypeId],
        fields: const ['status', 'implements'],
        to: 'implementation',
      ),
    ],
  ),
);

/// The doc type [docTypeId] of the fixture's packs at their available versions.
MergedDocType _finalType(
  ({Directory project, Directory home}) fixture,
  String docTypeId,
) => TemplateResolver()
    .resolveCarried(
      packNames: const ['prd-core', 'software-tech', 'acme'],
      homeDirectory: fixture.home,
    )
    .lookup(docTypeId)!;

void _moveToRecordTests() {
  group('move_to_record step', () {
    test('$_fr E33: a story and an FR move their status and code paths into '
        'a new draft record, and the plan names the record', () async {
      final plan = _plan(await _recordFixture());

      final record = plan.creates.singleWhere(
        (create) => create.path == 'docs/$_recordPath',
      );
      expect(record.note, ' (draft)');
      expect(_valuesOf(record.text), {
        'draft': true,
        'statuses': [
          'email_login:implemented',
          'email_login/validate_credentials:planned',
        ],
        'implements': ['email_login:app/lib/login/sign_in.dart:SignIn'],
      });
      for (final path in [_loginStoryPath, _loginFrPath]) {
        final text = _rewriteAt(plan, 'docs/$path').text;
        expect(text, isNot(contains('status:')));
        expect(text, isNot(contains('implements:')));
      }
      expect(_rewriteAt(plan, 'docs/$_loginStoryPath').text, contains('PV-01'));
      final text = plan.toText();
      expect(
        text,
        contains(
          '  from 1.0.0: move_to_record user_story, fr status, implements '
          '-> implementation: 2 docs\n',
        ),
      );
      expect(text, contains('commit 2, creates:\n  $_recordPath (draft)\n'));
    });

    test('$_fr E33: a feature with no story value gets no record, and the '
        'step line counts no docs', () async {
      final plan = _plan(
        await _recordFixture(
          docs: {
            _featurePath: '# Login\n',
            _loginStoryPath: '---\nvision:\n  - PV-01\n---\n# Email login\n',
          },
        ),
      );

      expect(plan.creates, isEmpty);
      expect(plan.toText(), contains('-> implementation: no doc changes\n'));
    });

    test('$_fr E34: a record that holds the story with the same values keeps '
        'its entry, and the FR joins it', () async {
      final plan = _plan(
        await _recordFixture(
          docs: {
            ..._loginDocs,
            _recordPath: recordText(
              front: 'draft: true\n',
              statuses: ['email_login:implemented'],
              code: ['email_login:app/lib/login/sign_in.dart:SignIn'],
            ),
          },
        ),
      );

      expect(plan.creates, isEmpty);
      final record = _rewriteAt(plan, 'docs/$_recordPath').text;
      expect(_valuesOf(record), {
        'draft': true,
        'statuses': [
          'email_login:implemented',
          'email_login/validate_credentials:planned',
        ],
        'implements': ['email_login:app/lib/login/sign_in.dart:SignIn'],
      });
      expect(
        _rewriteAt(plan, 'docs/$_loginStoryPath').text,
        isNot(contains('status:')),
      );
    });

    test('$_fr E34: a record that holds other values for the item refuses '
        'value_unplaced, naming the doc and key', () async {
      final fault = _refusedPlan(
        await _recordFixture(
          docs: {
            ..._loginDocs,
            _recordPath: recordText(statuses: ['email_login:planned']),
          },
        ),
      );

      expect(fault.code, MigrateFaultCode.valueUnplaced);
      expect(fault.exitStatus, 65);
      expect(fault.code.wire, 'value_unplaced');
      expect(fault.file, _loginStoryPath);
      expect(fault.key, 'status');
    });

    test('$_fr E34: a record that holds other code paths for the item '
        'refuses on the code key', () async {
      final fault = _refusedPlan(
        await _recordFixture(
          docs: {
            ..._loginDocs,
            _recordPath: recordText(
              code: ['email_login:app/lib/login/other.dart'],
            ),
          },
        ),
      );

      expect(fault.code, MigrateFaultCode.valueUnplaced);
      expect(fault.file, _loginStoryPath);
      expect(fault.key, 'implements');
    });

    group('$_fr E35: a value with no place refuses before anything prints', () {
      Future<MigrateFault> refuse(Map<String, String> docs) async =>
          _refusedPlan(await _recordFixture(docs: docs));

      test('a story with no parent feature', () async {
        final fault = await refuse({_loginStoryPath: _implementedStory});

        expect(fault.code, MigrateFaultCode.valueUnplaced);
        expect(fault.file, _loginStoryPath);
        expect(fault.key, 'status');
      });

      test('a status no entry takes', () async {
        final fault = await refuse({
          ..._loginDocs,
          _loginFrPath: '---\nstatus: wip\n---\n# Validate credentials\n',
        });

        expect(fault.file, _loginFrPath);
        expect(fault.key, 'status');
        expect(fault.message, contains('wip'));
      });

      test('an implements value that is no list of code paths', () async {
        final fault = await refuse({
          ..._loginDocs,
          _loginStoryPath: '---\nimplements:\n  a: b\n---\n# Email login\n',
        });

        expect(fault.file, _loginStoryPath);
        expect(fault.key, 'implements');
      });

      test('a doc whose frontmatter is not valid YAML', () async {
        final fault = await refuse({
          ..._loginDocs,
          _loginStoryPath:
              '---\nstatus: implemented\nimplements: [a\n---\n# E\n',
        });

        expect(fault.file, _loginStoryPath);
        expect(fault.key, 'status');
      });

      test('every offending doc is listed once, in doc order', () async {
        final fault = await refuse({
          ..._loginDocs,
          _loginStoryPath: '---\nstatus: wip\nimplements: 4\n---\n# E\n',
          _loginFrPath: '---\nstatus: later\n---\n# V\n',
        });

        expect(fault.toText().split('\n'), [
          startsWith('$_loginStoryPath: status: '),
          startsWith('$_loginFrPath: status: '),
        ]);
        expect(fault.more, hasLength(1));
      });
    });

    test(
      '$_fr E36: a project architecture path in a folder of its own and '
      'no implementation path writes the record override beside it',
      () async {
        for (final arch in [
          'specs/{slug}/f{nn}_{slug}/ARCHITECTURE.md',
          'specs/{slug}/f{nn}_{slug}/ARCH.md',
        ]) {
          final plan = _plan(
            await _recordFixture(
              docs: {_featurePath: '# Login\n'},
              extra: {
                '.specstone/templates/architecture.yaml': 'path: $arch\n',
              },
            ),
          );

          final create = plan.creates.singleWhere(
            (create) => create.path == _overrideFile,
          );
          expect(
            create.text,
            'path: specs/{slug}/f{nn}_{slug}/IMPLEMENTATION.md\n',
          );
          expect(plan.toText(), contains('  $_overrideFile\n'));
        }
      },
    );

    test('$_fr E36: no override is written when the pack path already lies '
        'beside architecture, or the Owner set the record path', () async {
      final plain = _plan(await _recordFixture(docs: {_featurePath: '# L\n'}));
      expect(plain.creates, isEmpty);

      final owned = _plan(
        await _recordFixture(
          docs: {_featurePath: '# L\n'},
          extra: {
            '.specstone/templates/architecture.yaml':
                'path: specs/{slug}/f{nn}_{slug}/ARCHITECTURE.md\n',
            _overrideFile: 'path: specs/{slug}/f{nn}_{slug}/IMPL.md\n',
          },
        ),
      );
      expect(owned.creates, isEmpty);
    });

    test('$_fr E36, R-FW-1: a folder at the record override path refuses '
        'value_unplaced before any write', () async {
      final fixture = await _recordFixture(
        docs: {_featurePath: '# Login\n'},
        extra: {
          '.specstone/templates/architecture.yaml':
              'path: specs/{slug}/f{nn}_{slug}/ARCHITECTURE.md\n',
          '$_overrideFile/notes.md': '',
        },
      );

      final fault = _refusedPlan(fixture);

      expect(fault.code, MigrateFaultCode.valueUnplaced);
      expect(fault.file, _overrideFile);
    });

    test('$_fr E36: an architecture file named by the slug refuses '
        'override_dangling before any write', () async {
      final fixture = await _recordFixture(
        docs: {_featurePath: '# L\n'},
        extra: {
          '.specstone/templates/architecture.yaml':
              'path: specs/{slug}/f{nn}_{slug}.md\n',
        },
      );

      final fault = _refusedPlan(fixture);

      expect(fault.code, MigrateFaultCode.overrideDangling);
      expect(fault.file, _overrideFile);
      expect(fault.key, 'path');
    });

    test('$_fr E38: a story and an FR approved before the run take the hash '
        'of their new content, and the record stays a draft', () async {
      final fixture = await _recordFixture(
        docs: {
          _featurePath: '# Login\n',
          _loginStoryPath: _approvedUnderShipped(
            _implementedStory,
            'user_story',
          ),
          _loginFrPath: _approvedUnderShipped(_plannedFr, 'fr'),
        },
      );

      final plan = _plan(fixture);

      final story = _stampedDocText(plan, _loginStoryPath);
      final fr = _stampedDocText(plan, _loginFrPath);
      expect(
        _valuesOf(story)['approved'],
        approvalHashOf(story, _finalType(fixture, 'user_story')),
      );
      expect(
        _valuesOf(fr)['approved'],
        approvalHashOf(fr, _finalType(fixture, 'fr')),
      );
      expect(story, isNot(contains('status:')));
      final record = plan.creates.single.text;
      expect(_valuesOf(record), isNot(contains('approved')));
      expect(_valuesOf(record)['draft'], true);
      expect(
        plan.toText(),
        contains('stamps: 2 approval hashes, 0 fingerprints'),
      );
    });

    test('$_fr E38: the hash before the run counts the code field the final '
        'type no longer declares, so the doc stays approved', () async {
      final fixture = await _recordFixture(
        docs: {
          _featurePath: '# Login\n',
          _loginStoryPath: _approvedUnderShipped(
            _implementedStory,
            'user_story',
          ),
        },
      );
      expect(
        _finalType(fixture, 'user_story').fields.map((f) => f.id),
        isNot(contains('implements')),
      );

      final plan = _plan(fixture);

      final story = _stampedDocText(plan, _loginStoryPath);
      expect(
        _valuesOf(story)['approved'],
        approvalHashOf(story, _finalType(fixture, 'user_story')),
      );
    });

    test('$_fr E38: a doc whose hash did not match keeps it, and a doc with '
        'neither key gets no entry', () async {
      final stale = _implementedStory.replaceFirst(
        '---\n',
        '---\napproved: "000000000000"\n',
      );
      final plan = _plan(
        await _recordFixture(
          docs: {
            _featurePath: '# Login\n',
            _loginStoryPath: stale,
            _loginFrPath: '---\nvision: []\n---\n# Validate credentials\n',
          },
        ),
      );

      expect(
        _valuesOf(_stampedDocText(plan, _loginStoryPath))['approved'],
        '000000000000',
      );
      expect(_valuesOf(plan.creates.single.text)['statuses'], [
        'email_login:implemented',
      ]);
    });

    group('$_fr, the shipped software-tech 1.6.0 pack', () {
      Future<Directory> shippedProject({
        Map<String, String> extra = const {},
      }) => writeTree({
        '.specstone/config.yaml':
            'packs:\n  prd-core: ${shippedPackVersions()['prd-core']}\n'
            '  software-tech: 1.4.0\n',
        for (final MapEntry(:key, :value) in _loginDocs.entries)
          'docs/$key': value,
        ...extra,
      });

      test(
        'E39: the move from 1.4.0 to 1.6.0 runs no one-time pass, the '
        'move_to_record step alone beside the passes every upgrade runs',
        () async {
          final project = await shippedProject(
            extra: {'CLAUDE.md': '# Owner rules\n'},
          );

          final plan = _planAt(project);

          final text = plan.toText();
          expect(text, contains('software-tech 1.4.0 -> 1.6.0'));
          expect(
            text,
            contains(
              '  from 1.4.0: move_to_record user_story, fr status, implements '
              '-> implementation: 2 docs\n',
            ),
          );
          expect(text, isNot(contains('renumber ids:')));
          expect(text, isNot(contains('number labels:')));
          expect(text, isNot(contains('agent files:')));
          expect(plan.agentFiles!.rootWrites, isEmpty);
          expect(plan.agentFiles!.topWrites, isEmpty);
        },
      );

      test(
        'E33, S11, S13: a story and an FR move their status and code '
        'paths into a new draft record of the shipped implementation type',
        () async {
          final plan = _planAt(await shippedProject());

          final record = plan.creates.singleWhere(
            (create) => create.path == 'docs/$_recordPath',
          );
          expect(record.note, ' (draft)');
          expect(_valuesOf(record.text), {
            'draft': true,
            'statuses': [
              'email_login:implemented',
              'email_login/validate_credentials:planned',
            ],
            'implements': ['email_login:app/lib/login/sign_in.dart:SignIn'],
          });
          for (final path in [_loginStoryPath, _loginFrPath]) {
            final text = _rewriteAt(plan, 'docs/$path').text;
            expect(text, isNot(contains('status:')));
            expect(text, isNot(contains('implements:')));
          }
          expect(
            plan.toText(),
            contains('commit 2, creates:\n  $_recordPath (draft)\n'),
          );
        },
      );

      test('S11: a story approved under the 1.4.0 pack, hashed with its '
          'implements field as 1.4.0 declared it, stays approved after the '
          'move', () async {
        // The 1.4.0 `user_story` layer: `implements`, an exact output_ref.
        const layer1x4 =
            'fields:\n'
            '  - id: implements\n'
            '    type: output_ref\n'
            '    list: true\n'
            '    pointer: exact\n';
        final stamped = withApprovalHashes({
          '.specstone/config.yaml': shippedPinsConfig(['prd-core']),
          '.specstone/templates/user_story.yaml': layer1x4,
          'docs/$_loginStoryPath': _implementedStory,
        })['docs/$_loginStoryPath']!;
        final oldHash = _valuesOf(stamped)['approved']! as String;
        final project = await shippedProject(
          extra: {'docs/$_loginStoryPath': stamped},
        );

        final plan = _planAt(project);

        final story = _stampedDocText(plan, _loginStoryPath);
        final values = _valuesOf(story);
        expect(values, isNot(contains('draft')));
        expect(values['approved'], isNot(oldHash));
        expect(
          values['approved'],
          approvalHashOf(
            story,
            TemplateResolver()
                .resolveCarried(
                  packNames: const ['prd-core', 'software-tech'],
                  homeDirectory: null,
                )
                .lookup('user_story'),
          ),
        );
        expect(
          plan.toText(),
          contains('stamps: 1 approval hashes, 0 fingerprints'),
        );
      });

      test('E36: no override is written, since the shipped record path '
          'already lies in its feature folder', () async {
        final plan = _planAt(await shippedProject());

        expect(
          plan.creates.map((create) => create.path),
          isNot(contains(_overrideFile)),
        );
        expect(
          plan.rewrites.map((rewrite) => rewrite.path),
          isNot(contains(_overrideFile)),
        );
      });
    });

    test('$_fr E35: with no doc type holding record_status every value '
        'refuses', () async {
      final fault = _refusedPlan(
        await _recordFixture(
          packFiles: {
            '.specstone/packs/acme/implementation.yaml':
                'fields:\n  - {id: statuses, disabled: true}\n'
                '  - {id: implements, disabled: true}\n',
          },
        ),
      );

      expect(fault.code, MigrateFaultCode.valueUnplaced);
      expect(fault.file, _loginStoryPath);
      expect(fault.message, contains('record_status'));
      expect(fault.more, hasLength(1));
    });

    test('$_fr E35: a record whose frontmatter is not valid YAML refuses '
        'instead of losing its lines', () async {
      final fault = _refusedPlan(
        await _recordFixture(
          docs: {..._loginDocs, _recordPath: '---\nstatuses: [a\n---\n# R\n'},
        ),
      );

      expect(fault.code, MigrateFaultCode.valueUnplaced);
      expect(fault.message, contains('not valid YAML'));
    });

    test('$_fr E35: a file at the record path the run cannot read as a '
        'record refuses instead of losing the values', () async {
      final fixture = await _recordFixture();
      File('${fixture.project.path}/docs/$_recordPath')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync([0xff, 0xfe, 0x00]);

      final fault = _refusedPlan(fixture);

      expect(fault.code, MigrateFaultCode.valueUnplaced);
      expect(fault.file, _loginStoryPath);
      expect(fault.message, contains(_recordPath));
      expect(fault.more, hasLength(1));
    });

    test('$_fr E35: a record whose code block reads only beside another block '
        'refuses instead of losing its lines', () async {
      final fault = _refusedPlan(
        await _recordFixture(
          docs: {
            ..._loginDocs,
            _recordPath: "---\nanchor: &a ['x']\nimplements: *a\n---\n# R\n",
          },
        ),
      );

      expect(fault.code, MigrateFaultCode.valueUnplaced);
      expect(fault.file, _loginStoryPath);
      expect(fault.key, 'implements');
      expect(
        fault.message,
        contains('the implements block of the record of login is not valid'),
      );
    });

    test(
      '$_fr E35: a record type with no code field refuses a code path',
      () async {
        final fault = _refusedPlan(
          await _recordFixture(
            packFiles: {
              '.specstone/packs/acme/implementation.yaml':
                  'fields:\n  - {id: implements, disabled: true}\n',
            },
          ),
        );

        expect(fault.file, _loginStoryPath);
        expect(fault.key, 'implements');
      },
    );

    test('$_fr E35: the refusal lists docs in doc order, whichever pass '
        'found them', () async {
      final fault = _refusedPlan(
        await _recordFixture(
          docs: {
            ..._loginDocs,
            _recordPath: recordText(statuses: ['email_login:planned']),
            'prds/features/f02_pay/us01_card/USER_STORY.md':
                '---\nstatus: implemented\n---\n# Card\n',
          },
        ),
      );

      expect(fault.file, _loginStoryPath);
      expect(
        fault.more.single.file,
        'prds/features/f02_pay/us01_card/USER_STORY.md',
      );
    });

    test('$_fr E30: an approved record that gains entries is re-stamped, not '
        'drafted', () async {
      final probe = await _recordFixture();
      final record = withApprovalHash(
        recordText(
          statuses: ['email_login:implemented'],
          code: ['email_login:app/lib/login/sign_in.dart:SignIn'],
        ),
        _finalType(probe, 'implementation'),
      );
      final fixture = await _recordFixture(
        docs: {..._loginDocs, _recordPath: record},
      );

      final plan = _plan(fixture);

      final text = _stampedDocText(plan, _recordPath);
      expect(
        _valuesOf(text)['approved'],
        approvalHashOf(text, _finalType(fixture, 'implementation')),
      );
      expect(_valuesOf(text), isNot(contains('draft')));
      expect(_valuesOf(text)['statuses'], hasLength(2));
    });

    test(
      '$_fr E36: a record layer without path refuses on that cause',
      () async {
        final fault = _refusedPlan(
          await _recordFixture(
            docs: {_featurePath: '# L\n'},
            extra: {
              '.specstone/templates/architecture.yaml':
                  'path: specs/{slug}/f{nn}_{slug}/ARCHITECTURE.md\n',
              _overrideFile: 'description: Mine\n',
            },
          ),
        );

        expect(fault.code, MigrateFaultCode.overrideDangling);
        expect(fault.file, _overrideFile);
        expect(fault.message, contains('sets no path'));
      },
    );

    test('$_fr E39: a pack that is no one-time trigger runs no one-time '
        'pass beside the step', () async {
      final text = _plan(await _recordFixture()).toText();

      expect(text, isNot(contains('renumber ids:')));
      expect(text, isNot(contains('number labels:')));
      expect(text, isNot(contains('agent files:')));
    });
  });
}

const _tree = 'setup_migration/upgrade_pack_pins/move_spec_tree_to_target';
const _chain = 'setup_migration/upgrade_pack_pins/chain_migration_steps';

String _draftDoc(String title, [String body = '']) =>
    '---\ndraft: true\n---\n# $title\n$body';

/// A config pinning `software-tech` at 1.4.0 over the targets `flutter` and
/// `jaspr`, so the `move_to_record` step runs beside the tree move.
String _oldPinTwinConfig() =>
    'packs:\n  prd-core: ${shippedPackVersions()['prd-core']}\n'
    '  software-tech: 1.4.0\n'
    'targets:\n  flutter:\n    code_root: flutter_ws\n'
    '  jaspr:\n    code_root: jaspr_ws\n';

Future<Directory> _treeProject(
  Map<String, String> docs, {
  String? config,
  Map<String, String> extra = const {},
}) => writeTree({
  '.specstone/config.yaml': config ?? twinConfig(),
  for (final MapEntry(:key, :value) in docs.entries) 'docs/$key': value,
  ...extra,
});

MigrateFault _refusedAt(Directory project) {
  try {
    _planAt(project);
  } on MigrateFault catch (fault) {
    return fault;
  }
  fail('expected the plan to refuse');
}

void _treeMoveTests() {
  group('spec tree move', () {
    test('$_tree E01, E09: each per-target doc at a one-target path moves to '
        "the first target's folder as a pure rename, under the unchanged-pins "
        'header', () async {
      final plan = _planAt(
        await _treeProject({
          'specs/TECH_STACK.md': _draftDoc('Tech stack'),
          'specs/f02_feedback/ARCHITECTURE.md': _draftDoc('Architecture'),
          'specs/topics/doc_model.md': _draftDoc('Doc model'),
        }),
      );

      expect(plan.moves, [
        (from: 'specs/TECH_STACK.md', to: 'specs/flutter/TECH_STACK.md'),
        (
          from: 'specs/f02_feedback/ARCHITECTURE.md',
          to: 'specs/flutter/f02_feedback/ARCHITECTURE.md',
        ),
        (
          from: 'specs/topics/doc_model.md',
          to: 'specs/flutter/topics/doc_model.md',
        ),
      ]);
      expect(
        plan.toText(),
        'pack upgrade: pins unchanged, spec tree to flutter\n'
        'commit 1, moves:\n'
        '  specs/TECH_STACK.md -> specs/flutter/TECH_STACK.md\n'
        '  specs/f02_feedback/ARCHITECTURE.md -> '
        'specs/flutter/f02_feedback/ARCHITECTURE.md\n'
        '  specs/topics/doc_model.md -> specs/flutter/topics/doc_model.md\n',
      );
      expect(plan.rewrites, isEmpty);
      expect(plan.creates, isEmpty);
    });

    test('$_tree E01, setup_migration/set_up_new_project/write_agent_files '
        'E35: the run that moves the tech stack surveys its code: roots for '
        'the agent files', () async {
      final plan = _planAt(
        await _treeProject(
          {
            'specs/TECH_STACK.md':
                '---\ndraft: true\ncode:\n  - packages/sub/\n---\n'
                '# Tech stack\n',
          },
          extra: {'flutter_ws/packages/sub/.git/HEAD': 'ref\n'},
        ),
      );

      expect(plan.moves, [
        (from: 'specs/TECH_STACK.md', to: 'specs/flutter/TECH_STACK.md'),
      ]);
      expect(plan.agentFiles!.topWrites.map((write) => write.path), [
        'flutter_ws/packages/sub/AGENTS.md',
      ]);
      expect(plan.agentFiles!.addedRoots, ['flutter_ws/packages/sub']);
    });

    test('$_tree E02: a project-layer path keeps every placeholder value '
        'under the target folder', () async {
      final plan = _planAt(
        await _treeProject(
          {'specs/payments/f01_checkout/ARCHITECTURE.md': _draftDoc('A')},
          extra: {
            '.specstone/templates/architecture.yaml':
                'path: specs/{slug}/f{nn}_{slug}/ARCHITECTURE.md\n',
          },
        ),
      );

      expect(plan.moves, [
        (
          from: 'specs/payments/f01_checkout/ARCHITECTURE.md',
          to: 'specs/flutter/payments/f01_checkout/ARCHITECTURE.md',
        ),
      ]);
    });

    test('$_tree E03, E04: a link to a moved doc, a link a moved doc holds, '
        'and a path mention are rewritten; a Name and a link between moved '
        'docs keep their text; a shared doc keeps its link, pointed at the '
        'moved doc', () async {
      const movedLink = '../../../specs/flutter/f02_feedback/ARCHITECTURE.md';
      final plan = _planAt(
        await _treeProject({
          'prds/features/f02_feedback/FEATURE.md': _draftDoc(
            'Feedback',
            '\nSee [architecture](../../../specs/f02_feedback/ARCHITECTURE.md), '
                '`../../../specs/f02_feedback/ARCHITECTURE.md`, and '
                '`architecture:feedback`.\n',
          ),
          'specs/f02_feedback/ARCHITECTURE.md': _draftDoc(
            'Architecture',
            '\n[feature](../../prds/features/f02_feedback/FEATURE.md) and '
                '[topic](../topics/doc_model.md).\n',
          ),
          'specs/topics/doc_model.md': _draftDoc('Doc model'),
        }),
      );

      expect(
        _rewriteAt(plan, 'docs/prds/features/f02_feedback/FEATURE.md').text,
        _draftDoc(
          'Feedback',
          '\nSee [architecture]($movedLink), `$movedLink`, and '
              '`architecture:feedback`.\n',
        ),
      );
      expect(
        _rewriteAt(
          plan,
          'docs/specs/flutter/f02_feedback/ARCHITECTURE.md',
        ).text,
        _draftDoc(
          'Architecture',
          '\n[feature](../../../prds/features/f02_feedback/FEATURE.md) and '
              '[topic](../topics/doc_model.md).\n',
        ),
      );
      final text = plan.toText();
      expect(
        text,
        contains(
          'commit 2, rewrites:\n'
          '  prds/features/f02_feedback/FEATURE.md: 1 link, 1 mention\n'
          '  specs/flutter/f02_feedback/ARCHITECTURE.md: 1 link\n',
        ),
      );
    });

    test('$_tree E05: a doc already at a target path stays, and only the '
        'others move', () async {
      final plan = _planAt(
        await _treeProject({
          'specs/flutter/f01_login/DOMAIN.md': _draftDoc('Login'),
          'specs/f02_feedback/DOMAIN.md': _draftDoc('Feedback'),
        }),
      );

      expect(plan.moves, [
        (
          from: 'specs/f02_feedback/DOMAIN.md',
          to: 'specs/flutter/f02_feedback/DOMAIN.md',
        ),
      ]);
    });

    test('$_tree E06: a move onto a path a doc already holds refuses '
        'upgrade_collision, naming the doc', () async {
      final fault = _refusedAt(
        await _treeProject({
          'specs/TECH_STACK.md': _draftDoc('Old'),
          'specs/flutter/TECH_STACK.md': _draftDoc('Held'),
        }),
      );

      expect(fault.code, MigrateFaultCode.upgradeCollision);
      expect(fault.exitStatus, 65);
      expect(fault.file, 'specs/TECH_STACK.md');
      expect(fault.message, contains('specs/flutter/TECH_STACK.md'));
    });

    test('$_tree E07: a file no per-target doc type matches stays', () async {
      final plan = _planAt(
        await _treeProject({
          'specs/INDEX.md': _draftDoc('Index'),
          'specs/f02_feedback/DOMAIN.md': _draftDoc('Feedback'),
        }),
      );

      expect(plan.moves.map((move) => move.from), [
        'specs/f02_feedback/DOMAIN.md',
      ]);
    });

    test('$_tree E08: one target, named or not, moves no doc', () async {
      final docs = {'specs/f02_feedback/DOMAIN.md': _draftDoc('Feedback')};
      final named = await _treeProject(
        docs,
        config:
            '${shippedPinsConfig()}targets:\n  flutter:\n    code_root: ws\n',
      );
      final unnamed = await _treeProject(docs, config: oneTargetConfig());

      expect(_planAt(named).moves, isEmpty);
      expect(_planAt(unnamed).moves, isEmpty);
    });

    test('$_tree E11: a doc approved before the run takes the hash of its new '
        'content, and a draft stays a draft', () async {
      final set = TemplateResolver().resolveCarried(
        packNames: const ['prd-core', 'software-tech'],
        homeDirectory: null,
      );
      final feature = set.lookup('feature');
      final architecture = set.lookup('architecture');
      final featureText = withApprovalHash(
        '# Feedback\n\n[a](../../../specs/f02_feedback/ARCHITECTURE.md)\n',
        feature,
      );
      final archText = withApprovalHash(
        '# Architecture\n\n[f](../../prds/features/f02_feedback/FEATURE.md)\n',
        architecture,
      );
      final plan = _planAt(
        await _treeProject({
          'prds/features/f02_feedback/FEATURE.md': featureText,
          'specs/f02_feedback/ARCHITECTURE.md': archText,
          'specs/f02_feedback/DOMAIN.md': _draftDoc('Domain'),
        }),
      );

      const archPath = 'specs/flutter/f02_feedback/ARCHITECTURE.md';
      final feat = _stampedDocText(
        plan,
        'prds/features/f02_feedback/FEATURE.md',
      );
      final arch = _stampedDocText(plan, archPath);
      expect(_valuesOf(feat)['approved'], approvalHashOf(feat, feature));
      expect(_valuesOf(arch)['approved'], approvalHashOf(arch, architecture));
      expect(
        _valuesOf(arch)['approved'],
        isNot(_valuesOf(archText)['approved']),
      );
      expect(
        arch,
        contains('(../../../prds/features/f02_feedback/FEATURE.md)'),
      );
      expect(
        plan.rewrites.map((rewrite) => rewrite.path),
        isNot(contains('docs/specs/flutter/f02_feedback/DOMAIN.md')),
      );
      expect(
        plan.toText(),
        contains('stamps: 2 approval hashes, 0 fingerprints'),
      );
    });

    test('$_tree R-T26-1: a pack move_file step over a per-target type '
        "resolves under the first target's folder, and the doc's rename "
        'step and layout apply there', () async {
      const packYaml = '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - rename_section: {doc_type: runbook, from: {id: steps, header: Steps}, to: {id: procedure, header: Procedure}}
      - move_file: {doc_type: runbook, from: "prds/runbooks/{slug}/RUNBOOK.md", to: "ops/runbooks/{slug}/RUNBOOK.md"}
''';
      const type = '''
id: runbook
description: A runbook.
path: ops/runbooks/{slug}/RUNBOOK.md
per_target: true
sections:
  - {id: procedure, header: Procedure, required: true}
''';
      final home = await writeTree({
        '.specstone/packs/acme/pack.yaml': packYaml,
        '.specstone/packs/acme/runbook.yaml': type,
      });
      final project = await writeTree({
        '.specstone/config.yaml':
            '${_config('1.0.0')}targets:\n  flutter:\n    code_root: f_ws\n'
            '  jaspr:\n    code_root: j_ws\n',
        'docs/prds/runbooks/deploy/RUNBOOK.md': '# Deploy\n\n## Steps\n\nx\n',
      });

      final plan = planUpgradeRun(
        _canonical(project),
        templates: TemplateResolver(),
        homeDirectory: home,
      );

      expect(plan.moves, [
        (
          from: 'prds/runbooks/deploy/RUNBOOK.md',
          to: 'ops/flutter/runbooks/deploy/RUNBOOK.md',
        ),
      ]);
      expect(
        _rewriteAt(plan, 'docs/ops/flutter/runbooks/deploy/RUNBOOK.md').text,
        contains('## Procedure\n'),
      );
    });

    group('with a pin change', () {
      const architecturePath = 'specs/f01_login/ARCHITECTURE.md';

      Future<Directory> project({Map<String, String> extra = const {}}) =>
          _treeProject({
            ..._loginDocs,
            architecturePath: _draftDoc('Architecture'),
            ...extra,
          }, config: _oldPinTwinConfig());

      test('$_chain E11, $_fr E37: the tree move comes first, and the record '
          "a move_to_record step creates lands in the first target's folder, "
          'none in the second', () async {
        final plan = _planAt(await project());

        expect(plan.moves, [
          (
            from: architecturePath,
            to: 'specs/flutter/f01_login/ARCHITECTURE.md',
          ),
        ]);
        final record = plan.creates.singleWhere(
          (create) => create.path.endsWith('IMPLEMENTATION.md'),
        );
        expect(record.path, 'docs/specs/flutter/f01_login/IMPLEMENTATION.md');
        expect(record.note, ' (draft)');
        expect(_valuesOf(record.text)['statuses'], [
          'email_login:implemented',
          'email_login/validate_credentials:planned',
        ]);
        expect(plan.toText(), startsWith('pack upgrade: software-tech 1.4.0'));
        expect(plan.toText(), contains('commit 1, moves:\n'));
        expect(
          plan.creates.map((create) => create.path),
          isNot(contains(startsWith('docs/specs/jaspr/'))),
        );
      });

      test('$_chain E11: a record at the one-target path moves first, and the '
          'step adds its entries to it, not to a second record', () async {
        final plan = _planAt(
          await project(
            extra: {
              'specs/f01_login/IMPLEMENTATION.md': recordText(
                front: 'draft: true\n',
                statuses: ['email_login:implemented'],
                code: ['email_login:app/lib/login/sign_in.dart:SignIn'],
              ),
            },
          ),
        );

        expect(
          plan.moves.map((move) => move.to),
          contains('specs/flutter/f01_login/IMPLEMENTATION.md'),
        );
        expect(plan.creates, isEmpty);
        final record = _rewriteAt(
          plan,
          'docs/specs/flutter/f01_login/IMPLEMENTATION.md',
        ).text;
        expect(_valuesOf(record)['statuses'], [
          'email_login:implemented',
          'email_login/validate_credentials:planned',
        ]);
      });

      test('$_fr E37: a record only the second target holds does not stand '
          "in for the first target's", () async {
        final plan = _planAt(
          await project(
            extra: {
              'specs/jaspr/f01_login/IMPLEMENTATION.md': recordText(
                front: 'draft: true\n',
                statuses: ['email_login:planned'],
              ),
            },
          ),
        );

        expect(plan.creates.map((create) => create.path), [
          'docs/specs/flutter/f01_login/IMPLEMENTATION.md',
        ]);
      });
    });
  });
}
