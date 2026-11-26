// Test names stay one literal so `specstone check` finds them by exact text.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_run.dart'
    show runCheck;
import 'package:specstone_core/src/consistency_check/finding.dart'
    show FindingKind;
import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/doc_model/doc.dart' show Doc;
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/document_writing/approval.dart'
    show approvalHashOf, withApprovalHash;
import 'package:specstone_core/src/document_writing/models/path_move.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart'
    show CommitStep, CreateStep, MoveStep, WriteStep;
import 'package:specstone_core/src/document_writing/owner_confirmation.dart'
    show OwnerConfirmation;
import 'package:specstone_core/src/document_writing/stale_mentions.dart'
    show StaleMention;
import 'package:specstone_core/src/index_query/doc_index.dart' show DocIndex;
import 'package:specstone_core/src/index_query/indexed_doc.dart'
    show frontmatterValuesOf;
import 'package:specstone_core/src/index_query/read_session.dart'
    show ReadSession;
import 'package:specstone_core/src/plan_hash.dart';
import 'package:specstone_core/src/rendering/formatter.dart' show layOutDoc;
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/setup_migration/agent_files.dart'
    show agentCursorPath, agentMdText, importBlock;
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/migrate_run.dart'
    show MigrateRequest, runMigrate;
import 'package:specstone_core/src/setup_migration/run_plan.dart';
import 'package:specstone_core/src/setup_migration/upgrade_plan.dart';
import 'package:specstone_core/src/shipped_generators.dart'
    show shippedGenerators;
import 'package:specstone_core/src/templates/generator_kinds.dart'
    show shippedGeneratorKinds;
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/pack_floors.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart'
    show shippedPackVersions;
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:specstone_core/src/version.dart';
import 'package:test/test.dart';

import '../../helpers/git_repo.dart' show commitAll, git, hasGit;
import '../../helpers/legacy_fixture.dart' show commitRepo;
import '../../helpers/posix_modes.dart';
import '../../helpers/record_fixture.dart' show oneTargetConfig, twinConfig;
import '../../helpers/rulebook_fixture.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/skill_files.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart' show testHome;

/// The approval hash of [lf], the one the stamp pass hashes by.
String _approvalHashBefore(String lf, MergedDocType? type) =>
    approvalHashOf(lf, type);

/// [lf] stamped with [_approvalHashBefore].
String _stampedBefore(String lf, MergedDocType? type) =>
    withApprovalHash(lf, type);

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
  generators: shippedGenerators(),
);

/// The `id:` value of a doc-type text, or null.
String? _idOf(String type) =>
    RegExp(r'^id: (\S+)$', multiLine: true).firstMatch(type)?.group(1);

PlannedRewrite _rewriteAt(RunPlan plan, String path) =>
    plan.rewrites.singleWhere((rewrite) => rewrite.path == path);

void main() {
  _agentFilesTests();
  _keepIdsAndLabelsTests();
  _stampTests();
  _treeMoveTests();
  _planInputTests();
  _testNameTests();
  _bulletLinesTests();
  _dropSectionTests();
  _renameStampTests();
  _addedPinsTests();
  _floorPinsTests();
  _dropSharedLinesTests();
  _markRetrimTests();
  _matrixFoldTests();
  _mergeDocTests();
  _dropDocTypeTests();
  _relinkTests();
  _regenerateTests();

  test('the --dry-run --json plans of an add over twin targets and of a '
      'merge_doc step hold only the keys api:setup_migration/upgrade_packs '
      'lists', () async {
    Future<Set<String>> keysOf(
      Directory project, {
      Directory? home,
      List<String> adds = const [],
    }) async {
      final root = _canonical(project);
      commitRepo(root);
      final out = StringBuffer();
      final status = await runMigrate(
        MigrateRequest(
          workingDirectory: root,
          homeDirectory: home ?? testHome(),
          templates: TemplateResolver(),
          dryRun: true,
          asJson: true,
          confirmation: OwnerConfirmation.prompt,
          addedPacks: adds,
          readLine: () => null,
          warningLog: [],
          out: out,
          generators: shippedGenerators(),
        ),
      );
      expect(status, 0);
      return (jsonDecode(out.toString()) as Map<String, Object?>).keys.toSet();
    }

    final added = await keysOf(
      await _foldProject({
        _foldFlutterRecord: _foldRecord(_foldEdgeRows),
        _foldJasprRecord: _foldRecord(_foldEdgeRows),
        'docs/specs/skills/review.md':
            '# Review\n\n\n\n## Purpose\n\nReviews.\n',
      }, config: twinConfig()),
      adds: const ['agent-skills'],
    );
    final merge = await _mergeFixture(
      overrides: const {_mergeLayerPath: 'sections: [{id: gone}]\n'},
    );
    final merged = await keysOf(merge.project, home: merge.home);

    expect(
      {...added, ...merged},
      {
        'plan',
        'dirty',
        'warnings',
        'formatLayout',
        'agentFiles',
        'stamps',
        'steps',
        'mentions',
        'keptLayers',
        'matrixRows',
        'addedPins',
        'typedByAdd',
      },
    );
  }, skip: hasGit ? null : 'git is not available');

  test('a dry run over a project holding a layer file of a doc type a '
      'merge_doc step folds prints its plan', () async {
    final fixture = await _fixture(
      packYaml:
          'name: acme\nversion: 1.2.0\nextends: software-tech\n'
          'migrations:\n  - from: 1.0.0\n    steps:\n'
          '      - merge_doc: {from: {id: playbook, path: specs/PLAYBOOK.md}, '
          'to: runbook, sections: [{from: {id: moves, header: Moves}, '
          'to: procedure}]}\n',
      docs: const {},
      overrides: const {
        '.specstone/templates/playbook.yaml':
            'sections: [{id: gone, required: true}]\n',
      },
    );

    final plan = _plan(fixture);

    expect(plan.toText(), contains('acme'));
  });

  test('a move onto a staying doc refuses before anything '
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

  test('two docs moved onto one path refuse once, each on '
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

  group('upgrade_collision lists each doc once', () {
    /// The DocPath each line of [fault] starts with.
    List<String?> filesOf(MigrateFault fault) => [
      fault.file,
      for (final next in fault.more) next.file,
    ];

    test('three docs moved onto one path print one line '
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

    test('a doc whose section and field renames both '
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
  });

  test('two docs whose new paths differ only in letter case '
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

  test('a move onto a staying doc that differs only in '
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

  test('a chained move_file path ends at the last step, '
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
      const PathMove(
        from: 'prds/runbooks/deploy/RUNBOOK.md',
        to: 'ops/runbooks/deploy/RUNBOOK.md',
      ),
    ]);
  });

  test('a swap composes onto one path and refuses', () async {
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
  });

  test('Scenario B orders a move onto the old path of '
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

  test('a rotation through a temporary name plans '
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

  test('one refusal lists a move collision and a rename '
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

  test('an upgrade re-stamps an approved '
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
    final approved = _stampedBefore(_runbookDoc, type);
    final fixture = await _fixture(overrides: const {}, docs: {path: approved});

    final plan = _plan(fixture);

    final written = plan.rewrites.singleWhere((r) => r.path == 'docs/$path');
    expect(written.text, contains('## Procedure'));
    expect(
      RegExp(
        r'^approved: "(\w+)"$',
        multiLine: true,
      ).firstMatch(written.text)!.group(1),
      _approvalHashBefore(written.text, type),
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

  test('a link to a renamed section, of another doc or the same one, takes '
      'the new anchor', () async {
    final plan = _plan(
      await _fixture(
        docs: const {
          'prds/runbooks/deploy/RUNBOOK.md':
              '# Deploy\n\n## Steps\n\nRun it; see [s](#steps).\n',
          'prds/notes.md': '# Notes\n\n[s](runbooks/deploy/RUNBOOK.md#steps)\n',
        },
        overrides: const {},
      ),
    );

    expect(
      _rewriteAt(plan, 'docs/prds/runbooks/deploy/RUNBOOK.md').text,
      contains('Run it; see [s](#procedure).\n'),
    );
    expect(
      _rewriteAt(plan, 'docs/prds/notes.md').text,
      '# Notes\n\n[s](runbooks/deploy/RUNBOOK.md#procedure)\n',
    );
    expect(
      plan.toText(),
      contains('  prds/notes.md: links to renamed sections\n'),
    );
  });

  test('the upgrade plan', () async {
    final plan = _plan(await _fixture());

    expect(
      plan.toText(),
      'pack upgrade: acme 1.0.0 -> 1.2.0\n'
      'commit 2, rewrites:\n'
      '  from 1.0.0: rename_section runbook steps -> procedure: 2 docs\n'
      '  from 1.1.0: rename_field runbook owner -> on_call: 1 docs\n'
      '  .specstone/config.yaml: acme 1.2.0\n',
    );
    final steps = plan.lists.steps;
    expect(steps.map((line) => line.from), ['1.0.0', '1.1.0']);
    expect(steps.map((line) => line.step), [
      'rename_section runbook steps -> procedure',
      'rename_field runbook owner -> on_call',
    ]);
    expect(steps.map((line) => line.paths), [
      ['prds/runbooks/deploy/RUNBOOK.md', '.specstone/templates/runbook.yaml'],
      ['prds/runbooks/deploy/RUNBOOK.md'],
    ]);
    expect(plan.moves, isEmpty);
    expect(plan.commit1Message, 'move docs to their new pack paths');
    expect(plan.commit2Message, 'upgrade pack pins');
    expect(plan.left, isEmpty);
  });

  test('the override takes the new id and keeps every '
      'other key', () async {
    final plan = _plan(await _fixture());

    expect(
      _rewriteAt(plan, _overridePath).text,
      'sections: [{id: procedure, required: true, description: Kept.}]\n',
    );
  });

  test('an after naming the renamed id takes the new id, '
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

  test('an override field with the old id takes the new '
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
      contains('from 1.1.0: rename_field runbook owner -> on_call: 2 docs\n'),
    );
  });

  test('every step skips a doc that is not UTF-8, '
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

  test('a doc that cannot be read refuses '
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

  test('a renamed field keeps its value', () async {
    final plan = _plan(await _fixture());

    final text = _rewriteAt(plan, 'docs/prds/runbooks/deploy/RUNBOOK.md').text;
    expect(text, contains('on_call: sre\n'));
    expect(text, isNot(contains('owner')));
    expect(text, contains('## Procedure\n'));
  });

  test('two chained renames end in the last name, written '
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

  test('a doc already lacking the section is unchanged', () async {
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
      contains('rename_section runbook steps -> procedure: 0 docs\n'),
    );
  });

  test("the older release's steps print "
      'first', () async {
    final both = _plan(await _fixture()).toText();
    final newer = _plan(await _fixture(acmePin: '1.1.0', overrides: const {}))
        .toText();

    expect(both.indexOf('from 1.0.0:'), lessThan(both.indexOf('from 1.1.0:')));
    expect(newer, isNot(contains('from 1.0.0:')));
    expect(newer, contains('from 1.1.0: rename_field'));
  });

  test('a release with no step changes the pin only', () async {
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
    expect(
      _rewriteAt(plan, '.specstone/config.yaml').text,
      '${_config('1.2.0')}$_stamp',
    );
    expect(plan.moves, isEmpty);
    expect(plan.prunes, isEmpty);
  });

  test('a move_file step keeps the placeholder values and '
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
      const PathMove(
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
      'ops/runbooks/{slug}/RUNBOOK.md: 1 docs\n'
      '  prds/notes.md: 1 link, 1 mention\n'
      '  .specstone/config.yaml: acme 1.2.0\n',
    );
  });

  group('mentions line', () {
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
    const techStack = '---\ncode:\n  - lib/\n---\n# Tech stack\n';
    const docs = {
      'prds/runbooks/deploy/RUNBOOK.md': '# Deploy\n\n## Steps\n\nx\n',
      'prds/notes.md': '# Notes\n',
      'specs/TECH_STACK.md': techStack,
    };

    Future<({Directory project, Directory home})> fixtureWith(
      Map<String, String> files,
    ) => _fixture(
      packYaml: packYaml,
      runbookType: type,
      docs: docs,
      overrides: files,
    );

    test('a path '
        'mention in an agent file and one in a code file that a move stops '
        'resolving print one count line after the agent files line, and the '
        'files stay as they are', () async {
      const claude = 'Read prds/runbooks/deploy/RUNBOOK.md first.\n';
      const code = 'void f() {}\n// See prds/runbooks/deploy/RUNBOOK.md\n';
      final fixture = await fixtureWith({
        'CLAUDE.md': claude,
        'lib/a.dart': code,
      });

      final plan = _plan(fixture);

      expect(
        plan.toText(),
        endsWith('  mentions: 2\n  .specstone/config.yaml: acme 1.2.0\n'),
      );
      expect(plan.lists.mentions, [
        const StaleMention(
          path: 'CLAUDE.md',
          line: 1,
          mention: 'prds/runbooks/deploy/RUNBOOK.md',
        ),
        const StaleMention(
          path: 'lib/a.dart',
          line: 2,
          mention: 'prds/runbooks/deploy/RUNBOOK.md',
        ),
      ]);
      expect(
        File('${fixture.project.path}/CLAUDE.md').readAsStringSync(),
        claude,
      );
      expect(
        File('${fixture.project.path}/lib/a.dart').readAsStringSync(),
        code,
      );
      expect(plan.inputs.lines, contains('lib/a.dart '));
    });

    test(
      'a doc a move_file step moves still narrows the code files by its code '
      'entries',
      () async {
        const movedType = '''
id: runbook
description: A runbook.
path: ops/runbooks/{slug}/RUNBOOK.md
fields:
  - id: code
    type: string
    list: true
sections:
  - {id: steps, header: Steps, required: true}
''';
        const mention = '// See prds/runbooks/deploy/RUNBOOK.md\n';
        final fixture = await _fixture(
          packYaml: packYaml,
          runbookType: movedType,
          docs: const {
            'prds/runbooks/deploy/RUNBOOK.md':
                '---\ncode:\n  - lib/\n---\n# Deploy\n\n## Steps\n\nx\n',
          },
          overrides: const {'lib/a.dart': mention, 'src/b.dart': mention},
        );

        final plan = _plan(fixture);

        expect(plan.lists.mentions, [
          const StaleMention(
            path: 'lib/a.dart',
            line: 1,
            mention: 'prds/runbooks/deploy/RUNBOOK.md',
          ),
        ]);
      },
    );

    test('a mention '
        'of a doc no move touches prints no count line', () async {
      final fixture = await fixtureWith({
        'CLAUDE.md': 'Read prds/notes.md first.\n',
        'lib/a.dart': '// See prds/notes.md\n',
      });

      final plan = _plan(fixture);

      expect(plan.toText(), isNot(contains('mentions:')));
      expect(plan.lists.mentions, isEmpty);
    });

    test('a run '
        'with no move reads no code file and prints no count line', () async {
      final plan = _plan(
        await _fixture(
          overrides: const {
            'CLAUDE.md': 'Read prds/runbooks/deploy/RUNBOOK.md first.\n',
          },
        ),
      );

      expect(plan.moves, isEmpty);
      expect(plan.toText(), isNot(contains('mentions:')));
      expect(plan.lists.mentions, isEmpty);
    });

    test('the plan hash changes when a code file mention changes, '
        'though the printed count stays', () async {
      final first = _plan(
        await fixtureWith({
          'lib/a.dart': '// See prds/runbooks/deploy/RUNBOOK.md\n',
        }),
      );
      final second = _plan(
        await fixtureWith({
          'lib/a.dart': '// Read prds/runbooks/deploy/RUNBOOK.md\n',
        }),
      );

      expect(first.toText(), second.toText());
      expect(
        planHashOf(first.toText(), first.inputs),
        isNot(planHashOf(second.toText(), second.inputs)),
      );
    });
  });

  test('verification: '
      'no plan line joins several paths', () async {
    final plan = _planAt(await _oldPinsTree(_e18Docs()));

    final counted = RegExp(
      r'^  (format layout: \d+ docs'
      r'|stamps: \d+ approval hashes, \d+ fingerprints(; skipped: \d+)?'
      r'|agent files: \d+ files'
      r'|mentions: \d+'
      r'|from \S+: .+: \d+ docs'
      r'(; (\S+: )?\d+ entries)*)$',
    );
    final passLines = plan
        .toText()
        .split('\n')
        .where(
          (line) => RegExp(
            '^  (format layout:|stamps:'
            '|agent files:|mentions:|from )',
          ).hasMatch(line),
        );

    expect(passLines, isNotEmpty);
    for (final line in passLines) {
      expect(line, matches(counted));
    }
  });

  test('pins equal '
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
      '  format layout: 2 docs\n',
    );
    expect(plan.lists.formatLayout, ['prds/GNFR.md', 'prds/PROJECT.md']);
    expect(plan.commit2Message, 'lay docs out as format writes them');
    expect(plan.moves, isEmpty);
    expect(plan.rewrites.map((rewrite) => rewrite.path), [
      'docs/prds/GNFR.md',
      'docs/prds/PROJECT.md',
    ]);
  });

  test('a doc a step renames and a doc no step touches are each laid out once, '
      'a laid-out doc is not rewritten, a refused doc is left', () async {
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
        '  format layout: 2 docs\n'
        '  .specstone/config.yaml: acme 1.2.0\n',
      ),
    );
  });

  test('an older pin with no selected step lays out an off-layout doc '
      'beside the new pin', () async {
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
      '  format layout: 1 docs\n'
      '  .specstone/config.yaml: acme 1.2.0\n',
    );
    expect(plan.lists.formatLayout, ['prds/features/f01_a/FEATURE.md']);
    expect(plan.commit2Message, 'upgrade pack pins');
  });

  test('a rename_field step leaves a doc whose key is already absent as it '
      'is', () async {
    final plan = _plan(
      await _fixture(
        acmePin: '1.1.0',
        overrides: const {},
        docs: const {
          'prds/runbooks/deploy/RUNBOOK.md':
              '---\nteam: ops\n---\n# Deploy\n\n## Procedure\n\nRun it.\n',
        },
      ),
    );

    expect(plan.rewrites.map((rewrite) => rewrite.path), [
      '.specstone/config.yaml',
    ]);
    expect(
      plan.toText(),
      contains('from 1.1.0: rename_field runbook owner -> on_call: 0 docs\n'),
    );
  });

  test('a run with no step and an older pin puts the laid-out doc, the stale '
      'agent file, and the new pin in commit 2', () async {
    final fixture = await _fixture(
      packYaml: 'name: acme\nversion: 1.2.0\nextends: software-tech\n',
      docs: const {
        'prds/features/f01_a/FEATURE.md':
            '## Benefit hypothesis\n\ng\n\n\n## Problem\n\nn\n',
      },
      overrides: {
        '.specstone/AGENT.md': agentMdText,
        'CLAUDE.md': '# Owner rules\n\n$_staleBlock',
      },
    );

    final plan = _plan(fixture);

    expect(
      plan.toText(),
      'pack upgrade: acme 1.0.0 -> 1.2.0\n'
      'commit 2, rewrites:\n'
      '  format layout: 1 docs\n'
      '  agent files: 1 files\n'
      '  .specstone/config.yaml: acme 1.2.0\n',
    );
    expect(plan.moves, isEmpty);
    final commit2 = plan
        .journalSteps(base: 'x', projectRoot: _canonical(fixture.project))
        .whereType<CommitStep>()
        .single;
    expect(
      commit2.paths,
      containsAll([
        'docs/prds/features/f01_a/FEATURE.md',
        '.specstone/config.yaml',
        'CLAUDE.md',
      ]),
    );
  });
}

const _begin = '<!-- BEGIN specstone v$specstoneVersion -->';

/// A `CLAUDE.md` whose block imports the `.specstone/AGENT.md` it lacks.
final _importingClaude = '# Owner\n\n$_importBlock';

final String _importBlock = importBlock(
  cliVersion: specstoneVersion,
  agentMdPath: '.specstone/AGENT.md',
  projectDocPath: 'docs/prds/PROJECT.md',
  goalDocPath: 'docs/prds/GOAL.md',
  featuresDocPath: 'docs/prds/FEATURES.md',
);

/// The stamp an upgrade that writes the config leaves: the running Version.
const _stamp = 'agent_files_version: $specstoneVersion\n';

/// The text of each config rewrite of [plan].
List<String> _stampRewrites(RunPlan plan) => [
  for (final rewrite in plan.rewrites)
    if (rewrite.path == '.specstone/config.yaml') rewrite.text,
];
const _staleBlock = '$_begin\nold rules\n<!-- END specstone -->\n';

/// Pins older than the shipped versions.
const _oldPins = 'packs:\n  prd-core: 1.0.0\n  software-tech: 1.0.0\n';

Directory _canonical(Directory directory) =>
    Directory(directory.resolveSymbolicLinksSync());

RunPlan _planAt(Directory project) => planUpgradeRun(
  _canonical(project),
  templates: TemplateResolver(),
  homeDirectory: null,
  generators: shippedGenerators(),
);

void _agentFilesTests() {
  group('agent files step', () {
    test('a pin moving from its floor to a later version over a root whose '
        'CLAUDE.md block the Owner deleted writes no block and no Cursor '
        'rules file', () async {
      final project = await writeTree({
        '.specstone/config.yaml': _oldPins,
        'CLAUDE.md': '# Owner rules\n',
      });

      final plan = _planAt(project);

      final writes = plan.agentFiles?.rootWrites ?? const [];
      expect(writes.map((write) => write.path), isNot(contains('CLAUDE.md')));
      expect(
        writes.map((write) => write.path),
        isNot(contains('.cursor/rules/specstone.mdc')),
      );
      expect(plan.lists.agentFiles, isEmpty);
    });

    test('a pin moving from the 1.8.0 and 1.6.0 floor to a later version '
        'leaves an opted-out group unwritten and prints no cites line, its '
        'JSON object holding no cites key', () async {
      final project = await writeTree({
        '.specstone/config.yaml': _oldPins,
        'CLAUDE.md': '# Owner rules\n',
      });

      final plan = _planAt(project);

      expect(plan.agentFiles?.isEmpty ?? true, isTrue);
      expect(plan.lists.agentFiles, isEmpty);
      expect(plan.toText(), isNot(contains('cites:')));
      expect(plan.lists.toJson(), isNot(contains('cites')));
    });

    test('a pin moving up gives a listed top no skill '
        'write', () async {
      final project = await writeTree({
        '.specstone/config.yaml':
            '$_oldPins'
            'code_root: code\nagent_file_roots:\n  - code\n',
        'code/.git/HEAD': 'ref: refs/heads/main\n',
      });

      final plan = _planAt(project);

      expect(plan.agentFiles, isNotNull);
      expect(plan.agentFiles!.topWrites, isEmpty);
      expect(plan.lists.agentFiles, isEmpty);
    });

    test('pins equal and one hand-edited skill file is the '
        'agent-only upgrade, one file counted', () async {
      final texts = skillFileTexts();
      final path = texts.keys.first;
      final project = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
        ...texts,
        path: '${texts[path]}hand edit\n',
      });

      final plan = _planAt(project);

      expect(
        plan.toText(),
        'pack upgrade: pins unchanged, agent files only\n'
        'commit 2, rewrites:\n'
        '  agent files: 1 files\n',
      );
      expect(plan.lists.agentFiles, [path]);
      expect(plan.agentFiles!.rootWrites.single.isNew, isFalse);
      expect(_stampRewrites(plan), ['${shippedPinsConfig()}$_stamp']);
    });

    test('pins equal and only the Claude Code settings file missing is the '
        'agent-only upgrade, one file counted', () async {
      final texts = skillFileTexts();
      final project = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
        for (final MapEntry(:key, :value) in texts.entries)
          if (key != settingsFilePath) key: value,
      });

      final plan = _planAt(project);

      expect(
        plan.toText(),
        'pack upgrade: pins unchanged, agent files only\n'
        'commit 2, rewrites:\n'
        '  agent files: 1 files\n',
      );
      expect(plan.lists.agentFiles, [settingsFilePath]);
      expect(plan.agentFiles!.rootWrites.single.isNew, isTrue);
      expect(plan.agentFiles!.rootWrites.single.text, settingsFileText);
    });

    test('pins equal and a settings file with another Specstone handler is '
        'merged by one write, never trashed', () async {
      final texts = skillFileTexts();
      final project = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
        ...texts,
        settingsFilePath:
            '{"hooks":{"SessionStart":[{"hooks":[{"type":"command",'
            '"command":"specstone","args":["hook","session-start"]}]}]}}',
      });

      final plan = _planAt(project);

      expect(plan.lists.agentFiles, [settingsFilePath]);
      expect(plan.agentFiles!.trash, isEmpty);
      expect(plan.agentFiles!.rootWrites.single.isNew, isFalse);
      expect(
        plan.agentFiles!.rootWrites.single.text,
        isNot(contains('session-start')),
      );
    });

    test(
      'pins equal and a current settings file is no agent-only upgrade',
      () async {
        final project = await writeTree({
          '.specstone/config.yaml': shippedPinsConfig(),
          ...skillFileTexts(),
        });

        expect(_planAt(project).agentFiles?.isEmpty ?? true, isTrue);
      },
    );

    test('a group opted out leaves a stale settings file unread', () async {
      final project = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
        '.claude/skills/own-skill/SKILL.md': 'own\n',
        settingsFilePath: '{',
      });

      expect(_planAt(project).agentFiles?.isEmpty ?? true, isTrue);
    });

    for (final (name, stale) in [
      ('missing', null),
      (
        'with an old Specstone matcher',
        '{"hooks":{"PreToolUse":[{"matcher":"Bash|PowerShell","hooks":'
            '[{"type":"command","command":"specstone hook pre-shell"}]}]}}',
      ),
    ]) {
      test('pins equal and only the Codex hooks file $name is the '
          'agent-only upgrade, one file counted', () async {
        final project = await writeTree({
          '.specstone/config.yaml': shippedPinsConfig(),
          for (final MapEntry(:key, :value) in skillFileTexts().entries)
            if (key != codexHooksFilePath) key: value,
          codexHooksFilePath: ?stale,
        });

        final plan = _planAt(project);

        expect(
          plan.toText(),
          'pack upgrade: pins unchanged, agent files only\n'
          'commit 2, rewrites:\n'
          '  agent files: 1 files\n',
        );
        expect(plan.lists.agentFiles, [codexHooksFilePath]);
        expect(plan.agentFiles!.rootWrites.single.isNew, stale == null);
        expect(plan.agentFiles!.rootWrites.single.text, codexHooksFileText);
      });
    }

    test('a Codex hooks file handler the binary does not write is removed by '
        'the merge, every other entry kept, never trashed', () async {
      final project = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
        ...skillFileTexts(),
        codexHooksFilePath:
            '{"hooks":{"SessionStart":[{"hooks":[{"type":"command",'
            '"command":"specstone","args":["hook","session-start"]}]}],'
            '"Stop":[{"hooks":[{"type":"command","command":"own-tool"}]}]}}',
      });

      final plan = _planAt(project);

      final text = plan.agentFiles!.rootWrites.single.text;
      expect(plan.lists.agentFiles, [codexHooksFilePath]);
      expect(plan.agentFiles!.trash, isEmpty);
      expect(text, isNot(contains('session-start')));
      expect(text, contains('own-tool'));
      expect(text, contains('specstone hook pre-shell'));
    });

    test('a Codex group opted out leaves a stale Codex hooks file unread and '
        'starts no run', () async {
      final project = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
        '.codex/agents/own-agent.toml': 'own\n',
        codexHooksFilePath: '{',
      });

      expect(_planAt(project).agentFiles?.isEmpty ?? true, isTrue);
    });

    test('a malformed settings file refuses agent_block_malformed naming '
        'it, at planning, before any write', () async {
      final project = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
        ...skillFileTexts(),
        settingsFilePath: '{"hooks": []}',
      });

      expect(
        () => _planAt(project),
        throwsA(
          isA<MigrateFault>()
              .having(
                (f) => f.code,
                'code',
                MigrateFaultCode.agentBlockMalformed,
              )
              .having((f) => f.file, 'file', settingsFilePath),
        ),
      );
    });

    test('a settings file that does not parse refuses agent_block_malformed '
        'naming it', () async {
      final project = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
        ...skillFileTexts(),
        settingsFilePath: '{',
      });

      expect(
        () => _planAt(project),
        throwsA(
          isA<MigrateFault>()
              .having(
                (f) => f.code,
                'code',
                MigrateFaultCode.agentBlockMalformed,
              )
              .having((f) => f.file, 'file', settingsFilePath),
        ),
      );
    });

    test('an agent_file_roots entry outside the project root is never '
        'written, whatever the pins', () async {
      final outer = _canonical(
        await writeTree({
          'proj/.specstone/config.yaml':
              '${_oldPins}agent_file_roots:\n  - ../other\n',
          'other/.git/HEAD': 'ref: refs/heads/main\n',
        }),
      );
      final project = Directory('${outer.path}/proj');

      final plan = _planAt(project);

      expect(plan.agentFiles!.topWrites, isEmpty);
      expect(plan.agentFiles!.addedRoots, isEmpty);
      expect(
        plan.lists.agentFiles,
        isNot(contains(anyOf(startsWith('..'), contains('other')))),
      );
      final steps = plan.journalSteps(base: 'x', projectRoot: project);
      expect(
        steps.whereType<CreateStep>().map((step) => step.path),
        isNot(contains(contains('other'))),
      );
      expect(
        _rewriteAt(plan, '.specstone/config.yaml').text,
        contains('agent_file_roots:\n  - ../other\n'),
      );
    });

    test('a settings file at a listed top is a top write, outside the root '
        'files', () async {
      final project = await writeTree({
        '.specstone/config.yaml':
            '${shippedPinsConfig()}code_root: code\nagent_file_roots:\n'
            '  - code\n',
        ...skillFileTexts(),
        ...skillFileTexts('code/'),
        'code/.git/HEAD': 'ref: refs/heads/main\n',
        'code/$settingsFilePath': '{}\n',
      });

      final plan = _planAt(project);

      final agents = plan.agentFiles!;
      expect(agents.rootWrites, isEmpty);
      expect(agents.topWrites.map((write) => write.path), [
        'code/$settingsFilePath',
      ]);
      expect(agents.topWrites.single.isAtTop, isTrue);
    });

    test('an entry the binary ships missing from a group in use is '
        'written, the other groups left alone', () async {
      final texts = skillFileTexts();
      final missing = texts.keys.first;
      final project = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
        for (final MapEntry(:key, :value) in texts.entries)
          if (key != missing) key: value,
      });

      final plan = _planAt(project);

      expect(plan.lists.agentFiles, [missing]);
      expect(plan.agentFiles!.rootWrites.single.isNew, isTrue);
    });

    test('a group none of whose folders holds a specstone entry '
        'starts no run', () async {
      final project = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
        '.claude/skills/own-skill/SKILL.md': 'own\n',
      });

      final plan = _planAt(project);

      expect(plan.agentFiles!.isEmpty, isTrue);
      expect(plan.toText(), isNot(contains('agent files:')));
      expect(plan.lists.agentFiles, isEmpty);
    });

    test('an unshipped entry is counted and listed under '
        'agentFiles, the one at a top named apart', () async {
      final project = await writeTree({
        '.specstone/config.yaml':
            '${shippedPinsConfig()}code_root: code\nagent_file_roots:\n'
            '  - code\n',
        'code/.git/HEAD': 'ref: refs/heads/main\n',
        ...skillFileTexts(),
        ...skillFileTexts('code/'),
        '.claude/skills/specstone-old/SKILL.md': 'old\n',
        'code/.claude/skills/specstone-old/SKILL.md': 'old\n',
      });

      final plan = _planAt(project);

      final trash = [
        '.claude/skills/specstone-old',
        'code/.claude/skills/specstone-old',
      ];
      expect(plan.agentFiles!.trash, trash);
      expect(plan.agentFiles!.topTrash, ['code/.claude/skills/specstone-old']);
      final files = [for (final path in trash) '$path/SKILL.md'];
      expect(plan.lists.agentFiles, files);
      expect(plan.toText(), contains('  agent files: 2 files\n'));
      expect(plan.lists.toJson()['agentFiles'], files);
    });

    test('a later upgrade never adds a deleted block or the rules '
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
        generators: shippedGenerators(),
      );

      expect(plan.agentFiles!.isEmpty, isTrue);
      expect(plan.toText(), isNot(contains('agent files:')));
    });

    test('the agent files line prints after the steps and '
        'before the pins', () async {
      final fixture = await _fixture(docs: const {}, overrides: const {});
      final projectPath = fixture.project.path;
      Directory('$projectPath/code/.git').createSync(recursive: true);
      File('$projectPath/.specstone/config.yaml')
          .writeAsStringSync('${_config('1.0.0')}code_root: code\n');

      final plan = _plan(fixture);

      final text = plan.toText();
      final stepAt = text.indexOf('from 1.1.0: rename_field');
      final agentsAt = text.indexOf('agent files: ${1 + skillFileCount} files');
      final pinAt = text.indexOf('.specstone/config.yaml: acme 1.2.0');
      expect(stepAt, greaterThan(0), reason: 'the steps print');
      expect(agentsAt, greaterThan(stepAt), reason: 'agent files after steps');
      expect(pinAt, greaterThan(agentsAt), reason: 'pins after agent files');
    });

    test('every pin equal and a stale block gives the agent-only '
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
        '  agent files: 1 files\n',
      );
      expect(plan.lists.agentFiles, ['CLAUDE.md']);
      expect(plan.commit2Message, 'refresh the Specstone agent files');
      expect(_stampRewrites(plan), ['${shippedPinsConfig()}$_stamp']);
      expect(plan.moves, isEmpty);
    });

    test('every pin equal, a doc off its layout, and a stale '
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
        '  format layout: 1 docs\n'
        '  agent files: 1 files\n',
      );
      expect(
        plan.commit2Message,
        'lay docs out and refresh the Specstone agent files',
      );
      expect(plan.rewrites.map((rewrite) => rewrite.path), [
        'docs/prds/GNFR.md',
        '.specstone/config.yaml',
      ]);
    });

    test('a repository top unlisted in agent_file_roots takes its '
        'files outside the commits and joins the config', () async {
      final project = await writeTree({
        '.specstone/config.yaml': '${shippedPinsConfig()}code_root: code\n',
        'code/.git/HEAD': 'ref: refs/heads/main\n',
      });

      final plan = _planAt(project);

      final agents = plan.agentFiles!;
      expect(agents.topWrites.map((write) => write.path), [
        'code/AGENTS.md',
        ...skillPaths('code/'),
      ]);
      expect(agents.addedRoots, ['code']);
      expect(
        plan.toText(),
        contains('  agent files: ${1 + skillFileCount} files\n'),
      );
      expect(plan.lists.agentFiles, ['code/AGENTS.md', ...skillPaths('code/')]);
      expect(
        _rewriteAt(plan, '.specstone/config.yaml').text,
        '${shippedPinsConfig()}code_root: code\nagent_file_roots:\n'
        '  - code\n$_stamp',
      );
      expect(_rewriteAt(plan, '.specstone/config.yaml').changes, [
        'agent_file_roots',
        'agent_files_version',
      ]);
    });

    test('a bare agent_file_roots key rewrites to a valid list', () async {
      final project = await writeTree({
        '.specstone/config.yaml':
            '${shippedPinsConfig()}code_root: code\nagent_file_roots:\n',
        'code/.git/HEAD': 'ref: refs/heads/main\n',
      });

      final plan = _planAt(project);

      expect(
        _rewriteAt(plan, '.specstone/config.yaml').text,
        '${shippedPinsConfig()}code_root: code\n'
        'agent_file_roots:\n  - code\n$_stamp',
      );
    });

    test('a replaced agent_file_roots drops an end-of-line comment', () async {
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
        'agent_file_roots:\n  - other\n  - code\n$_stamp',
      );
    });

    test('the config rewrite replaces a listed agent_file_roots '
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

    test('a pin-moving upgrade replaces a lower stamp in place and '
        'keeps every other key', () async {
      final project = await writeTree({
        '.specstone/config.yaml':
            '${_oldPins}code_root: code\nagent_files_version: 1.0.0\n',
        'code/lib/a.dart': 'class A {}\n',
      });

      final plan = _planAt(project);

      final rewrite = _rewriteAt(plan, '.specstone/config.yaml');
      expect(rewrite.text, contains('code_root: code\n$_stamp'));
      expect('agent_files_version'.allMatches(rewrite.text), hasLength(1));
      expect(rewrite.changes, ['pins', 'agent_files_version']);
    });

    test('a layout-only upgrade writes no config and leaves the '
        'stamp as it is', () async {
      final project = await writeTree({
        '.specstone/config.yaml':
            '${shippedPinsConfig()}agent_files_version: 1.0.0\n',
        ...skillFileTexts(),
        'docs/prds/GNFR.md': '## Reliability\n\nr\n\n## Performance\n\np\n',
      });

      final plan = _planAt(project);

      expect(plan.rewrites.map((rewrite) => rewrite.path), [
        'docs/prds/GNFR.md',
      ]);
    });

    test('an agent-only upgrade whose stamp already holds the running '
        'Version rewrites no config', () async {
      final texts = skillFileTexts();
      final path = texts.keys.first;
      final project = await writeTree({
        '.specstone/config.yaml': '${shippedPinsConfig()}$_stamp',
        ...texts,
        path: '${texts[path]}edit\n',
      });

      final plan = _planAt(project);

      expect(plan.lists.agentFiles, [path]);
      expect(_stampRewrites(plan), isEmpty);
    });

    test('an agent-only upgrade that writes the missing AGENT.md an import '
        'block names sets the stamp', () async {
      final project = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
        ...skillFileTexts(),
        'CLAUDE.md': _importingClaude,
      });

      final plan = _planAt(project);

      expect(plan.lists.agentFiles, ['.specstone/AGENT.md']);
      expect(_stampRewrites(plan), ['${shippedPinsConfig()}$_stamp']);
    });

    test('a stamp above the running Version stays as it is', () async {
      final project = await writeTree({
        '.specstone/config.yaml': '${_oldPins}agent_files_version: 9.0.0\n',
      });

      final text = _stampRewrites(_planAt(project)).single;

      expect(text, endsWith('agent_files_version: 9.0.0\n'));
    });

    test('a refused AGENT.md write leaves the stamp as it was', () async {
      final project = await writeTree({
        '.specstone/config.yaml': '${_oldPins}agent_files_version: 1.0.0\n',
        'CLAUDE.md': _importingClaude,
      });
      final outside = await writeTree({'outside/keep': 'x\n'});
      Link('${project.path}/.specstone/AGENT.md')
          .createSync('${outside.path}/outside/AGENT.md');

      final plan = _planAt(project);

      expect(plan.lists.agentFiles, isNot(contains('.specstone/AGENT.md')));
      expect(
        _stampRewrites(plan).single,
        endsWith('agent_files_version: 1.0.0\n'),
      );
    });

    test('an AGENT.md of other bytes is rewritten in place, and a changed '
        'stale block body moves the plan hash', () async {
      final project = _canonical(
        await writeTree({
          '.specstone/config.yaml': shippedPinsConfig(),
          ...skillFileTexts(),
          '.specstone/AGENT.md': '${agentMdText}other bytes\n',
          'CLAUDE.md': '# Owner rules\n\n$_staleBlock',
        }),
      );

      final before = _planAt(project);
      File('${project.path}/CLAUDE.md').writeAsStringSync(
        '# Owner rules\n\n$_begin\nolder rules\n<!-- END specstone -->\n',
      );
      final after = _planAt(project);

      final agentMd = before.agentFiles!.rootWrites.first;
      expect(agentMd.path, '.specstone/AGENT.md');
      expect(agentMd.text, agentMdText);
      expect(agentMd.isNew, isFalse);
      expect(before.lists.agentFiles, ['.specstone/AGENT.md', 'CLAUDE.md']);
      expect(before.toText(), contains('  agent files: 2 files\n'));
      expect(after.toText(), before.toText());
      expect(_hashOf(after), isNot(_hashOf(before)));
    });

    test('a stale block at a listed top is rewritten in that work tree, '
        'outside both commits', () async {
      final project = _canonical(
        await writeTree({
          '.specstone/config.yaml':
              '${shippedPinsConfig()}code_root: code\nagent_file_roots:\n'
              '  - code\n',
          ...skillFileTexts(),
          ...skillFileTexts('code/'),
          'code/.git/HEAD': 'ref: refs/heads/main\n',
          'code/AGENTS.md': '# Top rules\n\n$_staleBlock',
        }),
      );

      final plan = _planAt(project);

      final agents = plan.agentFiles!;
      expect(agents.rootWrites, isEmpty);
      expect(agents.topWrites.map((write) => write.path), ['code/AGENTS.md']);
      expect(agents.topWrites.single.isAtTop, isTrue);
      expect(
        agents.topWrites.single.text,
        startsWith('# Top rules\n\n$_begin'),
      );
      final steps = plan.journalSteps(base: 'x', projectRoot: project);
      expect(
        steps.whereType<CommitStep>().last.paths,
        isNot(contains('code/AGENTS.md')),
      );
      expect(
        steps.whereType<WriteStep>().map((step) => step.path),
        contains(endsWith('code/AGENTS.md')),
      );
    });

    test('a block whose BEGIN line names an older version is not rewritten '
        'by an upgrade plan', () async {
      final olderBlock = _importBlock.replaceFirst(
        _begin,
        '<!-- BEGIN specstone v0.0.1 -->',
      );
      final project = await writeTree({
        '.specstone/config.yaml': _oldPins,
        '.specstone/AGENT.md': agentMdText,
        'CLAUDE.md': '# Owner rules\n\n$olderBlock',
      });

      final plan = _planAt(project);

      expect(plan.agentFiles?.rootWrites ?? const [], isEmpty);
      expect(plan.lists.agentFiles, isNot(contains('CLAUDE.md')));
    });

    test('a later upgrade leaves a deleted rules file deleted while it '
        'rewrites a stale block beside it', () async {
      final project = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
        ...skillFileTexts(),
        '.specstone/AGENT.md': agentMdText,
        'AGENTS.md': '# Owner rules\n\n$_staleBlock',
        '.cursor/rules/own.mdc': 'own rule\n',
      });

      final plan = _planAt(project);

      expect(plan.agentFiles!.rootWrites.map((write) => write.path), [
        'AGENTS.md',
      ]);
      expect(plan.lists.agentFiles, isNot(contains(agentCursorPath)));
    });

    test('an import block with a missing AGENT.md has '
        'commit 2 write it', () async {
      final project = await writeTree({
        '.specstone/config.yaml': _oldPins,
        'CLAUDE.md': _importingClaude,
      });

      final plan = _planAt(project);

      expect(plan.agentFiles!.rootWrites.map((write) => write.path), [
        '.specstone/AGENT.md',
      ]);
      final commit2 = plan
          .journalSteps(base: 'x', projectRoot: _canonical(project))
          .whereType<CommitStep>()
          .last;
      expect(commit2.paths, contains('.specstone/AGENT.md'));
      expect(commit2.paths, isNot(contains('CLAUDE.md')));
    });

    test('an unlisted top alone with every pin equal gives the agent-only '
        'plan', () async {
      final project = await writeTree({
        '.specstone/config.yaml': '${shippedPinsConfig()}code_root: code\n',
        ...skillFileTexts(),
        'code/.git/HEAD': 'ref: refs/heads/main\n',
      });

      final plan = _planAt(project);

      expect(
        plan.toText(),
        'pack upgrade: pins unchanged, agent files only\n'
        'commit 2, rewrites:\n'
        '  agent files: ${1 + skillFileCount} files\n',
      );
      expect(plan.agentFiles!.rootWrites, isEmpty);
      expect(plan.agentFiles!.addedRoots, ['code']);
      expect(plan.moves, isEmpty);
    });

    test('a root with an AGENT.md of other bytes, an import block of a '
        'missing AGENT.md, or an unlisted top plans the agent files '
        'step alone', () async {
      final roots = {
        'other bytes': {'.specstone/AGENT.md': '${agentMdText}other bytes\n'},
        'missing AGENT.md': {'CLAUDE.md': _importingClaude},
        'unlisted top': {'code/.git/HEAD': 'ref: refs/heads/main\n'},
      };
      for (final MapEntry(:key, :value) in roots.entries) {
        final project = await writeTree({
          '.specstone/config.yaml':
              '${shippedPinsConfig()}'
              '${key == 'unlisted top' ? 'code_root: code\n' : ''}',
          ...skillFileTexts(),
          ...value,
        });

        final plan = _planAt(project);

        final count = key == 'unlisted top' ? 1 + skillFileCount : 1;
        expect(
          plan.toText(),
          'pack upgrade: pins unchanged, agent files only\n'
          'commit 2, rewrites:\n'
          '  agent files: $count files\n',
          reason: key,
        );
        expect(plan.moves, isEmpty, reason: key);
      }
    });

    test('a malformed block refuses before the plan returns', () async {
      final project = await writeTree({
        '.specstone/config.yaml': _oldPins,
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
    });
  });
}

const _storyPath = 'prds/features/f01_a/us01_b/USER_STORY.md';
const _topicPath = 'specs/topics/doc_model.md';
const _lettered = '### Scenario 6a — [edge] lettered\n- **Given** g\n';

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

### Scenario 2 — [error] two

- **Given** g

$_lettered''';

String _tracingFr(String fingerprint, {String body = ''}) =>
    '---\ntraced_from:\n  - S6a\nconfirmed:\n  - S6a $fingerprint\n---\n'
    '# C\n$body';

/// The E18 tree under `docs/`: the charter and story with lettered IDs, two
/// FRs tracing Scenario 6a, one matched and one suspect, and an architecture
/// doc citing the charter by path.
Map<String, String> _e18Docs({String topic = _topic}) => {
  _topicPath: topic,
  'specs/topics/other_topic.md':
      '# Other topic\n\n## Rules\n\n- **RULE-1** — One.\n',
  _storyPath: _story,
  'prds/features/f01_a/us01_b/fr01_c.md': _tracingFr(
    fingerprintOf(_lettered),
    body:
        '\n## Statement\n\n'
        '`charter:doc_model` RULE-7a\n`charter:other_topic` RULE-7a\n',
  ),
  'prds/features/f01_a/us01_b/fr02_g.md': _tracingFr('000000000000'),
  'specs/f01_a/ARCHITECTURE.md':
      '# A\n\n## Components\n\n[rules](../topics/doc_model.md) RULE-7a\n'
      '`../topics/doc_model.md` RULE-7a\n',
};

/// The project at [_oldPins] holding [docs], with the charter layer that
/// types its `specs/topics/` docs.
Future<Directory> _oldPinsTree(Map<String, String> docs) => writeTree({
  '.specstone/config.yaml': _oldPins,
  charterLayerFile: charterLayer,
  for (final MapEntry(:key, :value) in docs.entries) 'docs/$key': value,
});

/// The text of [docPath] the plan writes, else the text it leaves on disk in
/// [project].
String _docText(RunPlan plan, Directory project, String docPath) {
  final path = 'docs/$docPath';
  final rewrites = plan.rewrites.where((rewrite) => rewrite.path == path);
  return _withoutStamp(
    rewrites.isEmpty
        ? File('${project.path}/$path').readAsStringSync()
        : rewrites.single.text,
  );
}

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

void _keepIdsAndLabelsTests() {
  group('lettered IDs and number labels', () {
    test('an upgrade from below the floor prints no renumber or label line, '
        'holds no numberLabels or renumberIds key, and leaves the IDs and '
        'labels as written', () async {
      final project = await writeTree({
        '.specstone/config.yaml': _oldPins,
        charterLayerFile: charterLayer,
        for (final MapEntry(:key, :value) in _e18Docs().entries)
          'docs/$key': value,
        'docs/$_labelFeature': '# A\n',
        'docs/specs/topics/labelled.md':
            '# Labelled\n\n## Rules\n\nSee F-01 US-01 FR-01 and FR-09.\n',
      });

      final plan = _planAt(project);

      final text = plan.toText();
      expect(text, isNot(contains('renumber ids')));
      expect(text, isNot(contains('number labels')));
      final json = plan.lists.toJson();
      expect(json, isNot(contains('numberLabels')));
      expect(json, isNot(contains('renumberIds')));
      expect(
        _docText(plan, project, _topicPath),
        contains('- **RULE-7a** — Lettered.\n'),
      );
      expect(_docText(plan, project, _storyPath), contains('### Scenario 6a'));
      expect(
        _docText(plan, project, 'specs/topics/labelled.md'),
        contains('See F-01 US-01 FR-01 and FR-09.\n'),
      );
    });
  });
}

const _labelFeature = 'prds/features/f01_a/FEATURE.md';
const _labelFr = 'prds/features/f01_a/us01_b/fr01_c.md';
const _techStackPath = 'specs/TECH_STACK.md';

RunPlan _planWith(Directory project) => planUpgradeRun(
  _canonical(project),
  templates: TemplateResolver(),
  homeDirectory: null,
  generators: shippedGenerators(),
);

Future<Directory> _labelTree(
  Map<String, String> docs, {
  Map<String, String> code = const {},
  String pins = _oldPins,
}) => writeTree({
  '.specstone/config.yaml': pins,
  charterLayerFile: charterLayer,
  'docs/$_labelFeature': '# A\n',
  'docs/prds/features/f01_a/us01_b/USER_STORY.md': '# B\n',
  'docs/$_labelFr': '# C\n',
  'docs/$_techStackPath':
      '---\ncode:\n  - lib/\n  - vendor/\n---\n# Tech stack\n',
  for (final MapEntry(:key, :value) in docs.entries) 'docs/$key': value,
  ...code,
});

void _stampTests() {
  group('stamp pass', () {
    const frPath = 'prds/features/f01_a/us01_b/fr01_c.md';
    final matched = fingerprintOf(_lettered);

    test('a doc the upgrade leaves a draft is not stamped, and a '
        'tree with nothing to stamp prints no stamps line', () async {
      final plan = _planAt(
        await _oldPinsTree({
          _storyPath: '---\ndraft: true\n---\n# B\n',
          frPath: _tracingFr(matched)
              .replaceFirst('---\n', '---\ndraft: true\n'),
        }),
      );

      expect(plan.toText(), isNot(contains('stamps:')));
    });

    test('a doc left unstamped for its frontmatter is counted after '
        'skipped and listed in code point order', () async {
      final plan = _planAt(
        await _oldPinsTree({
          _storyPath: '---\ndraft: true\n: bad: [\n---\n# B\n',
          frPath: '---\ndraft: true\n: bad: [\n---\n# C\n',
        }),
      );

      expect(
        plan.toText(),
        contains('  stamps: 0 approval hashes, 0 fingerprints; skipped: 2\n'),
      );
      expect(plan.lists.stampsSkipped, [_storyPath, frPath]);
    });

    test('no later upgrade stamps', () async {
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

    test('an edit to .specstone/config.yaml changes the hash', () async {
      final fixture = await _fixture();

      await expectEditMoves(
        '${fixture.project.path}/.specstone/config.yaml',
        '# edited\n',
        plan: () => _plan(fixture),
        recordedAs: '.specstone/config.yaml ',
      );
    });

    test('an edit to a project-layer template changes the hash', () async {
      final fixture = await _fixture();

      await expectEditMoves(
        '${fixture.project.path}/$_overridePath',
        '# edited\n',
        plan: () => _plan(fixture),
        recordedAs: '$_overridePath ',
      );
    });

    test("an edit to a personal pack's home pack.yaml changes "
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

    test('an edit to an agent file changes the hash', () async {
      final project = _canonical(
        await writeTree({
          '.specstone/config.yaml': _oldPins,
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

    test('a labelled file under the code roots is never read, so an edit to '
        'it leaves the plan and the hash as they were', () async {
      final project = await _labelTree(
        {},
        code: {'lib/a.dart': '// See F-01 US-01\n'},
      );
      final before = _planWith(project);

      File('${project.path}/lib/a.dart')
          .writeAsStringSync('// F-01\n// more\n');
      final after = _planWith(project);

      expect(after.rewrites.map((r) => r.path), isNot(contains('lib/a.dart')));
      expect(after.inputs.lines, isNot(contains('lib/a.dart')));
      expect(after.toText(), isNot(contains('lib/a.dart')));
      expect(_hashOf(after), _hashOf(before));
    });
  });
}

Map<String, Object?> _valuesOf(String text) =>
    frontmatterValuesOf(Doc.parse(text));

String _draftDoc(String title, [String body = '']) =>
    '---\ndraft: true\n---\n# $title\n$body';

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
    test('each per-target doc at a one-target path moves to '
        "the first target's folder as a pure rename, under the unchanged-pins "
        'header', () async {
      final plan = _planAt(
        await _treeProject({
          'specs/TECH_STACK.md': _draftDoc('Tech stack'),
          'specs/f02_feedback/ARCHITECTURE.md': _draftDoc('Architecture'),
          'specs/f02_feedback/SECURITY.md': _draftDoc('Security'),
        }),
      );

      expect(plan.moves, [
        const PathMove(
          from: 'specs/TECH_STACK.md',
          to: 'specs/flutter/TECH_STACK.md',
        ),
        const PathMove(
          from: 'specs/f02_feedback/ARCHITECTURE.md',
          to: 'specs/flutter/f02_feedback/ARCHITECTURE.md',
        ),
        const PathMove(
          from: 'specs/f02_feedback/SECURITY.md',
          to: 'specs/flutter/f02_feedback/SECURITY.md',
        ),
      ]);
      expect(
        plan.toText(),
        'pack upgrade: pins unchanged, spec tree to flutter\n'
        'commit 1, moves:\n'
        '  specs/TECH_STACK.md -> specs/flutter/TECH_STACK.md\n'
        '  specs/f02_feedback/ARCHITECTURE.md -> '
        'specs/flutter/f02_feedback/ARCHITECTURE.md\n'
        '  specs/f02_feedback/SECURITY.md -> '
        'specs/flutter/f02_feedback/SECURITY.md\n',
      );
      expect(plan.rewrites, isEmpty);
      expect(plan.creates, isEmpty);
    });

    test('the run that moves the tech stack surveys its code: roots for '
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
        const PathMove(
          from: 'specs/TECH_STACK.md',
          to: 'specs/flutter/TECH_STACK.md',
        ),
      ]);
      expect(plan.agentFiles!.topWrites.map((write) => write.path), [
        'flutter_ws/packages/sub/AGENTS.md',
        ...skillPaths('flutter_ws/packages/sub/'),
      ]);
      expect(plan.agentFiles!.addedRoots, ['flutter_ws/packages/sub']);
    });

    test('a project-layer path keeps every placeholder value '
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
        const PathMove(
          from: 'specs/payments/f01_checkout/ARCHITECTURE.md',
          to: 'specs/flutter/payments/f01_checkout/ARCHITECTURE.md',
        ),
      ]);
    });

    test('a link to a moved doc, a link a moved doc holds, '
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
                '[security](SECURITY.md).\n',
          ),
          'specs/f02_feedback/SECURITY.md': _draftDoc('Security'),
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
              '[security](SECURITY.md).\n',
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

    test('a doc already at a target path stays, and only the '
        'others move', () async {
      final plan = _planAt(
        await _treeProject({
          'specs/flutter/f01_login/SECURITY.md': _draftDoc('Login'),
          'specs/f02_feedback/SECURITY.md': _draftDoc('Feedback'),
        }),
      );

      expect(plan.moves, [
        const PathMove(
          from: 'specs/f02_feedback/SECURITY.md',
          to: 'specs/flutter/f02_feedback/SECURITY.md',
        ),
      ]);
    });

    test('a move onto a path a doc already holds refuses '
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

    test('a file no per-target doc type matches stays', () async {
      final plan = _planAt(
        await _treeProject({
          'specs/INDEX.md': _draftDoc('Index'),
          'specs/f02_feedback/SECURITY.md': _draftDoc('Feedback'),
        }),
      );

      expect(plan.moves.map((move) => move.from), [
        'specs/f02_feedback/SECURITY.md',
      ]);
    });

    test('a spec file no per-target doc type matches stays through the run, '
        'and check lists it', () async {
      final root = _canonical(
        await writeTree({
          '.specstone/config.yaml': twinConfig(),
          'docs/specs/INDEX.md': _draftDoc('Index'),
          'docs/specs/f02_feedback/SECURITY.md': _draftDoc('Feedback'),
        }),
      );
      commitRepo(root);
      var asked = 0;

      final status = await runMigrate(
        MigrateRequest(
          workingDirectory: root,
          homeDirectory: testHome(),
          templates: TemplateResolver(),
          dryRun: false,
          confirmation: OwnerConfirmation.prompt,
          readLine: () => asked++ == 0 ? 'y' : null,
          out: StringBuffer(),
          generators: shippedGenerators(),
        ),
      );

      expect(status, 0);
      expect(File('${root.path}/docs/specs/INDEX.md').existsSync(), isTrue);
      expect(
        File('${root.path}/docs/specs/flutter/f02_feedback/SECURITY.md')
            .existsSync(),
        isTrue,
      );
      final untyped = await ReadSession.runAsync(
        (session) async => [
          for (final finding in (await runCheck(session)).findings)
            if (finding.kind == FindingKind.untypedDoc) finding.path,
        ],
        templates: TemplateResolver(),
        workingDirectory: root,
        homeDirectory: testHome(),
      );
      expect(untyped, contains('specs/INDEX.md'));
    }, skip: hasGit ? null : 'git is not available');

    test('one target, named or not, moves no doc', () async {
      final docs = {'specs/f02_feedback/SECURITY.md': _draftDoc('Feedback')};
      final named = await _treeProject(
        docs,
        config:
            '${shippedPinsConfig()}targets:\n  flutter:\n    code_root: ws\n',
      );
      final unnamed = await _treeProject(docs, config: oneTargetConfig());

      expect(_planAt(named).moves, isEmpty);
      expect(_planAt(unnamed).moves, isEmpty);
    });

    test('a doc approved before the run takes the hash of its new '
        'content, and a draft stays a draft', () async {
      final set = TemplateResolver().resolveCarried(
        packNames: const ['prd-core', 'software-tech'],
        homeDirectory: null,
      );
      final feature = set.lookup('feature');
      final architecture = set.lookup('architecture');
      final featureText = _stampedBefore(
        '# Feedback\n\n[a](../../../specs/f02_feedback/ARCHITECTURE.md)\n',
        feature,
      );
      final archText = _stampedBefore(
        '# Architecture\n\n[f](../../prds/features/f02_feedback/FEATURE.md)\n',
        architecture,
      );
      final plan = _planAt(
        await _treeProject({
          'prds/features/f02_feedback/FEATURE.md': featureText,
          'specs/f02_feedback/ARCHITECTURE.md': archText,
          'specs/f02_feedback/SECURITY.md': _draftDoc('Security'),
        }),
      );

      const archPath = 'specs/flutter/f02_feedback/ARCHITECTURE.md';
      final feat = _stampedDocText(
        plan,
        'prds/features/f02_feedback/FEATURE.md',
      );
      final arch = _stampedDocText(plan, archPath);
      expect(_valuesOf(feat)['approved'], _approvalHashBefore(feat, feature));
      expect(
        _valuesOf(arch)['approved'],
        _approvalHashBefore(arch, architecture),
      );
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
        isNot(contains('docs/specs/flutter/f02_feedback/SECURITY.md')),
      );
      expect(
        plan.toText(),
        contains('stamps: 2 approval hashes, 0 fingerprints'),
      );
    });

    test('a pack move_file step over a per-target type '
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
        generators: shippedGenerators(),
      );

      expect(plan.moves, [
        const PathMove(
          from: 'prds/runbooks/deploy/RUNBOOK.md',
          to: 'ops/flutter/runbooks/deploy/RUNBOOK.md',
        ),
      ]);
      expect(
        _rewriteAt(plan, 'docs/ops/flutter/runbooks/deploy/RUNBOOK.md').text,
        contains('## Procedure\n'),
      );
    });
  });
}

// MARK: - Test names

const _testFile = 'app/test/auth_test.dart';

String _testSource(String name) =>
    "void main() {\n  test('$name', () {});\n}\n";

const _featurePath = 'prds/features/f01_login/FEATURE.md';
const _loginStoryPath =
    'prds/features/f01_login/us01_email_login/USER_STORY.md';
const _loginFrPath =
    'prds/features/f01_login/us01_email_login/fr01_validate_credentials.md';

const Map<String, String> _plainLoginDocs = {
  _featurePath: '# Login\n',
  _loginStoryPath: '# Email login\n',
  _loginFrPath: '# Validate credentials\n',
};

/// A committed git project: [docs] under `docs/` and [files] beside them.
Future<Directory> _testNameProject({
  String pins = _oldPins,
  Map<String, String> docs = _plainLoginDocs,
  Map<String, String> files = const {},
}) async {
  final project = await writeTree({
    '.specstone/config.yaml': '${pins}code_root: app\n',
    charterLayerFile: charterLayer,
    for (final MapEntry(:key, :value) in docs.entries) 'docs/$key': value,
    ...files,
  });
  final root = _canonical(project);
  expect(git(root, ['init', '-q']).exitCode, 0);
  commitAll(root, 'base');
  return root;
}

RunPlan _planTestNames(Directory project) => planUpgradeRun(
  project,
  templates: TemplateResolver(),
  homeDirectory: null,
  generators: shippedGenerators(),
);

void _testNameTests() {
  group('test names', () {
    test('an upgrade from a software-tech pin at the floor over test names '
        'holding item IDs prints no tests line, holds no tests key, and '
        'reads no test file', () async {
      final project = await _testNameProject(
        files: {_testFile: _testSource('f01/us01/fr01 rejects a wrong key')},
      );

      final plan = _planTestNames(project);

      expect(plan.toText(), isNot(contains('tests:')));
      expect(plan.lists.toJson(), isNot(contains('tests')));
      expect(plan.inputs.lines, isNot(contains('$_testFile ')));
      expect(plan.creates, isEmpty);
    });
  });
}

const _bulletPackYaml = '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - bullet_lines: {doc_type: runbook, section: goals, prefixes: ["**Serves:**", "**By:**"]}
''';

const _bulletType = '''
id: runbook
description: A runbook.
path: prds/runbooks/{slug}/RUNBOOK.md
sections:
  - {id: goals, header: Goals}
  - {id: notes, header: Notes}
''';

const _bulletDocPath = 'prds/runbooks/deploy/RUNBOOK.md';
const _bulletDoc =
    '# Deploy\n\n## Goals\n\n**Serves:** PV-01\n- **By:** v1\n\n'
    '## Notes\n\n**Serves:** kept\n';
const _bulletedDoc =
    '# Deploy\n\n## Goals\n\n- **Serves:** PV-01\n- **By:** v1\n\n'
    '## Notes\n\n**Serves:** kept\n';

List<String> _docRewrites(RunPlan plan) => [
  for (final rewrite in plan.rewrites)
    if (rewrite.path.startsWith('docs/')) rewrite.path,
];

Future<({Directory project, Directory home})> _bulletFixture({
  String doc = _bulletDoc,
  String packYaml = _bulletPackYaml,
  Map<String, String> overrides = const {},
}) => _fixture(
  packYaml: packYaml,
  runbookType: _bulletType,
  docs: {_bulletDocPath: doc},
  overrides: overrides,
);

void _bulletLinesTests() {
  group('bullet_lines step', () {
    test(
      'commit 2 bullets the listed lines of the section and '
      'the step line counts the rewritten docs, listed under steps',
      () async {
        final plan = _plan(await _bulletFixture());

        expect(_rewriteAt(plan, 'docs/$_bulletDocPath').text, _bulletedDoc);
        expect(
          plan.toText(),
          contains(
            'commit 2, rewrites:\n'
            '  from 1.0.0: bullet_lines runbook goals: 1 docs\n',
          ),
        );
        expect(plan.lists.toJson()['steps'], [
          {
            'from': '1.0.0',
            'step': 'bullet_lines runbook goals',
            'paths': [_bulletDocPath],
          },
        ]);
      },
    );

    test('a doc with no line to bullet is not rewritten and the '
        'step line counts no docs', () async {
      final plan = _plan(await _bulletFixture(doc: _bulletedDoc));

      expect(_docRewrites(plan), isEmpty);
      expect(
        plan.toText(),
        contains('  from 1.0.0: bullet_lines runbook goals: 0 docs\n'),
      );
    });

    test('a project that disables the section plans the step at '
        'no docs and rewrites none', () async {
      final plan = _plan(
        await _bulletFixture(
          overrides: const {
            _overridePath: 'sections: [{id: goals, disabled: true}]\n',
          },
        ),
      );

      expect(_docRewrites(plan), isEmpty);
      expect(
        plan.toText(),
        contains('  from 1.0.0: bullet_lines runbook goals: 0 docs\n'),
      );
    });

    test('a doc that awaits approval keeps its approval fields '
        'and stays a draft', () async {
      const draft = '---\ndraft: true\n---\n$_bulletDoc';

      final plan = _plan(await _bulletFixture(doc: draft));

      expect(
        _rewriteAt(plan, 'docs/$_bulletDocPath').text,
        '---\ndraft: true\n---\n$_bulletedDoc',
      );
      expect(plan.toText(), isNot(contains('stamps:')));
    });

    test('an approved doc gets the approval hash of its new '
        'content', () async {
      final seed = await _bulletFixture();
      final set = TemplateResolver().resolveCarried(
        packNames: ProjectConfig.read(seed.project).pins.keys,
        homeDirectory: seed.home,
      );
      final type = switch (DocTypeMatcher(
        set,
        targetNames: const [],
      ).match(_bulletDocPath)) {
        MatchedDocType(:final docType) => docType,
        _ => null,
      };
      final approved = _stampedBefore(_bulletDoc, type);

      final plan = _plan(await _bulletFixture(doc: approved));

      final written = _rewriteAt(plan, 'docs/$_bulletDocPath').text;
      expect(written, contains('- **Serves:** PV-01\n'));
      final hash = RegExp(
        r'^approved: "(\w+)"$',
        multiLine: true,
      ).firstMatch(written)!.group(1);
      expect(hash, _approvalHashBefore(written, type));
      expect(hash, isNot(_approvalHashBefore(approved, type)));
      expect(
        plan.toText(),
        contains('  stamps: 1 approval hashes, 0 fingerprints\n'),
      );
    });

    test('a step the pack load refuses throws unknown_value and '
        'plans nothing', () async {
      final fixture = await _bulletFixture(
        packYaml: _bulletPackYaml.replaceFirst(
          'section: goals',
          'section: nope',
        ),
      );

      expect(
        () => _plan(fixture),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.unknownValue)
              .having(
                (f) => f.key,
                'key',
                'migrations[0].steps[0].bullet_lines.section',
              ),
        ),
      );
    });
  });
}

const _dropSectionPackYaml = '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - drop_section: {doc_types: [runbook], section: {id: questions, header: Open questions}}
''';

const _dropType = '''
id: runbook
description: A runbook.
path: prds/runbooks/{slug}/RUNBOOK.md
sections:
  - {id: goals, header: Goals}
''';

/// The runbook type with a section after the one the step drops.
const _dropMiddleType = '''
id: runbook
description: A runbook.
path: prds/runbooks/{slug}/RUNBOOK.md
sections:
  - {id: goals, header: Goals}
  - {id: risks, header: Risks}
''';

/// [_dropMiddleType] as it stood before the drop, the section in its slot.
const _dropMiddleTypeBefore = '''
id: runbook
description: A runbook.
path: prds/runbooks/{slug}/RUNBOOK.md
sections:
  - {id: goals, header: Goals}
  - {id: questions, header: Open questions}
  - {id: risks, header: Risks}
''';

/// A pack with no migration, to resolve a doc type as an older pin had it.
const _stepFreePackYaml = '''
name: acme
version: 1.0.0
extends: software-tech
''';

const _dropDocPath = 'prds/runbooks/deploy/RUNBOOK.md';
const _dropOtherDocPath = 'prds/runbooks/build/RUNBOOK.md';
const _dropBareDocPath = 'prds/runbooks/clean/RUNBOOK.md';
const _dropDoc =
    '# Deploy\n\n## Goals\n\nShip it.\n\n## Open questions\n\nWho?\n';
const _droppedDoc = '# Deploy\n\n## Goals\n\nShip it.\n';
const _dropBareDoc = '# Clean\n\n## Goals\n\nSweep.\n';

/// The merged runbook type at [_dropDocPath] of the acme [packYaml] with
/// [runbookType], and no project layer.
Future<MergedDocType> _runbookTypeOf({
  required String packYaml,
  required String runbookType,
}) async {
  final fixture = await _fixture(
    packYaml: packYaml,
    runbookType: runbookType,
    docs: const {},
    overrides: const {},
  );
  final set = TemplateResolver().resolveCarried(
    packNames: ProjectConfig.read(fixture.project).pins.keys,
    homeDirectory: fixture.home,
  );
  return switch (DocTypeMatcher(
    set,
    targetNames: const [],
  ).match(_dropDocPath)) {
    MatchedDocType(:final docType) => docType,
    final match => throw StateError('$_dropDocPath matched $match'),
  };
}

/// The `approved:` value of [lf].
String? _approvedValueOf(String lf) =>
    RegExp(r'^approved: "(\w+)"$', multiLine: true).firstMatch(lf)?.group(1);

void _dropSectionTests() {
  group('drop_section step', () {
    test('a drop_section step rewrites each doc whose merged type lacks the '
        'id and counts it', () async {
      final plan = _plan(
        await _fixture(
          packYaml: _dropSectionPackYaml,
          runbookType: _dropType,
          docs: {
            _dropDocPath: _dropDoc,
            _dropOtherDocPath: _dropDoc.replaceFirst('Deploy', 'Build'),
            _dropBareDocPath: _dropBareDoc,
          },
          overrides: const {},
        ),
      );

      expect(_rewriteAt(plan, 'docs/$_dropDocPath').text, _droppedDoc);
      expect(
        _rewriteAt(plan, 'docs/$_dropOtherDocPath').text,
        _droppedDoc.replaceFirst('Deploy', 'Build'),
      );
      expect(_docRewrites(plan), hasLength(2));
      expect(
        plan.toText(),
        contains(
          'commit 2, rewrites:\n'
          '  from 1.0.0: drop_section runbook questions: 2 docs\n',
        ),
      );
      expect(plan.lists.toJson()['steps'], [
        {
          'from': '1.0.0',
          'step': 'drop_section runbook questions',
          'paths': [_dropOtherDocPath, _dropDocPath],
        },
      ]);
    });

    test('a link to the dropped anchor of another doc loses the anchor, and '
        'one of the same doc unwraps to its text', () async {
      const linker =
          '# Notes\n\n'
          '[a](runbooks/deploy/RUNBOOK.md#open-questions) '
          '[b](runbooks/deploy/RUNBOOK.md#goals) '
          '[c][q] `[d](runbooks/deploy/RUNBOOK.md#open-questions)`\n\n'
          '[q]: runbooks/deploy/RUNBOOK.md#open-questions\n';
      final plan = _plan(
        await _fixture(
          packYaml: _dropSectionPackYaml,
          runbookType: _dropType,
          docs: {
            _dropDocPath: _dropDoc.replaceFirst(
              'Ship it.',
              'Ship it; see [the questions](#open-questions), '
                  '[them](RUNBOOK.md#open-questions), and [goals](#goals).',
            ),
            'prds/notes.md': linker,
          },
          overrides: const {},
        ),
      );

      expect(
        _rewriteAt(plan, 'docs/$_dropDocPath').text,
        _droppedDoc.replaceFirst(
          'Ship it.',
          'Ship it; see the questions, them, and [goals](#goals).',
        ),
      );
      expect(
        _rewriteAt(plan, 'docs/prds/notes.md').text,
        '# Notes\n\n'
        '[a](runbooks/deploy/RUNBOOK.md) '
        '[b](runbooks/deploy/RUNBOOK.md#goals) '
        '[c][q] `[d](runbooks/deploy/RUNBOOK.md#open-questions)`\n\n'
        '[q]: runbooks/deploy/RUNBOOK.md\n',
      );
      expect(
        plan.toText(),
        contains('  prds/notes.md: links to dropped sections\n'),
      );
    });

    const dupDoc =
        '# Deploy\n\n## Open questions\n\n### Dup\n\nA\n\n'
        '## Goals\n\n### Dup\n\nB\n';
    for (final (what, deployDoc, links, followed) in [
      (
        'a dropped heading and a kept one its drop renumbers',
        dupDoc,
        '[d](runbooks/deploy/RUNBOOK.md#dup) '
            '[k](runbooks/deploy/RUNBOOK.md#dup-1)',
        '[d](runbooks/deploy/RUNBOOK.md) [k](runbooks/deploy/RUNBOOK.md#dup)',
      ),
      (
        'an html id in the dropped section',
        _dropDoc.replaceFirst('Who?', '<a id="legacy"></a>\n\nWho?'),
        '[l](runbooks/deploy/RUNBOOK.md#legacy)',
        '[l](runbooks/deploy/RUNBOOK.md)',
      ),
      (
        'a dropped anchor after a query',
        _dropDoc,
        '[q](runbooks/deploy/RUNBOOK.md?v=1#open-questions)',
        '[q](runbooks/deploy/RUNBOOK.md?v=1)',
      ),
      (
        'a dropped anchor through a dot segment',
        _dropDoc,
        '[d](runbooks/deploy/./RUNBOOK.md#open-questions)',
        '[d](runbooks/deploy/./RUNBOOK.md)',
      ),
    ]) {
      test('a link to $what follows the drop', () async {
        final plan = _plan(
          await _fixture(
            packYaml: _dropSectionPackYaml,
            runbookType: _dropType,
            docs: {
              _dropDocPath: deployDoc,
              'prds/notes.md': '# Notes\n\n$links\n',
            },
            overrides: const {},
          ),
        );

        expect(
          _rewriteAt(plan, 'docs/prds/notes.md').text,
          '# Notes\n\n$followed\n',
        );
      });
    }

    for (final (layer, section) in [
      ('the section whole', '{id: questions, header: Open questions}'),
      ('the header under another id', '{id: notes, header: Open questions}'),
    ]) {
      test('a project layer writing $layer keeps it and counts '
          'nothing', () async {
        final plan = _plan(
          await _fixture(
            packYaml: _dropSectionPackYaml,
            runbookType: _dropType,
            docs: const {_dropDocPath: _dropDoc},
            overrides: {_overridePath: 'sections: [$section]\n'},
          ),
        );

        expect(_docRewrites(plan), isEmpty);
        expect(
          plan.toText(),
          contains('  from 1.0.0: drop_section runbook questions: 0 docs\n'),
        );
      });
    }

    test('a doc that awaits approval keeps its approval fields and stays a '
        'draft', () async {
      const draft = '---\ndraft: true\n---\n$_dropDoc';

      final plan = _plan(
        await _fixture(
          packYaml: _dropSectionPackYaml,
          runbookType: _dropType,
          docs: const {_dropDocPath: draft},
          overrides: const {},
        ),
      );

      expect(
        _rewriteAt(plan, 'docs/$_dropDocPath').text,
        '---\ndraft: true\n---\n$_droppedDoc',
      );
      expect(plan.toText(), isNot(contains('stamps:')));
    });

    // Each doc is off its layout, so only the type it was approved under
    // hashes it.
    for (final (drift, drifted) in [
      (
        '',
        '# Deploy\n\n## Goals\n\n\n\nShip it.\n\n'
            '## Open questions\n\nWho?\n\n## Risks\n\nNone.\n',
      ),
      (
        ', the section out of type order,',
        '# Deploy\n\n## Goals\n\nShip it.\n\n## Risks\n\nNone.\n\n'
            '## Open questions\n\nWho?\n',
      ),
    ]) {
      test('an approved doc$drift the step rewrites is restamped', () async {
        final before = await _runbookTypeOf(
          packYaml: _stepFreePackYaml,
          runbookType: _dropMiddleTypeBefore,
        );
        final after = await _runbookTypeOf(
          packYaml: _dropSectionPackYaml,
          runbookType: _dropMiddleType,
        );
        expect(layOutDoc(drifted, before), isNot(drifted));
        final approved = _stampedBefore(drifted, before);

        final plan = _plan(
          await _fixture(
            packYaml: _dropSectionPackYaml,
            runbookType: _dropMiddleType,
            docs: {_dropDocPath: approved},
            overrides: const {},
          ),
        );

        final written = _rewriteAt(plan, 'docs/$_dropDocPath').text;
        expect(written, isNot(contains('## Open questions')));
        expect(_approvedValueOf(written), _approvalHashBefore(written, after));
        expect(
          plan.toText(),
          contains('  stamps: 1 approval hashes, 0 fingerprints\n'),
        );
      });
    }
  });
}

/// The runbook type of [_runbookPackYaml]'s last version, with a second field.
const _renamedType = '''
id: runbook
description: A runbook.
path: prds/runbooks/{slug}/RUNBOOK.md
fields:
  - {id: on_call, type: string}
  - {id: team, type: string}
sections:
  - {id: procedure, header: Procedure, required: true}
''';

void _renameStampTests() {
  group('rename steps on an approved doc', () {
    /// Stamps [drifted] under [beforeType], plans the upgrade from
    /// [acmePin], and returns the doc the plan writes.
    Future<_StampedRewrite> stampedRewrite({
      required String acmePin,
      required String beforeType,
      required String drifted,
    }) async {
      final before = await _runbookTypeOf(
        packYaml: _stepFreePackYaml,
        runbookType: beforeType,
      );
      expect(layOutDoc(drifted, before), isNot(drifted));
      final plan = _plan(
        await _fixture(
          acmePin: acmePin,
          runbookType: _renamedType,
          docs: {_dropDocPath: _stampedBefore(drifted, before)},
          overrides: const {},
        ),
      );
      return _StampedRewrite(
        plan: plan,
        written: _rewriteAt(plan, 'docs/$_dropDocPath').text,
        after: await _runbookTypeOf(
          packYaml: _runbookPackYaml,
          runbookType: _renamedType,
        ),
      );
    }

    test('a rename_section step restamps a doc approved off its '
        'layout', () async {
      final result = await stampedRewrite(
        acmePin: '1.0.0',
        beforeType: _renamedType
            .replaceFirst('on_call', 'owner')
            .replaceFirst(
              '{id: procedure, header: Procedure',
              '{id: steps, header: Steps',
            ),
        drifted: '---\nowner: sre\n---\n# Deploy\n\n## Steps\n\n\n\nRun it.\n',
      );

      expect(result.written, contains('## Procedure\n'));
      expect(
        _approvedValueOf(result.written),
        _approvalHashBefore(result.written, result.after),
      );
      expect(
        result.plan.toText(),
        contains('  stamps: 1 approval hashes, 0 fingerprints\n'),
      );
    });

    test('a rename_field step restamps a doc approved with its keys out of '
        'field order', () async {
      final result = await stampedRewrite(
        acmePin: '1.1.0',
        beforeType: _renamedType.replaceFirst('on_call', 'owner'),
        drifted:
            '---\nteam: ops\nowner: sre\n---\n# Deploy\n\n## Procedure\n\n'
            'Run it.\n',
      );

      expect(result.written, contains('on_call: sre\n'));
      expect(
        _approvedValueOf(result.written),
        _approvalHashBefore(result.written, result.after),
      );
      expect(
        result.plan.toText(),
        contains('  stamps: 1 approval hashes, 0 fingerprints\n'),
      );
    });
  });
}

/// A plan and the doc text it writes, with the doc's type after the steps.
final class _StampedRewrite {
  const new({required this.plan, required this.written, required this.after});

  final RunPlan plan;
  final String written;
  final MergedDocType after;
}

const _configPath = '.specstone/config.yaml';

/// Plans the upgrade of [project] with [adds] as the added packs.
RunPlan _planAdding(Directory project, List<String> adds) => planUpgradeRun(
  _canonical(project),
  templates: TemplateResolver(),
  homeDirectory: null,
  addedPacks: adds,
  generators: shippedGenerators(),
);

/// The `config.yaml` text [plan] writes, less the `agent_files_version` line
/// every run that writes the config sets.
String _configWrittenBy(RunPlan plan) => _rewriteAt(
  plan,
  _configPath,
).text.replaceAll(RegExp(r'agent_files_version: [^\r\n]*\r?\n'), '');

PackVersion _version(String text) =>
    PackVersion.parse(text, file: _configPath, key: 'packs');

void _floorPinsTests() {
  test('a project pinned at every shipped floor upgrades to the carried '
      'versions with the prd-core regenerate step and the two spec-scope '
      'mark_retrim steps', () async {
    String pins(Map<String, Object> versions) => [
      'packs:\n',
      for (final pack in PackFloors.shipped.byPack.keys)
        '  $pack: ${versions[pack]}\n',
    ].join();
    final project = await writeTree({
      _configPath: pins(PackFloors.shipped.byPack),
    });

    final plan = planUpgradeRun(
      project,
      templates: TemplateResolver(),
      homeDirectory: null,
      generators: shippedGenerators(),
    );

    expect(plan.lists.toJson()['steps'], [
      {
        'from': '1.31.0',
        'step': 'regenerate: feature_catalog, group_feature_catalog',
        'paths': <String>[],
      },
      {'from': '1.5.0', 'step': 'mark_retrim', 'paths': <String>[]},
      {'from': '1.26.0', 'step': 'mark_retrim', 'paths': <String>[]},
    ]);
    expect(plan.moves, isEmpty);
    expect(_configWrittenBy(plan), pins(shippedPackVersions()));
  });
}

void _addedPinsTests() {
  group('added pins', () {
    final versions = shippedPackVersions();
    final core = versions['prd-core']!;
    final tech = versions['software-tech']!;
    final skills = versions['agent-skills']!;
    final marketing = versions['marketing']!;

    Future<Directory> project(String config) =>
        writeTree({_configPath: config});

    test('an added pin prints its line before upgraded pins', () async {
      final fixture = await _fixture();

      final plan = planUpgradeRun(
        fixture.project,
        templates: TemplateResolver(),
        homeDirectory: fixture.home,
        addedPacks: const ['agent-skills'],
        generators: shippedGenerators(),
      );

      expect(
        plan.toText(),
        contains(
          '  $_configPath: agent-skills $skills (added)\n'
          '  $_configPath: acme 1.2.0\n',
        ),
      );
    });

    test('the header names added pins before upgraded ones and never says '
        'pins unchanged', () async {
      final fixture = await _fixture();
      final alone = await project(shippedPinsConfig());

      final withUpgrade = planUpgradeRun(
        fixture.project,
        templates: TemplateResolver(),
        homeDirectory: fixture.home,
        addedPacks: const ['agent-skills'],
        generators: shippedGenerators(),
      );
      final addOnly = _planAdding(alone, const ['agent-skills']);

      expect(
        withUpgrade.header,
        'pack upgrade: agent-skills $skills (added), acme 1.0.0 -> 1.2.0',
      );
      expect(addOnly.header, 'pack upgrade: agent-skills $skills (added)');
      expect(addOnly.toText(), isNot(contains('pins unchanged')));
    });

    test('two added pins list in the order given in the config, lines, '
        'header, and json', () async {
      final root = await project(shippedPinsConfig());

      final plan = _planAdding(root, const ['agent-skills', 'marketing']);

      expect(
        plan.header,
        'pack upgrade: agent-skills $skills (added), marketing $marketing '
        '(added)',
      );
      expect(
        plan.toText(),
        contains(
          '  $_configPath: agent-skills $skills (added)\n'
          '  $_configPath: marketing $marketing (added)\n',
        ),
      );
      expect(
        _configWrittenBy(plan),
        'packs:\n'
        '  prd-core: $core\n'
        '  software-tech: $tech\n'
        '  agent-skills: $skills\n'
        '  marketing: $marketing\n',
      );
      expect(plan.lists.toJson()['addedPins'], [
        {'pack': 'agent-skills', 'version': skills},
        {'pack': 'marketing', 'version': marketing},
      ]);
    });

    test('a run with no add holds no addedPins key', () async {
      final root = await project(shippedPinsConfig());

      expect(_planAt(root).lists.toJson(), isNot(contains('addedPins')));
    });

    group('a block map takes the pin after its last entry line with that '
        'indent', () {
      for (final (:label, :config, :expected) in [
        (
          label: 'a trailing comment on the last entry',
          config: 'packs:\n  prd-core: $core\n  software-tech: $tech # keep\n',
          expected:
              'packs:\n  prd-core: $core\n  software-tech: $tech # keep\n'
              '  agent-skills: $skills\n',
        ),
        (
          label: 'blank lines then another key',
          config:
              'packs:\n  prd-core: $core\n  software-tech: $tech\n\n\n'
              'verification_coverage: false\n',
          expected:
              'packs:\n  prd-core: $core\n  software-tech: $tech\n'
              '  agent-skills: $skills\n\n\nverification_coverage: false\n',
        ),
        (
          label: 'a four-space indent',
          config: 'packs:\n    prd-core: $core\n    software-tech: $tech\n',
          expected:
              'packs:\n    prd-core: $core\n    software-tech: $tech\n'
              '    agent-skills: $skills\n',
        ),
        (
          label: 'CRLF line endings',
          config:
              'packs:\r\n  prd-core: $core\r\n  software-tech: $tech\r\n'
              'verification_coverage: false\r\n',
          expected:
              'packs:\r\n  prd-core: $core\r\n  software-tech: $tech\r\n'
              '  agent-skills: $skills\r\nverification_coverage: false\r\n',
        ),
      ]) {
        test(label, () async {
          final root = await project(config);

          final plan = _planAdding(root, const ['agent-skills']);

          expect(_configWrittenBy(plan), expected);
        });
      }
    });

    group('a one-line flow map takes the pin after its last value', () {
      for (final (:label, :config, :expected) in [
        (
          label: 'with no inner space',
          config: 'packs: {prd-core: $core}\n',
          expected: 'packs: {prd-core: $core, agent-skills: $skills}\n',
        ),
        (
          label: 'with a space inside the braces',
          config: 'packs: { prd-core: $core }\n',
          expected: 'packs: { prd-core: $core, agent-skills: $skills }\n',
        ),
      ]) {
        test(label, () async {
          final root = await project(config);

          final plan = _planAdding(root, const ['agent-skills']);

          expect(_configWrittenBy(plan), expected);
        });
      }
    });

    test(
      'an added pack leads the header ahead of the spec tree move',
      () async {
        final root = await _treeProject({
          'specs/TECH_STACK.md': _draftDoc('Tech stack'),
        });

        final plan = _planAdding(root, const ['agent-skills']);

        expect(
          plan.header,
          'pack upgrade: agent-skills $skills (added), spec tree to flutter',
        );
      },
    );

    test('a dangling override of an added pack names its version', () async {
      final root = await _treeProject(
        const {},
        config: shippedPinsConfig(),
        extra: {
          '.specstone/templates/skill.yaml':
              'sections: [{id: nosuch, required: true}]\n',
        },
      );

      expect(
        () => _planAdding(root, const ['agent-skills']),
        throwsA(
          isA<MigrateFault>()
              .having((f) => f.code, 'code', MigrateFaultCode.overrideDangling)
              .having(
                (f) => f.message,
                'message',
                startsWith('pack agent-skills $skills defines no section '),
              ),
        ),
      );
    });

    test('an empty one-line flow map takes the pins with no leading '
        'comma', () {
      final pins = [
        AddedPin(pack: 'agent-skills', version: _version(skills)),
        AddedPin(pack: 'marketing', version: _version(marketing)),
      ];

      expect(
        withPinsAppended('packs: {}\n', pins),
        'packs: {agent-skills: $skills, marketing: $marketing}\n',
      );
    });

    test('a multi-line flow map refuses unknown_value at packs', () async {
      final root = await project(
        'packs: {\n  prd-core: $core,\n  software-tech: $tech\n}\n',
      );

      expect(
        () => _planAdding(root, const ['agent-skills']),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.unknownValue)
              .having((f) => f.file, 'file', _configPath)
              .having((f) => f.key, 'key', 'packs')
              .having(
                (f) => f.message,
                'message',
                'migrate --add writes a packs block map or a one-line flow '
                    'map; add the pin by hand',
              ),
        ),
      );
    });

    test('an added pack whose base is neither pinned nor added raises the '
        'load fault before the plan', () async {
      final root = await project('packs:\n  prd-core: $core\n');

      expect(
        () => _planAdding(root, const ['software-design-system']),
        throwsA(
          isA<TemplateFault>().having(
            (f) => f.code,
            'code',
            FaultCode.extendsTargetUnknown,
          ),
        ),
      );
      expect(
        _planAdding(root, const ['software-design-system', 'software-tech']),
        isA<RunPlan>(),
      );
    });

    group('docs the add newly types', () {
      const skillPath = 'docs/specs/skills/review.md';
      const skillDoc = '# Review\n\n\n\n## Purpose\n\nReviews.\n';

      Future<Directory> withDocs(Map<String, String> docs) => writeTree({
        _configPath: shippedPinsConfig(),
        for (final MapEntry(:key, :value) in docs.entries) 'docs/$key': value,
      });

      test('a file only the added pack types gets a draft flag and is '
          'laid out', () async {
        final root = await withDocs({'specs/skills/review.md': skillDoc});

        final plan = _planAdding(root, const ['agent-skills']);

        final text = _rewriteAt(plan, skillPath).text;
        expect(text, startsWith('---\ndraft: true\n---\n'));
        expect(text, isNot(contains('approved:')));
        expect(text, contains('# Review\n\n## Purpose\n'));
        expect(plan.lists.formatLayout, ['specs/skills/review.md']);
      });

      test('the plan counts newly typed docs before the layout line and '
          'lists them in json', () async {
        final root = await withDocs({
          'specs/skills/review.md': skillDoc,
          'specs/skills/deploy.md': skillDoc,
        });

        final plan = _planAdding(root, const ['agent-skills']);

        final lines = plan.toText().split('\n');
        final counted = lines.indexOf('  typed by the add: 2 docs');
        expect(counted, isNonNegative);
        expect(lines[counted + 1], startsWith('  format layout: '));
        expect(plan.lists.toJson()['typedByAdd'], [
          'specs/skills/deploy.md',
          'specs/skills/review.md',
        ]);
      });

      test('an add that types nothing prints no count line and no json '
          'key', () async {
        final root = await withDocs({'specs/skills/review.md': skillDoc});

        final plan = _planAdding(root, const ['marketing']);

        expect(plan.toText(), isNot(contains('typed by the add')));
        expect(plan.lists.toJson(), isNot(contains('typedByAdd')));
        expect(plan.rewrites.map((rewrite) => rewrite.path), [_configPath]);
      });

      test('a doc already typed gets no draft flag and is still laid '
          'out', () async {
        final root = await withDocs({
          'specs/TECH_STACK.md': '# Tech stack\n\n\n\n## Stack\n\nDart.\n',
          'specs/skills/review.md': skillDoc,
        });

        final plan = _planAdding(root, const ['agent-skills']);

        expect(plan.lists.toJson()['typedByAdd'], ['specs/skills/review.md']);
        expect(plan.lists.formatLayout, contains('specs/TECH_STACK.md'));
        expect(
          _rewriteAt(plan, 'docs/specs/TECH_STACK.md').text,
          isNot(contains('draft: true')),
        );
      });

      test('a file with frontmatter takes the flag once, an existing draft '
          'keeps its line', () async {
        final root = await withDocs({
          'specs/skills/review.md':
              '---\noutput: .claude/skills/review/\n---\n# Review\n\n'
              '## Purpose\n\nReviews.\n',
          'specs/skills/deploy.md':
              '---\ndraft: true # note\n---\n# Deploy\n\n## Purpose\n\nx\n',
        });

        final plan = _planAdding(root, const ['agent-skills']);

        expect(
          _rewriteAt(plan, skillPath).text,
          '---\ndraft: true\noutput: .claude/skills/review/\n---\n'
          '# Review\n\n## Purpose\n\nReviews.\n',
        );
        expect(
          plan.rewrites.map((rewrite) => rewrite.path),
          isNot(contains('docs/specs/skills/deploy.md')),
        );
      });

      test('an override of a type only the added pack defines still '
          'plans', () async {
        final root = await writeTree({
          _configPath: shippedPinsConfig(const ['prd-core']),
          '.specstone/templates/skill.yaml':
              'fields:\n  - {id: extra, type: string}\n',
          'docs/specs/skills/review.md': skillDoc,
        });

        final plan = _planAdding(root, const ['agent-skills']);

        expect(plan.lists.toJson()['typedByAdd'], ['specs/skills/review.md']);
      });

      test('a path-only override of a type only the added pack defines '
          'still plans', () async {
        final root = await writeTree({
          _configPath: shippedPinsConfig(const ['prd-core']),
          '.specstone/templates/skill.yaml':
              'path: specs/agent-skills/{slug}.md\n',
          'docs/specs/agent-skills/review.md': skillDoc,
        });

        final plan = _planAdding(root, const ['agent-skills']);

        expect(plan.lists.toJson()['typedByAdd'], [
          'specs/agent-skills/review.md',
        ]);
      });

      test('a project type extending a project type extending a pinned type '
          'stands without the add, so its docs are neither drafted nor '
          'newly typed', () async {
        final root = await writeTree({
          _configPath: shippedPinsConfig(const ['prd-core']),
          '.specstone/templates/a.yaml':
              'id: a\nextends: glossary\npath: prds/as/{slug}.md\n',
          '.specstone/templates/b.yaml':
              'id: b\nextends: a\npath: prds/bs/{slug}.md\n',
          'docs/prds/bs/one.md': '# One\n\n\n\nText.\n',
        });

        final plan = _planAdding(root, const ['agent-skills']);

        expect(plan.lists.toJson(), isNot(contains('typedByAdd')));
        expect(
          _rewriteAt(plan, 'docs/prds/bs/one.md').text,
          isNot(contains('draft: true')),
        );
      });

      test('a newly typed doc the run also moves is listed at its planned '
          'path', () async {
        final home = await writeTree({
          '.specstone/packs/mine/pack.yaml': 'name: mine\nversion: 1.0.0\n',
          '.specstone/packs/mine/memo.yaml':
              'id: memo\ndescription: A memo.\npath: specs/MEMO.md\n'
              'per_target: true\n',
        });
        final root = await _treeProject({
          'specs/MEMO.md': '# Memo\n\n\n\nText.\n',
        });

        final plan = planUpgradeRun(
          _canonical(root),
          templates: TemplateResolver(),
          homeDirectory: home,
          addedPacks: const ['mine'],
          generators: shippedGenerators(),
        );

        expect(plan.lists.toJson()['typedByAdd'], ['specs/flutter/MEMO.md']);
        expect(
          _rewriteAt(plan, 'docs/specs/flutter/MEMO.md').text,
          startsWith('---\ndraft: true\n---\n'),
        );
      });
    });

    test('the form check refuses before the load fault', () async {
      final root = await project('packs: {\n  prd-core: $core\n}\n');

      expect(
        () => _planAdding(root, const ['software-design-system']),
        throwsA(
          isA<TemplateFault>().having(
            (f) => f.code,
            'code',
            FaultCode.unknownValue,
          ),
        ),
      );
    });
  });
}

void _dropSharedLinesTests() {
  group('drop_shared_lines step', () {
    test('a drop_shared_lines step plans a 0 docs line, no writes', () async {
      const packYaml = '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - drop_shared_lines: {ids: [ghost]}
''';
      final plan = _plan(
        await _fixture(
          packYaml: packYaml,
          overrides: const {
            _overridePath: 'sections: [{id: procedure, description: Kept.}]\n',
          },
        ),
      );

      expect(
        plan.toText(),
        contains(
          'commit 2, rewrites:\n'
          '  from 1.0.0: drop_shared_lines: 0 docs\n',
        ),
      );
      expect(plan.lists.toJson()['steps'], [
        {'from': '1.0.0', 'step': 'drop_shared_lines', 'paths': <String>[]},
      ]);
      final rewritten = plan.rewrites.map((rewrite) => rewrite.path);
      expect(
        rewritten,
        isNot(contains('docs/prds/runbooks/deploy/RUNBOOK.md')),
      );
      expect(rewritten, isNot(contains(_overridePath)));
    });
  });
}

void _markRetrimTests() {
  group('mark_retrim step', () {
    test('a pin at the from of a mark_retrim entry selects its step', () async {
      const packYaml = '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - mark_retrim: {doc_types: [rulebook], sections: [invariants]}
''';
      final plan = _plan(
        await _fixture(
          packYaml: packYaml,
          runbookType: _rulebookTypes,
          overrides: const {},
          docs: {_loginPath: _loginDoc},
        ),
      );

      expect(
        plan.toText(),
        contains(
          'commit 2, rewrites:\n'
          '  from 1.0.0: mark_retrim: 1 docs\n',
        ),
      );
      expect(plan.lists.toJson()['steps'], [
        {
          'from': '1.0.0',
          'step': 'mark_retrim',
          'paths': [_loginPath],
        },
      ]);
      expect(
        _rewriteAt(plan, 'docs/$_loginPath').text,
        '---\nretrim:\n  - invariants\n---\n\n$_loginDoc',
      );
    });
  });
}

// MARK: - Matrix fold pass

const _foldFr = 'email_login/validate_credentials';
const _foldFlutterRecord =
    '.specstone/records/flutter/f01_login/IMPLEMENTATION.md';
const _foldJasprRecord = '.specstone/records/jaspr/f01_login/IMPLEMENTATION.md';
const _foldEdgeRows = [
  '- $_foldFr E01: `rejects a wrong key`',
  '- $_foldFr E02: `rejects an empty key`',
];
const _foldedRow = '- $_foldFr: `rejects a wrong key`, `rejects an empty key`';

/// A record of the login feature whose Verification matrix holds [rows].
String _foldRecord(List<String> rows, {String front = ''}) =>
    "---\n${front}statuses:\n  - 'email_login:implemented'\n---\n\n"
    '# Login implementation\n\n## Verification matrix\n\n${rows.join('\n')}\n';

/// A project pinned to the shipped packs under [coverage] (omitted for off),
/// holding the plain login docs and each of [records] by project path.
Future<Directory> _foldProject(
  Map<String, String> records, {
  String? coverage,
  String? config,
}) => writeTree({
  '.specstone/config.yaml':
      config ??
      '${shippedPinsConfig()}'
          '${coverage == null ? '' : 'verification_coverage: $coverage\n'}',
  for (final MapEntry(:key, :value) in _plainLoginDocs.entries)
    'docs/$key': value,
  ...records,
});

/// The project path of each record [plan] rewrites.
List<String> _foldedPaths(RunPlan plan) => [
  for (final rewrite in plan.rewrites)
    if (rewrite.path.startsWith('.specstone/records/')) rewrite.path,
];

void _matrixFoldTests() {
  group('matrix fold pass', () {
    const twinFold = [_foldFlutterRecord, _foldJasprRecord];

    for (final coverage in <String?>[null, 'fr']) {
      test("folds every target's records under "
          '${coverage ?? 'off'}', () async {
        final project = await _foldProject(
          {for (final path in twinFold) path: _foldRecord(_foldEdgeRows)},
          config:
              '${twinConfig()}'
              '${coverage == null ? '' : 'verification_coverage: $coverage\n'}',
        );

        final plan = _planAt(project);

        expect(_foldedPaths(plan), twinFold);
        for (final path in twinFold) {
          expect(_rewriteAt(plan, path).text, _foldRecord([_foldedRow]));
        }
        expect(
          plan.toText(),
          contains('  matrix rows: 4 rows folded into 2 rows in 2 records\n'),
        );
        expect(plan.lists.toJson()['matrixRows'], {'folded': twinFold});
      });
    }

    test('does not run under edge_case', () async {
      final project = await _foldProject({
        _foldFlutterRecord: _foldRecord(_foldEdgeRows),
      }, coverage: 'edge_case');

      final plan = _planAt(project);

      expect(_foldedPaths(plan), isEmpty);
      expect(plan.toText(), isNot(contains('matrix rows:')));
      expect(plan.lists.toJson(), isNot(contains('matrixRows')));
    });

    test('plans no fold for a record already folded', () async {
      final project = await _foldProject({
        _foldFlutterRecord: _foldRecord([_foldedRow]),
      }, config: '${twinConfig()}verification_coverage: fr\n');

      final plan = _planAt(project);

      expect(_foldedPaths(plan), isEmpty);
      expect(plan.toText(), isNot(contains('matrix rows:')));
      expect(plan.lists.toJson(), isNot(contains('matrixRows')));
    });

    test(
      'does not run when only story or feature rows are per-edge-case',
      () async {
        final project = await _foldProject({
          _foldFlutterRecord: _foldRecord([
            '- email_login E01: `signs in`',
            '- login E01: `loads the feature`',
            '- no_such_doc E01: `names no doc`',
          ]),
        }, coverage: 'fr');

        final plan = _planAt(project);

        expect(_foldedPaths(plan), isEmpty);
        expect(plan.toText(), isNot(contains('matrix rows:')));
        expect(plan.lists.toJson(), isNot(contains('matrixRows')));
      },
    );

    test('leaves approval fields as they were when it folds', () async {
      final type = TemplateResolver()
          .resolveCarried(
            packNames: const ['prd-core', 'software-tech'],
            homeDirectory: null,
          )
          .recordDocType;
      final approved = _stampedBefore(_foldRecord(_foldEdgeRows), type);
      final project = await _foldProject({
        _foldFlutterRecord: approved,
        _foldJasprRecord: _foldRecord(_foldEdgeRows, front: 'draft: true\n'),
      }, config: twinConfig());

      final plan = _planAt(project);

      final stamp = RegExp(r'^approved: .*$', multiLine: true);
      final folded = _rewriteAt(plan, _foldFlutterRecord).text;
      expect(
        stamp.firstMatch(folded)?.group(0),
        stamp.firstMatch(approved)![0],
      );
      expect(folded, contains(_foldedRow));
      final draft = _rewriteAt(plan, _foldJasprRecord).text;
      expect(draft, startsWith('---\ndraft: true\n'));
      expect(draft, contains(_foldedRow));
    });
  });
}

/// The acme doc types of the drop and retrim fixtures: the runbook, and the
/// rulebook pair standing in for the per-feature and project rule docs.
const _rulebookTypes =
    '$_runbookType---\n$rulebookLayer---\n$projectRulebookLayer';

const _loginPath = 'specs/f01_login/DOMAIN.md';

String _domainText(String rows, String invariants) =>
    '# Domain\n\n## Entities\n\n| Entity | Kind | Identity | Owns |\n'
    '|---|---|---|---|\n${rows.isEmpty ? '' : '$rows\n'}\n'
    '## Invariants\n\n$invariants\n';

const _accountRow = '| Account | Aggregate root | its email | a name |';
const _statedDefaults =
    '- **INV-1** An email is unique.\n'
    '  - **Enforcer:** Account\n'
    '  - **Consistency:** immediate';
final String _loginDoc = _domainText(_accountRow, _statedDefaults);

const _mergePackYaml = '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - merge_doc:
          from: {id: playbook, path: "prds/runbooks/{slug}/PLAYBOOK.md"}
          to: runbook
          sections:
            - from: {id: moves, header: Moves}
              to: procedure
''';

/// [_mergePackYaml] with a `relink_merged_docs` entry after its fold.
const _relinkPackYaml =
    '''
$_mergePackYaml  - from: 1.1.0
    steps:
      - relink_merged_docs: {}
''';

const _mergeType = '''
id: runbook
description: A runbook.
path: prds/runbooks/{slug}/RUNBOOK.md
sections:
  - {id: goals, header: Goals}
  - {id: procedure, header: Procedure}
''';

const _mergeTwinType = '''
id: runbook
description: A runbook.
path: prds/runbooks/{slug}/RUNBOOK.md
per_target: true
sections:
  - {id: goals, header: Goals}
  - {id: procedure, header: Procedure}
''';

const _mergeRetrimPackYaml = '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - merge_doc:
          from: {id: playbook, path: "prds/runbooks/{slug}/PLAYBOOK.md"}
          to: runbook
          sections:
            - from: {id: moves, header: Moves}
              to: procedure
            - from: {id: aims, header: Aims}
              to: goals
      - mark_retrim: {doc_types: [runbook], sections: [procedure]}
''';

const _dropThenMergePackYaml = '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - drop_section: {doc_types: [playbook], section: {id: notes, header: Notes}}
  - from: 1.1.0
    steps:
      - merge_doc:
          from: {id: playbook, path: "prds/runbooks/{slug}/PLAYBOOK.md"}
          to: runbook
          sections:
            - from: {id: moves, header: Moves}
              to: procedure
''';

/// A pack whose drop of the `to` type's Notes runs before a fold brings one.
const _dropToThenMergePackYaml = '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - drop_section: {doc_types: [runbook], section: {id: notes, header: Notes}}
      - merge_doc:
          from: {id: playbook, path: "prds/runbooks/{slug}/PLAYBOOK.md"}
          to: runbook
          sections:
            - from: {id: moves, header: Moves}
              to: procedure
''';

/// The `playbook` doc type of [_dropThenMergePackYaml] before its fold.
const _frozenMovesPlaybookType = '''
id: playbook
description: A playbook.
path: prds/runbooks/{slug}/PLAYBOOK.md
sections:
  - {id: moves, header: Moves}
''';

final String _nestedMergePackYaml = _mergePackYaml.replaceFirst(
  'prds/runbooks/{slug}/PLAYBOOK.md',
  'specs/f{nn}_{slug}/PLAYBOOK.md',
);

final String _nestedMergeType = _mergeType.replaceFirst(
  'path: prds/runbooks/{slug}/RUNBOOK.md',
  'path: specs/f{nn}_{slug}/RUNBOOK.md\nparent: feature',
);

const _mergeToPath = 'prds/runbooks/deploy/RUNBOOK.md';
const _mergeFromPath = 'prds/runbooks/deploy/PLAYBOOK.md';
const _mergeToDoc = '# Deploy\n\n## Goals\n\nShip it.\n';
const _mergeFromDoc =
    '---\ntasks:\n  - Review\n---\n# Deploy playbook\n\n'
    '## Moves\n\nRun it.\n\n## Notes\n\nKeep calm.\n';
const _mergedDoc =
    '---\ntasks:\n  - Review\n---\n\n# Deploy\n\n## Goals\n\nShip it.\n\n'
    '## Procedure\n\nRun it.\n\n## Notes\n\nKeep calm.\n';
const _mergeLayerPath = '.specstone/templates/playbook.yaml';

/// The project and personal home of a `merge_doc` fixture.
final class _MergeFixture {
  const new(this.project, this.home);

  final Directory project;
  final Directory home;
}

Future<_MergeFixture> _mergeFixture({
  Map<String, String> docs = const {
    _mergeToPath: _mergeToDoc,
    _mergeFromPath: _mergeFromDoc,
  },
  Map<String, String> overrides = const {},
  String packYaml = _mergePackYaml,
  String runbookType = _mergeType,
}) async {
  final fixture = await _fixture(
    packYaml: packYaml,
    runbookType: runbookType,
    docs: docs,
    overrides: overrides,
  );
  return _MergeFixture(fixture.project, fixture.home);
}

RunPlan _planMerge(_MergeFixture fixture) => planUpgradeRun(
  fixture.project,
  templates: TemplateResolver(),
  homeDirectory: fixture.home,
  generators: shippedGenerators(),
);

const _dropTypePackYaml = '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - drop_doc_type: {id: x, path: "xs/{slug}.md"}
''';

const _dropTypeThenMergePackYaml = '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - drop_doc_type: {id: x, path: "xs/{slug}.md"}
      - merge_doc:
          from: {id: playbook, path: "prds/runbooks/{slug}/PLAYBOOK.md"}
          to: runbook
          sections:
            - from: {id: moves, header: Moves}
              to: procedure
''';

const _dropTypeLayerPath = '.specstone/templates/x.yaml';

void _dropDocTypeTests() {
  group('drop_doc_type step', () {
    test('the plan prints its line with 0 docs and the run writes no doc '
        'file', () async {
      final plan = _planMerge(
        await _mergeFixture(
          packYaml: _dropTypePackYaml,
          docs: const {'xs/a.md': '# A\n'},
        ),
      );

      expect(
        plan.toText(),
        contains('  from 1.0.0: drop_doc_type x: 0 docs\n'),
      );
      expect(plan.lists.toJson()['steps'], [
        {'from': '1.0.0', 'step': 'drop_doc_type x', 'paths': <String>[]},
      ]);
      expect(plan.rewrites.where((r) => r.path.startsWith('docs/')), isEmpty);
      expect(plan.creates.where((c) => c.path.startsWith('docs/')), isEmpty);
      expect(plan.trashedDocs, isEmpty);
    });

    test('a project layer file of the dropped type is kept, named by a layers '
        'kept line after the step line and by keptLayers', () async {
      final plan = _planMerge(
        await _mergeFixture(
          packYaml: _dropTypePackYaml,
          overrides: const {_dropTypeLayerPath: 'sections: [{id: gone}]\n'},
        ),
      );

      expect(plan.keptLayers, [_dropTypeLayerPath]);
      expect(
        plan.toText(),
        contains(
          '  from 1.0.0: drop_doc_type x: 0 docs\n'
          '  layers kept: 1\n',
        ),
      );
      expect(plan.lists.toJson()['keptLayers'], [_dropTypeLayerPath]);
      expect(plan.trashedDocs, isNot(contains(_dropTypeLayerPath)));
      expect(
        plan.rewrites.map((r) => r.path),
        isNot(contains(_dropTypeLayerPath)),
      );
    });

    test('with a merge_doc step after it the layers kept line follows the '
        'merge_doc step line and counts both files', () async {
      final plan = _planMerge(
        await _mergeFixture(
          packYaml: _dropTypeThenMergePackYaml,
          overrides: const {
            _dropTypeLayerPath: 'sections: []\n',
            _mergeLayerPath: 'sections: []\n',
          },
        ),
      );

      expect(plan.keptLayers, [_dropTypeLayerPath, _mergeLayerPath]);
      expect(
        plan.toText(),
        contains(
          '  from 1.0.0: drop_doc_type x: 0 docs\n'
          '  from 1.0.0: merge_doc playbook -> runbook: 1 docs\n'
          '  layers kept: 2\n',
        ),
      );
    });

    test(
      'no layer file of the dropped type prints no layers kept line',
      () async {
        final plan = _planMerge(
          await _mergeFixture(packYaml: _dropTypePackYaml),
        );

        expect(plan.keptLayers, isEmpty);
        expect(plan.toText(), isNot(contains('layers kept')));
      },
    );
  });
}

void _mergeDocTests() {
  group('merge_doc step', () {
    test('each section and list field entry of a from doc lands in its to '
        'doc, the mapped section under the to header', () async {
      final plan = _planMerge(await _mergeFixture());

      expect(_rewriteAt(plan, 'docs/$_mergeToPath').text, _mergedDoc);
      expect(
        plan.rewrites.where((rewrite) => rewrite.path.endsWith('PLAYBOOK.md')),
        isEmpty,
      );
    });

    test(
      'the from file moves to the trash and no doc commit writes it',
      () async {
        final plan = _planMerge(await _mergeFixture());

        expect(plan.trashedDocs, ['docs/$_mergeFromPath']);
        expect(plan.creates, isEmpty);
      },
    );

    test('a to doc the project lacks is created as a draft holding the '
        'sections and entries', () async {
      final plan = _planMerge(
        await _mergeFixture(docs: const {_mergeFromPath: _mergeFromDoc}),
      );

      final create = plan.creates.single;
      expect(create.path, 'docs/$_mergeToPath');
      expect(create.note, ' (draft)');
      expect(
        create.text,
        '---\ndraft: true\ntasks:\n  - Review\n---\n\n# Deploy playbook\n\n'
        '## Procedure\n\nRun it.\n\n## Notes\n\nKeep calm.\n',
      );
      expect(plan.trashedDocs, ['docs/$_mergeFromPath']);
      expect(plan.rewrites.where((r) => r.path.startsWith('docs/')), isEmpty);
    });

    test('a to doc the project lacks whose path a folder holds refuses '
        'upgrade_collision before any write', () async {
      final fixture = await _mergeFixture(
        docs: const {
          _mergeFromPath: _mergeFromDoc,
          '$_mergeToPath/notes.md': '# Notes\n',
        },
      );

      final fault = _refusedWith(() => _planMerge(fixture));

      expect(fault.code, MigrateFaultCode.upgradeCollision);
      expect(fault.file, 'docs/$_mergeToPath');
    });

    test('a created to doc stays an unapproved draft when the pins sit below '
        'the stamp passes, and no stamp is counted for it', () async {
      final plan = _planMerge(
        await _mergeFixture(
          docs: const {_mergeFromPath: _mergeFromDoc},
          overrides: const {
            '.specstone/config.yaml':
                'packs:\n  prd-core: 1.0.0\n  software-tech: 1.0.0\n'
                '  acme: 1.0.0\n',
          },
        ),
      );

      final create = plan.creates.single;
      expect(create.path, 'docs/$_mergeToPath');
      expect(create.text, startsWith('---\ndraft: true\n'));
      expect(create.text, isNot(contains('approved:')));
      expect(plan.toText(), isNot(contains('stamp approvals')));
    });

    test('the step line keeps the from version, the step, and the count of '
        'the docs it writes', () async {
      final plan = _planMerge(await _mergeFixture());

      expect(
        plan.toText(),
        contains(
          'commit 2, rewrites:\n'
          '  from 1.0.0: merge_doc playbook -> runbook: 1 docs\n',
        ),
      );
      expect(plan.lists.toJson()['steps'], [
        {
          'from': '1.0.0',
          'step': 'merge_doc playbook -> runbook',
          'paths': [_mergeToPath],
        },
      ]);
    });

    test('a from doc takes no earlier step of another pack, so a fold of '
        'a type another pack steps plans with no frozen copy', () async {
      final home = await writeTree({
        '.specstone/packs/acme/pack.yaml':
            'name: acme\nversion: 1.2.0\nextends: software-tech\n'
            'migrations:\n  - from: 1.0.0\n    steps:\n'
            '      - bullet_lines: {doc_type: runbook, section: procedure, '
            'prefixes: [A]}\n',
        '.specstone/packs/acme/runbook.yaml': _mergeType,
        '.specstone/packs/zeta/pack.yaml':
            'name: zeta\nversion: 1.1.0\nextends: acme\n'
            'migrations:\n  - from: 1.0.0\n    steps:\n'
            '      - merge_doc:\n'
            '          from: {id: runbook, path: '
            '"prds/runbooks/{slug}/RUNBOOK.md"}\n'
            '          to: guide\n'
            '          sections:\n'
            '            - from: {id: procedure, header: Procedure}\n'
            '              to: steps\n',
        '.specstone/packs/zeta/guide.yaml':
            'id: guide\ndescription: A guide.\n'
            'path: prds/guides/{slug}/GUIDE.md\n'
            'sections:\n  - {id: steps, header: Steps}\n',
      });
      final project = await writeTree({
        '.specstone/config.yaml':
            '${shippedPinsConfig()}  acme: 1.0.0\n  zeta: 1.0.0\n',
        'docs/$_mergeToPath': '# Deploy\n\n## Procedure\n\nA step.\n',
      });

      final plan = planUpgradeRun(
        project,
        templates: TemplateResolver(),
        homeDirectory: home,
        generators: shippedGenerators(),
      );

      expect(
        plan.creates
            .singleWhere(
              (create) => create.path == 'docs/prds/guides/deploy/GUIDE.md',
            )
            .text,
        contains('## Steps\n\nA step.\n'),
      );
      expect(
        plan.lists.toJson()['steps'],
        contains(
          equals({
            'from': '1.0.0',
            'step': 'bullet_lines runbook procedure',
            'paths': <String>[],
          }),
        ),
      );
    });

    test('a personal pack with an earlier step on a from type and no frozen '
        'file for it refuses missing_key at that file', () async {
      final fixture = await _mergeFixture(packYaml: _dropThenMergePackYaml);

      expect(
        () => _planMerge(fixture),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.missingKey)
              .having(
                (f) => f.file,
                'file',
                '~/.specstone/packs/acme/frozen/playbook.yaml',
              ),
        ),
      );
    });

    test('a from doc at the path a project layer writes for its type is '
        'folded, and one at the step path is not', () async {
      const layerFromPath = 'prds/books/deploy/PLAYBOOK.md';
      final plan = _planMerge(
        await _mergeFixture(
          docs: const {
            _mergeToPath: _mergeToDoc,
            layerFromPath: _mergeFromDoc,
            'prds/runbooks/build/PLAYBOOK.md': '# Build\n\n## Moves\n\nx\n',
          },
          overrides: const {
            _mergeLayerPath: 'path: "prds/books/{slug}/PLAYBOOK.md"\n',
          },
        ),
      );

      expect(plan.trashedDocs, ['docs/$layerFromPath']);
      expect(_rewriteAt(plan, 'docs/$_mergeToPath').text, _mergedDoc);
    });

    test('a project layer file of the from type is kept as written, named by '
        'a layers kept line after the step line and by keptLayers', () async {
      final plan = _planMerge(
        await _mergeFixture(
          overrides: const {_mergeLayerPath: 'sections: [{id: gone}]\n'},
        ),
      );

      expect(plan.keptLayers, [_mergeLayerPath]);
      expect(
        plan.toText(),
        contains(
          '  from 1.0.0: merge_doc playbook -> runbook: 1 docs\n'
          '  layers kept: 1\n',
        ),
      );
      expect(plan.lists.toJson()['keptLayers'], [_mergeLayerPath]);
      expect(plan.trashedDocs, isNot(contains(_mergeLayerPath)));
      expect(
        plan.rewrites.map((r) => r.path),
        isNot(contains(_mergeLayerPath)),
      );
    });

    for (final (:name, :packYaml, :layerPath, :merges) in [
      (
        name: 'merge_doc from type',
        packYaml: _mergePackYaml,
        layerPath: _mergeLayerPath,
        merges: true,
      ),
      (
        name: 'drop_doc_type id',
        packYaml: _dropTypePackYaml,
        layerPath: _dropTypeLayerPath,
        merges: false,
      ),
    ]) {
      test('a layer file that holds invalid YAML halts nothing: the plan '
          'prints and keeps the file, $name', () async {
        final plan = _planMerge(
          await _mergeFixture(
            packYaml: packYaml,
            overrides: {layerPath: 'path: [oops\n'},
          ),
        );

        expect(plan.keptLayers, [layerPath]);
        if (merges) {
          expect(_rewriteAt(plan, 'docs/$_mergeToPath').text, _mergedDoc);
        }
      });
    }

    test(
      'no layer file prints no layers kept line and no keptLayers key',
      () async {
        final plan = _planMerge(await _mergeFixture());

        expect(plan.keptLayers, isEmpty);
        expect(plan.toText(), isNot(contains('layers kept')));
        expect(plan.lists.toJson(), isNot(contains('keptLayers')));
      },
    );

    test('the layers kept line follows the last merge_doc step line and counts '
        'each kept file', () async {
      const packYaml = '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - merge_doc:
          from: {id: playbook, path: "prds/runbooks/{slug}/PLAYBOOK.md"}
          to: runbook
          sections:
            - from: {id: moves, header: Moves}
              to: procedure
      - merge_doc:
          from: {id: checklist, path: "prds/runbooks/{slug}/CHECKLIST.md"}
          to: runbook
          sections:
            - from: {id: other, header: Other}
              to: procedure
''';
      final plan = _planMerge(
        await _mergeFixture(
          packYaml: packYaml,
          docs: const {
            _mergeToPath: _mergeToDoc,
            _mergeFromPath: _mergeFromDoc,
            'prds/runbooks/deploy/CHECKLIST.md': '# C\n\n## Checks\n\nTick.\n',
          },
          overrides: const {
            _mergeLayerPath: 'sections: []\n',
            '.specstone/templates/checklist.yaml': 'sections: []\n',
          },
        ),
      );

      expect(
        plan.toText(),
        contains(
          '  from 1.0.0: merge_doc playbook -> runbook: 1 docs\n'
          '  from 1.0.0: merge_doc checklist -> runbook: 1 docs\n'
          '  layers kept: 2\n',
        ),
      );
      expect(plan.keptLayers, [
        _mergeLayerPath,
        '.specstone/templates/checklist.yaml',
      ]);
    });

    test('with two code targets each target folds its own from docs into its '
        'own to doc', () async {
      final project = await writeTree({
        '.specstone/config.yaml': twinConfig(),
        'docs/prds/flutter/runbooks/deploy/RUNBOOK.md': _mergeToDoc,
        'docs/prds/flutter/runbooks/deploy/PLAYBOOK.md': _mergeFromDoc,
        'docs/prds/jaspr/runbooks/deploy/RUNBOOK.md': _mergeToDoc,
        'docs/prds/jaspr/runbooks/deploy/PLAYBOOK.md':
            '# Deploy\n\n## Moves\n\nJaspr way.\n',
      });
      final home = (await _mergeFixture()).home;
      File('${home.path}/.specstone/packs/acme/runbook.yaml')
          .writeAsStringSync(_mergeTwinType);
      File('${project.path}/.specstone/config.yaml').writeAsStringSync(
        twinConfig().replaceFirst('packs:\n', 'packs:\n  acme: 1.0.0\n'),
      );

      final plan = _planMerge(_MergeFixture(project, home));

      expect(
        _rewriteAt(plan, 'docs/prds/flutter/runbooks/deploy/RUNBOOK.md').text,
        _mergedDoc,
      );
      expect(
        _rewriteAt(plan, 'docs/prds/jaspr/runbooks/deploy/RUNBOOK.md').text,
        '# Deploy\n\n## Goals\n\nShip it.\n\n## Procedure\n\nJaspr way.\n',
      );
      expect(plan.trashedDocs, [
        'docs/prds/flutter/runbooks/deploy/PLAYBOOK.md',
        'docs/prds/jaspr/runbooks/deploy/PLAYBOOK.md',
      ]);
    });

    test(
      'a section whose header the to doc already holds refuses '
      'upgrade_collision, listing each colliding doc once by its path',
      () async {
        final fixture = await _mergeFixture(
          docs: const {
            _mergeToPath: '$_mergeToDoc\n## Procedure\n\nHeld.\n',
            _mergeFromPath: _mergeFromDoc,
            'prds/runbooks/build/RUNBOOK.md':
                '# Build\n\n## Procedure\n\nHeld.\n',
            'prds/runbooks/build/PLAYBOOK.md': '# Build\n\n## Moves\n\nx\n',
          },
        );

        final fault = _refusedWith(() => _planMerge(fixture));

        expect(fault.code, MigrateFaultCode.upgradeCollision);
        expect(fault.exitStatus, 65);
        expect(fault.file, 'prds/runbooks/build/RUNBOOK.md');
        expect(fault.message, contains('Procedure'));
        expect(fault.message, contains('prds/runbooks/build/PLAYBOOK.md'));
        expect(fault.more.map((f) => f.file), [_mergeToPath]);
      },
    );

    test('a link to a mapped section, an unmapped section, or the doc whole '
        'follows the fold to the to doc', () async {
      const linker =
          '# Build\n\n'
          '[a](../deploy/PLAYBOOK.md#moves) '
          '[b](../deploy/PLAYBOOK.md#notes) '
          '[c](../deploy/PLAYBOOK.md)\n';
      final plan = _planMerge(
        await _mergeFixture(
          docs: const {
            _mergeToPath: _mergeToDoc,
            _mergeFromPath: _mergeFromDoc,
            'prds/runbooks/build/RUNBOOK.md': linker,
          },
        ),
      );

      expect(
        _rewriteAt(plan, 'docs/prds/runbooks/build/RUNBOOK.md').text,
        '# Build\n\n'
        '[a](../deploy/RUNBOOK.md#procedure) '
        '[b](../deploy/RUNBOOK.md#notes) '
        '[c](../deploy/RUNBOOK.md)\n',
      );
      expect(
        plan.toText(),
        contains('  prds/runbooks/build/RUNBOOK.md: links to merged docs\n'),
      );
    });

    test('a typed link text naming a folded doc, on any link, takes the to '
        "doc's typed name and section key; a code span keeps every "
        'byte', () async {
      const linker =
          '# Build\n\n'
          '[playbook:deploy](../deploy/PLAYBOOK.md) '
          '[playbook:deploy#moves][p] '
          '`[playbook:deploy](../deploy/PLAYBOOK.md)` '
          '[playbook:deploy](../build/NOTES.md) '
          '[note:deploy](../deploy/PLAYBOOK.md) '
          '[playbook:](../deploy/PLAYBOOK.md) '
          '[playbook:other](../deploy/PLAYBOOK.md)\n\n'
          '[p]: ../deploy/PLAYBOOK.md#moves\n';
      final plan = _planMerge(
        await _mergeFixture(
          docs: const {
            _mergeToPath: _mergeToDoc,
            _mergeFromPath: _mergeFromDoc,
            'prds/runbooks/build/RUNBOOK.md': linker,
          },
        ),
      );

      expect(
        _rewriteAt(plan, 'docs/prds/runbooks/build/RUNBOOK.md').text,
        '# Build\n\n'
        '[runbook:deploy](../deploy/RUNBOOK.md) '
        '[runbook:deploy#procedure][p] '
        '`[playbook:deploy](../deploy/PLAYBOOK.md)` '
        '[runbook:deploy](../build/NOTES.md) '
        '[note:deploy](../deploy/RUNBOOK.md) '
        '[playbook:](../deploy/RUNBOOK.md) '
        '[playbook:other](../deploy/RUNBOOK.md)\n\n'
        '[p]: ../deploy/RUNBOOK.md#procedure\n',
      );
    });

    const typedLinks =
        'See [playbook:deploy](PLAYBOOK.md) and [it](PLAYBOOK.md).\n';
    for (final (first, toLead, fromDoc, links, followed) in [
      (
        'a mapped section',
        '',
        _mergeFromDoc,
        typedLinks,
        'See [runbook:deploy](#procedure) and [it](#procedure).\n',
      ),
      (
        'an unmapped section',
        '',
        '# Deploy playbook\n\n## Notes\n\nKeep calm.\n\n## Moves\n\nRun it.\n',
        typedLinks,
        'See [runbook:deploy](#notes) and [it](#notes).\n',
      ),
      (
        'a section whose slug a heading of the to doc holds',
        '### Notes\n\nx\n\n',
        '# Deploy playbook\n\n## Notes\n\nKeep calm.\n',
        'See [it](PLAYBOOK.md).\n',
        'See [it](#notes-1).\n',
      ),
      (
        'missing',
        '',
        '# Deploy playbook\n',
        'See [it](PLAYBOOK.md).\n',
        'See it.\n',
      ),
    ]) {
      test('a whole-doc link in the to doc to the folded doc, whose first '
          'section is $first, reaches the header that section lands under, '
          'or unwraps to its text', () async {
        final plan = _planMerge(
          await _mergeFixture(
            docs: {
              _mergeToPath: '# Deploy\n\n## Goals\n\n$toLead$links',
              _mergeFromPath: fromDoc,
            },
          ),
        );

        expect(_rewriteAt(plan, 'docs/$_mergeToPath').text, contains(followed));
      });
    }

    test('a whole-doc link in the folded text to the to doc unwraps to its '
        'text', () async {
      final plan = _planMerge(
        await _mergeFixture(
          docs: const {
            _mergeToPath: _mergeToDoc,
            _mergeFromPath:
                '# Deploy playbook\n\n## Moves\n\nSee [the runbook](RUNBOOK.md) '
                'and [goals](RUNBOOK.md#goals).\n',
          },
        ),
      );

      expect(
        _rewriteAt(plan, 'docs/$_mergeToPath').text,
        contains(
          '## Procedure\n\nSee the runbook and [goals](RUNBOOK.md#goals).\n',
        ),
      );
    });

    test('a link to a section a drop took from the from doc before its fold '
        'loses its anchor, and a whole-doc link reaches the first section '
        'left', () async {
      final fixture = await _mergeFixture(
        packYaml: _dropThenMergePackYaml,
        docs: const {
          _mergeToPath: '# Deploy\n\n## Goals\n\nSee [w](PLAYBOOK.md).\n',
          _mergeFromPath:
              '# Deploy playbook\n\n## Notes\n\nCalm.\n\n## Moves\n\nRun.\n',
          'prds/runbooks/build/RUNBOOK.md':
              '# Build\n\n'
              '[n](../deploy/PLAYBOOK.md#notes) '
              '[m](../deploy/PLAYBOOK.md#moves)\n',
        },
      );
      File('${fixture.home.path}/.specstone/packs/acme/frozen/playbook.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync(_frozenMovesPlaybookType);

      final plan = _planMerge(fixture);

      expect(
        _rewriteAt(plan, 'docs/$_mergeToPath').text,
        contains('See [w](#procedure).\n'),
      );
      expect(
        _rewriteAt(plan, 'docs/prds/runbooks/build/RUNBOOK.md').text,
        '# Build\n\n'
        '[n](../deploy/RUNBOOK.md) '
        '[m](../deploy/RUNBOOK.md#procedure)\n',
      );
    });

    for (final (what, toBody) in [
      ('its own section', '## Goals\n\nShip.\n\n## Notes\n\nOld.\n'),
      ('an unrelated subheading', '## Goals\n\n### Notes\n\nOld.\n'),
    ]) {
      test('a link to a section a drop took from the from doc before its fold '
          'loses its anchor when the to doc holds $what of that '
          'slug', () async {
        final fixture = await _mergeFixture(
          packYaml: _dropThenMergePackYaml,
          docs: {
            _mergeToPath: '# Deploy\n\n$toBody',
            _mergeFromPath:
                '# Deploy playbook\n\n## Moves\n\nRun.\n\n## Notes\n\nCalm.\n',
            'prds/runbooks/build/RUNBOOK.md':
                '# Build\n\n[n](../deploy/PLAYBOOK.md#notes)\n',
          },
        );
        File('${fixture.home.path}/.specstone/packs/acme/frozen/playbook.yaml')
          ..createSync(recursive: true)
          ..writeAsStringSync(_frozenMovesPlaybookType);

        final plan = _planMerge(fixture);

        expect(
          _rewriteAt(plan, 'docs/prds/runbooks/build/RUNBOOK.md').text,
          '# Build\n\n[n](../deploy/RUNBOOK.md)\n',
        );
      });
    }

    test('a link to a dropped section keeps its anchor when a later fold '
        'brings a section of that header', () async {
      final plan = _planMerge(
        await _mergeFixture(
          packYaml: _dropToThenMergePackYaml,
          docs: const {
            _mergeToPath: '# Deploy\n\n## Goals\n\nShip.\n\n## Notes\n\nOld.\n',
            _mergeFromPath: _mergeFromDoc,
            'prds/runbooks/build/RUNBOOK.md':
                '# Build\n\n[n](../deploy/RUNBOOK.md#notes)\n',
          },
        ),
      );

      expect(
        plan.rewrites.map((rewrite) => rewrite.path),
        isNot(contains('docs/prds/runbooks/build/RUNBOOK.md')),
      );
    });

    test('a to doc that cannot be read refuses upgrade_collision naming both '
        'docs, and the run trashes no from doc', () async {
      final fixture = await _mergeFixture();
      File('${fixture.project.path}/docs/$_mergeToPath')
          .writeAsBytesSync([0xff, 0xfe, 0x00]);

      final fault = _refusedWith(() => _planMerge(fixture));

      expect(fault.code, MigrateFaultCode.upgradeCollision);
      expect(fault.file, _mergeToPath);
      expect(fault.message, contains(_mergeFromPath));
      expect(fault.message, contains(_mergeToPath));
    });

    for (final held in ['tasks: oops', 'tasks: [oops']) {
      test(
        'a to list field that is no list ($held) refuses '
        'upgrade_collision naming the doc, the field, and the from doc',
        () async {
          final fixture = await _mergeFixture(
            docs: {
              _mergeToPath: '---\n$held\n---\n# Deploy\n\n## Goals\n\nx\n',
              _mergeFromPath: _mergeFromDoc,
            },
          );

          final fault = _refusedWith(() => _planMerge(fixture));

          expect(fault.code, MigrateFaultCode.upgradeCollision);
          expect(fault.file, _mergeToPath);
          expect(fault.message, contains('tasks'));
          expect(fault.message, contains(_mergeFromPath));
        },
      );
    }

    test(
      'an unreadable to doc is listed with the other collisions at once',
      () async {
        final fixture = await _mergeFixture(
          docs: const {
            _mergeToPath: _mergeToDoc,
            _mergeFromPath: _mergeFromDoc,
            'prds/runbooks/build/RUNBOOK.md': '# Build\n\n## Procedure\n\nx\n',
            'prds/runbooks/build/PLAYBOOK.md': '# Build\n\n## Moves\n\nx\n',
          },
        );
        File('${fixture.project.path}/docs/$_mergeToPath')
            .writeAsBytesSync([0xff, 0xfe, 0x00]);

        final fault = _refusedWith(() => _planMerge(fixture));

        expect([
          fault.file,
          ...fault.more.map((f) => f.file),
        ], unorderedEquals([_mergeToPath, 'prds/runbooks/build/RUNBOOK.md']));
      },
    );

    test('a link in a from doc of another folder is rebased to reach its '
        'target from the to doc', () async {
      const packYaml = '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - merge_doc:
          from: {id: playbook, path: "prds/{slug}/PLAYBOOK.md"}
          to: runbook
          sections:
            - from: {id: moves, header: Moves}
              to: procedure
''';
      final plan = _planMerge(
        await _mergeFixture(
          packYaml: packYaml,
          docs: const {
            _mergeToPath: _mergeToDoc,
            'prds/deploy/PLAYBOOK.md':
                '# P\n\n## Moves\n\nSee [x](../ops/NOTES.md).\n',
          },
        ),
      );

      expect(
        _rewriteAt(plan, 'docs/$_mergeToPath').text,
        contains('See [x](../../ops/NOTES.md).'),
      );
    });

    test('a created to draft takes the later steps of the run and the layout '
        'pass', () async {
      final plan = _planMerge(
        await _mergeFixture(
          packYaml: _mergeRetrimPackYaml,
          docs: const {
            _mergeFromPath:
                '# Deploy playbook\n\n## Moves\n\nRun it.\n\n'
                '## Aims\n\nShip it.\n',
          },
        ),
      );

      expect(
        plan.creates.single.text,
        '---\ndraft: true\nretrim:\n  - procedure\n---\n\n'
        '# Deploy playbook\n\n## Goals\n\nShip it.\n\n'
        '## Procedure\n\nRun it.\n',
      );
    });

    test('a from doc the tree move leaves at the one-target path folds into '
        'the to doc the move carries to the first target', () async {
      final project = await writeTree({
        '.specstone/config.yaml': twinConfig(),
        'docs/prds/runbooks/deploy/RUNBOOK.md': _mergeToDoc,
        'docs/prds/runbooks/deploy/PLAYBOOK.md': _mergeFromDoc,
      });
      final home = (await _mergeFixture()).home;
      File('${home.path}/.specstone/packs/acme/runbook.yaml')
          .writeAsStringSync(_mergeTwinType);
      File('${project.path}/.specstone/config.yaml').writeAsStringSync(
        twinConfig().replaceFirst('packs:\n', 'packs:\n  acme: 1.0.0\n'),
      );

      final plan = _planMerge(_MergeFixture(project, home));

      expect(
        _rewriteAt(plan, 'docs/prds/flutter/runbooks/deploy/RUNBOOK.md').text,
        _mergedDoc,
      );
      expect(plan.trashedDocs, ['docs/prds/runbooks/deploy/PLAYBOOK.md']);
    });

    test('a lead in the from doc lands first in the first moved section with '
        'its relative link rebased', () async {
      const packYaml = '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - merge_doc:
          from: {id: playbook, path: "prds/{slug}/PLAYBOOK.md"}
          to: runbook
          sections:
            - from: {id: moves, header: Moves}
              to: procedure
''';
      final plan = _planMerge(
        await _mergeFixture(
          packYaml: packYaml,
          docs: const {
            _mergeToPath: _mergeToDoc,
            'prds/deploy/PLAYBOOK.md':
                '# P\n\nSee [x](../ops/NOTES.md).\n\n## Moves\n\nRun it.\n',
          },
        ),
      );

      expect(
        _rewriteAt(plan, 'docs/$_mergeToPath').text,
        contains('## Procedure\n\nSee [x](../../ops/NOTES.md).\n\nRun it.\n'),
      );
    });

    test('a from doc with a lead and no section refuses upgrade_collision '
        'naming the from doc, and the run trashes nothing', () async {
      final fixture = await _mergeFixture(
        docs: const {
          _mergeToPath: _mergeToDoc,
          _mergeFromPath: '# Deploy playbook\n\nAbout deploys.\n',
        },
      );

      final fault = _refusedWith(() => _planMerge(fixture));

      expect(fault.code, MigrateFaultCode.upgradeCollision);
      expect(fault.file, _mergeToPath);
      expect(fault.message, contains(_mergeFromPath));
    });

    test(
      'a from doc in a nested feature folder folds into the to doc of the same '
      'folder and leaves for the trash',
      () async {
        const toPath = 'specs/f01_a/f02_b/RUNBOOK.md';
        const fromPath = 'specs/f01_a/f02_b/PLAYBOOK.md';
        final plan = _planMerge(
          await _mergeFixture(
            packYaml: _nestedMergePackYaml,
            runbookType: _nestedMergeType,
            docs: const {
              'specs/f01_a/RUNBOOK.md': _mergeToDoc,
              'specs/f01_a/PLAYBOOK.md': _mergeFromDoc,
              toPath: _mergeToDoc,
              fromPath: _mergeFromDoc,
            },
          ),
        );

        expect(_rewriteAt(plan, 'docs/$toPath').text, _mergedDoc);
        expect(
          _rewriteAt(plan, 'docs/specs/f01_a/RUNBOOK.md').text,
          _mergedDoc,
        );
        expect(plan.trashedDocs, [
          'docs/specs/f01_a/PLAYBOOK.md',
          'docs/$fromPath',
        ]);
      },
    );

    test(
      'a to doc that already holds an entry does not take it twice',
      () async {
        final plan = _planMerge(
          await _mergeFixture(
            docs: const {
              _mergeToPath: '---\ntasks:\n  - Review\n---\n\n# Deploy\n\n## Goals\n\nShip it.\n',
              _mergeFromPath: _mergeFromDoc,
            },
          ),
        );

        expect(_rewriteAt(plan, 'docs/$_mergeToPath').text, _mergedDoc);
      },
    );
  });
}

void _relinkTests() {
  group('relink_merged_docs step', () {
    Future<RunPlan> planRelink(
      String toDoc, {
      Map<String, String> docs = const {},
    }) async => _plan(
      await _fixture(
        acmePin: '1.1.0',
        packYaml: _relinkPackYaml,
        runbookType: _mergeType,
        overrides: const {},
        docs: {_mergeToPath: toDoc, ...docs},
      ),
    );

    test('a block a move changed by a path mention alone keeps its confirmed entry suspect', () async {
      const storyPath = 'prds/features/f01_a/us01_b/USER_STORY.md';
      const frPath = 'prds/features/f01_a/us01_b/fr01_c.md';
      const scenario =
          '### Scenario 1 — [happy] one\n\n'
          '- **Given** `../../../runbooks/deploy/RUNBOOK.md`';
      final fixture = await _fixture(
        packYaml: '''
name: acme
version: 1.2.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - move_file: {doc_type: runbook, from: "prds/runbooks/{slug}/RUNBOOK.md", to: "ops/runbooks/{slug}/RUNBOOK.md"}
''',
        runbookType: _runbookType.replaceFirst(
          'prds/runbooks/{slug}/RUNBOOK.md',
          'ops/runbooks/{slug}/RUNBOOK.md',
        ),
        overrides: const {},
        docs: {
          'prds/runbooks/deploy/RUNBOOK.md': _runbookDoc,
          storyPath: '# B\n\n## Acceptance Criteria\n\n$scenario\n',
          frPath:
              '---\ntraced_from:\n  - S1\nconfirmed:\n'
              '  - S1 ${fingerprintOf(scenario)}\n---\n# C\n',
        },
      );

      final plan = _plan(fixture);

      expect(
        _rewriteAt(plan, 'docs/$storyPath').text,
        contains('`../../../../ops/runbooks/deploy/RUNBOOK.md`'),
      );
      expect(
        plan.rewrites.where(
          (rewrite) =>
              rewrite.path == 'docs/$frPath' &&
              !rewrite.text.contains('  - S1 ${fingerprintOf(scenario)}\n'),
        ),
        isEmpty,
      );
    });

    test('a relinked upstream leaves no confirmed entry suspect', () async {
      const storyPath = 'prds/features/f01_a/us01_b/USER_STORY.md';
      const frPath = 'prds/features/f01_a/us01_b/fr01_c.md';
      const scenario = '### Scenario 1 — [happy] one\n\n- **Given** ';
      const runbook = '(../../../runbooks/deploy/RUNBOOK.md)';
      const folded = '$scenario[playbook:deploy]$runbook';
      const relinked = '$scenario[runbook:deploy]$runbook';
      final plan = await planRelink(
        '# Deploy\n\n## Goals\n\nShip it.\n\n## Procedure\n\nRun it.\n',
        docs: {
          storyPath: '# B\n\n## Acceptance Criteria\n\n$folded\n',
          frPath:
              '---\ntraced_from:\n  - S1\nconfirmed:\n'
              '  - S1 ${fingerprintOf(folded)}\n---\n# C\n',
        },
      );

      expect(
        _rewriteAt(plan, 'docs/$storyPath').text,
        contains('[runbook:deploy]$runbook'),
      );
      expect(
        _rewriteAt(plan, 'docs/$frPath').text,
        contains('  - S1 ${fingerprintOf(relinked)}\n'),
      );
    });

    test(
      'the relink step retypes a self link a fold left in the to doc',
      () async {
        final plan = await planRelink(
          '# Deploy\n\n## Goals\n\nSee [playbook:deploy](RUNBOOK.md).\n\n'
          '## Procedure\n\nRun it.\n',
        );

        expect(
          _rewriteAt(plan, 'docs/$_mergeToPath').text,
          contains('See [runbook:deploy](#procedure).'),
        );
        expect(
          plan.toText(),
          contains('  from 1.1.0: relink_merged_docs: 1 docs\n'),
        );
        expect(
          plan.toText(),
          contains('  $_mergeToPath: links to merged docs\n'),
        );
      },
    );

    test(
      'the relink step rewrites no doc of a project whose links resolve',
      () async {
        final plan = await planRelink(
          '# Deploy\n\n## Goals\n\nSee [Procedure](#procedure).\n\n'
          '## Procedure\n\nRun it.\n',
        );

        expect(
          plan.rewrites.where(
            (rewrite) => rewrite.path == 'docs/$_mergeToPath',
          ),
          isEmpty,
        );
      },
    );

    test(
      'a run selecting the fold and the relink rewrites each link once',
      () async {
        const docs = {
          _mergeToPath:
              '# Deploy\n\n## Goals\n\nSee [playbook:deploy](PLAYBOOK.md).\n',
          _mergeFromPath: _mergeFromDoc,
        };
        final foldAlone = _planMerge(await _mergeFixture(docs: docs));
        final both = _planMerge(
          await _mergeFixture(docs: docs, packYaml: _relinkPackYaml),
        );

        final folded = _rewriteAt(foldAlone, 'docs/$_mergeToPath').text;
        expect(folded, contains('See [runbook:deploy](#procedure).'));
        expect(_rewriteAt(both, 'docs/$_mergeToPath').text, folded);
        expect(
          both.toText(),
          contains('  from 1.1.0: relink_merged_docs: 0 docs\n'),
        );
      },
    );
  });
}

/// The fault [plan] throws, or a failure when it plans.
MigrateFault _refusedWith(void Function() plan) {
  try {
    plan();
  } on MigrateFault catch (fault) {
    return fault;
  }
  fail('expected the plan to refuse');
}

const _regenPackYaml = '''
name: acme
version: 1.1.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - regenerate: {generators: [feature_catalog, area_catalog]}
''';

const _regenFeatureOnlyPackYaml = '''
name: acme
version: 1.1.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - regenerate: {generators: [feature_catalog]}
''';

const _areaIndexType = '''
id: area_index
description: One index per feature group.
path_from: feature_groups
file: AREA.md
generators: [area_catalog]
sections:
  - id: features
    header: Features
''';

const _acmeNoteType = '''
id: acme_note
description: A note kept beside the features.
path: prds/notes/{slug}.md
generators: [area_catalog]
sections:
  - id: features
    header: Features
''';

const _regenFeaturesPath = 'prds/FEATURES.md';
const _regenNotePath = 'prds/notes/a.md';
const _kitchenAreaPath = 'prds/features/kitchen/AREA.md';
const _pantryAreaPath = 'prds/features/pantry/AREA.md';
const _plainRecipes = 'prds/features/f01_recipes/FEATURE.md';

final String _featureOpen = generatedOpenMarker('feature_catalog');
final String _areaOpen = generatedOpenMarker('area_catalog');

/// A features doc whose catalog block holds [block].
String _regenFeaturesDoc(String block) =>
    '# Features\n\n## Features\n\n$_featureOpen\n$block\n'
    '$generatedEndMarker\n\n## System interaction diagram\n\n'
    '```mermaid\nflowchart LR\n  A --> B\n```\n\n## Systems\n\n'
    '| System | Description |\n|---|---|\n| S | d |\n';

/// An `area_index` or note doc whose block holds [rows], closed unless
/// [isOpen].
String _regenAreaDoc(String title, String rows, {bool isOpen = false}) =>
    '# $title\n\n## Features\n\n$_areaOpen\n$rows\n'
    '${isOpen ? '' : '$generatedEndMarker\n'}';

/// The `feature_catalog` and `area_catalog` kinds with fake text, and the
/// `area_index` docs `feature_catalog` keeps: one per group folder of a
/// feature, as `featureCatalogCompanions` lists them.
GeneratorRegistry<DocIndex> _regenRegistry() {
  List<String> featurePaths(DocIndex index) => [
    for (final doc in index.docs)
      if (doc.docTypeId == 'feature') doc.docPath,
  ];
  return GeneratorRegistry<DocIndex>(
    {
      'feature_catalog': (doc, docPath, type, index) => [
        GeneratedBlock(
          kind: 'feature_catalog',
          sectionId: 'features',
          place: const SectionTop(),
          text: 'features: ${featurePaths(index).length}',
        ),
      ],
      'area_catalog': (doc, docPath, type, index) => [
        GeneratedBlock(
          kind: 'area_catalog',
          sectionId: type.sections.first.id,
          place: const SectionTop(),
          text: 'rows of $docPath',
        ),
      ],
    },
    companions: {
      'feature_catalog': (docPath, type, index) {
        final slugs = {
          for (final path in featurePaths(index))
            if (path.split('/') case [_, _, final slug, _, _]) slug,
        }.toList()..sort();
        return CompanionDocs(
          docTypeId: slugs.isEmpty ? '' : 'area_index',
          docs: [
            for (final slug in slugs)
              CompanionDoc(
                docPath: 'prds/features/$slug/AREA.md',
                seedText: '# $slug\n\n## Features\n',
              ),
          ],
        );
      },
    },
  );
}

TemplateResolver _regenTemplates() => TemplateResolver(
  generatorKinds: {...shippedGeneratorKinds, 'area_catalog'},
);

/// A project and the personal pack home it pins `acme` in.
final class _RegenFixture {
  const new(this.project, this.home);

  final Directory project;
  final Directory home;
}

/// A project pinned to the personal pack `acme` at 1.0.0 whose home holds
/// 1.1.0, so `TemplateResolver.resolve` refuses its pin.
///
/// With [grouped] the `feature` path holds one group folder.
Future<_RegenFixture> _regenFixture({
  required Map<String, String> docs,
  String packYaml = _regenPackYaml,
  String noteType = _acmeNoteType,
  bool grouped = true,
}) async {
  final home = await writeTree({
    '.specstone/packs/acme/pack.yaml': packYaml,
    '.specstone/packs/acme/area_index.yaml': _areaIndexType,
    '.specstone/packs/acme/acme_note.yaml': noteType,
  });
  final project = await writeTree({
    '.specstone/config.yaml': _config('1.0.0'),
    if (grouped)
      '.specstone/templates/feature.yaml':
          'path: prds/features/{slug}/f{nn}_{slug}/FEATURE.md\n',
    for (final MapEntry(:key, :value) in docs.entries) 'docs/$key': value,
  });
  return _RegenFixture(project, home);
}

RunPlan _planRegen(
  _RegenFixture fixture, {
  required GeneratorRegistry<DocIndex> generators,
  RegenerationIndex? index,
}) => planUpgradeRun(
  fixture.project,
  templates: _regenTemplates(),
  homeDirectory: fixture.home,
  generators: generators,
  regenerationIndex: index,
);

/// [_regenRegistry] with each generator and companions call adding its index
/// to [seen], by identity.
GeneratorRegistry<DocIndex> _recordingRegistry(Set<DocIndex> seen) {
  final registry = _regenRegistry();
  return GeneratorRegistry<DocIndex>(
    {
      for (final kind in registry.kinds)
        kind: (doc, docPath, type, index) {
          seen.add(index);
          return registry[kind]!(doc, docPath, type, index);
        },
    },
    companions: {
      for (final kind in registry.kinds)
        if (registry.companionsOf(kind) case final companions?)
          kind: (docPath, type, index) {
            seen.add(index);
            return companions(docPath, type, index);
          },
    },
  );
}

const _kitchenRecipes = 'prds/features/kitchen/f01_recipes/FEATURE.md';
const _kitchenMenus = 'prds/features/kitchen/f02_menus/FEATURE.md';

/// The docs of a kitchen group with two top features, a fresh features doc,
/// and the [extra] docs.
Map<String, String> _kitchenDocs([Map<String, String> extra = const {}]) => {
  _kitchenRecipes: '# Recipes\n',
  _kitchenMenus: '# Menus\n',
  _regenFeaturesPath: _regenFeaturesDoc('features: 2'),
  ...extra,
};

void _regenerateTests() {
  group('regenerate step', () {
    test(
      'a regenerate step below the carried version plans its line',
      () async {
        final fixture = await _regenFixture(
          grouped: false,
          packYaml: _regenFeatureOnlyPackYaml,
          docs: {
            _plainRecipes: '# Recipes\n',
            _regenFeaturesPath: _regenFeaturesDoc('old'),
          },
        );

        await expectLater(
          () => _regenTemplates().resolve(
            workingDirectory: fixture.project,
            homeDirectory: fixture.home,
          ),
          throwsA(
            isA<TemplateFault>().having(
              (fault) => fault.code,
              'code',
              FaultCode.personalPackVersionDiffers,
            ),
          ),
        );
        final plan = _planRegen(fixture, generators: _regenRegistry());

        expect(
          plan.toText(),
          contains('  from 1.0.0: regenerate: feature_catalog: 1 docs\n'),
        );
        expect(plan.lists.toJson()['steps'], [
          {
            'from': '1.0.0',
            'step': 'regenerate: feature_catalog',
            'paths': [_regenFeaturesPath],
          },
        ]);
        expect(
          _docText(plan, fixture.project, _regenFeaturesPath),
          _regenFeaturesDoc('features: 1'),
        );
      },
    );

    test('a current features doc prints 0 docs and writes nothing', () async {
      final fixture = await _regenFixture(
        grouped: false,
        packYaml: _regenFeatureOnlyPackYaml,
        docs: {
          _plainRecipes: '# Recipes\n',
          _regenFeaturesPath: _regenFeaturesDoc('features: 1'),
        },
      );

      final plan = _planRegen(fixture, generators: _regenRegistry());

      expect(
        plan.toText(),
        contains('  from 1.0.0: regenerate: feature_catalog: 0 docs\n'),
      );
      expect(plan.lists.steps.single.paths, isEmpty);
      expect(
        _docText(plan, fixture.project, _regenFeaturesPath),
        _regenFeaturesDoc('features: 1'),
      );
      expect(plan.creates, isEmpty);
      expect(plan.trashedDocs, isEmpty);
    });

    test('a missing group doc is a commit 2 create listed in the step paths, '
        'approved with its block filled', () async {
      final fixture = await _regenFixture(docs: _kitchenDocs());

      final plan = _planRegen(fixture, generators: _regenRegistry());

      final create = plan.creates.single;
      expect(create.path, 'docs/$_kitchenAreaPath');
      expect(create.text, contains('rows of $_kitchenAreaPath'));
      expect(create.text, contains('approved: "'));
      expect(
        plan.toText(),
        contains('commit 2, creates:\n  $_kitchenAreaPath\n'),
      );
      expect(plan.lists.toJson()['steps'], [
        {
          'from': '1.0.0',
          'step': 'regenerate: feature_catalog, area_catalog',
          'paths': [_kitchenAreaPath],
        },
      ]);
      expect(
        plan.toText(),
        contains(
          '  from 1.0.0: regenerate: feature_catalog, area_catalog: 1 docs\n',
        ),
      );
    });

    test('a group doc whose folder holds no top feature is moved to the trash '
        'by commit 2, listed in the step paths and counted', () async {
      final fixture = await _regenFixture(
        docs: _kitchenDocs({
          _kitchenAreaPath: _regenAreaDoc(
            'kitchen',
            'rows of $_kitchenAreaPath',
          ),
          _pantryAreaPath: _regenAreaDoc('pantry', 'rows of $_pantryAreaPath'),
        }),
      );

      final plan = _planRegen(fixture, generators: _regenRegistry());

      expect(plan.trashedDocs, ['docs/$_pantryAreaPath']);
      expect(plan.lists.toJson()['steps'], [
        {
          'from': '1.0.0',
          'step': 'regenerate: feature_catalog, area_catalog',
          'paths': [_pantryAreaPath],
        },
      ]);
      expect(
        plan.toText(),
        contains(
          '  from 1.0.0: regenerate: feature_catalog, area_catalog: 1 docs\n',
        ),
      );
      expect(
        plan.rewrites.map((rewrite) => rewrite.path),
        isNot(contains('docs/$_pantryAreaPath')),
      );
      final steps = plan.journalSteps(
        base: 'abc',
        projectRoot: fixture.project,
      );
      expect(
        steps.whereType<MoveStep>().map((step) => step.from),
        contains('docs/$_pantryAreaPath'),
      );
      expect(
        steps.whereType<CommitStep>().single.paths,
        contains('docs/$_pantryAreaPath'),
      );
    });

    test('an unclosed area_catalog marker in one group doc refuses the run '
        'as an upgrade_collision naming the doc and the open block', () async {
      final fixture = await _regenFixture(
        docs: _kitchenDocs({
          _regenFeaturesPath: _regenFeaturesDoc('old'),
          _kitchenAreaPath: _regenAreaDoc('kitchen', 'old', isOpen: true),
          _regenNotePath: _regenAreaDoc('A', 'old'),
        }),
      );

      final fault = _refusedWith(
        () => _planRegen(fixture, generators: _regenRegistry()),
      );

      expect(fault.code, MigrateFaultCode.upgradeCollision);
      expect(fault.file, _kitchenAreaPath);
      expect(
        fault.message,
        'regenerate cannot write docs/$_kitchenAreaPath: open generated '
        'block area_catalog; make the doc one format accepts, then run '
        'specstone migrate again',
      );
      expect(fault.more, isEmpty);
    });

    test('a features doc with an owner-added header refuses the run as an '
        'upgrade_collision naming the doc and the header', () async {
      final fixture = await _regenFixture(
        docs: _kitchenDocs({
          _regenFeaturesPath: '${_regenFeaturesDoc('old')}\n## Notes\n\nmine\n',
        }),
      );

      final fault = _refusedWith(
        () => _planRegen(fixture, generators: _regenRegistry()),
      );

      expect(fault.code, MigrateFaultCode.upgradeCollision);
      expect(fault.file, _regenFeaturesPath);
      expect(
        fault.message,
        'regenerate cannot write docs/$_regenFeaturesPath: unknown header '
        '"## Notes"; make the doc one format accepts, then run specstone '
        'migrate again',
      );
    });

    test('a refused doc whose type lists no kind of the step leaves the plan '
        'standing', () async {
      final fixture = await _regenFixture(
        docs: _kitchenDocs({_kitchenRecipes: '# Recipes\n\n## Mystery\n\nx\n'}),
      );

      final plan = _planRegen(fixture, generators: _regenRegistry());

      expect(plan.creates.single.path, 'docs/$_kitchenAreaPath');
    });

    test('two plans sharing one RegenerationIndex read their generators from '
        'one index, and a plan with none builds its own', () async {
      final seen = <DocIndex>{};
      final fixture = await _regenFixture(docs: _kitchenDocs());
      final index = RegenerationIndex();
      addTearDown(index.close);

      _planRegen(fixture, generators: _recordingRegistry(seen), index: index);
      final shown = seen.length;
      _planRegen(fixture, generators: _recordingRegistry(seen), index: index);

      expect(shown, 1);
      expect(seen, hasLength(1));
      _planRegen(fixture, generators: _recordingRegistry(seen));
      expect(seen, hasLength(2));
    });

    test('planning the dry run leaves no index file and no new .gitignore '
        'under .specstone', () async {
      final fixture = await _regenFixture(
        docs: _kitchenDocs({
          _pantryAreaPath: _regenAreaDoc('pantry', 'rows of $_pantryAreaPath'),
        }),
      );
      final specstone = '${fixture.project.path}/.specstone';
      final before = Directory(specstone)
          .listSync(recursive: true)
          .map((entity) => entity.path)
          .toSet();

      _planRegen(fixture, generators: _regenRegistry());

      expect(
        Directory(specstone)
            .listSync(recursive: true)
            .map((entity) => entity.path)
            .toSet(),
        before,
      );
      expect(File('$specstone/index.sqlite').existsSync(), isFalse);
      expect(File('$specstone/.gitignore').existsSync(), isFalse);
    });

    test('a regenerate naming a kind the registry lacks throws a StateError '
        'before the plan prints', () async {
      final fixture = await _regenFixture(
        grouped: false,
        packYaml: _regenFeatureOnlyPackYaml,
        docs: {
          _plainRecipes: '# Recipes\n',
          _regenFeaturesPath: _regenFeaturesDoc('old'),
        },
      );

      expect(
        () => _planRegen(fixture, generators: GeneratorRegistry({})),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('feature_catalog'),
          ),
        ),
      );
    });

    test('a doc a step of the same run reshapes gets its block filled and is '
        'listed and counted by the regenerate step', () async {
      const reshaped = '''
id: acme_note
description: A note kept beside the features.
path: prds/notes/{slug}.md
generators: [area_catalog]
sections:
  - id: rows
    header: Rows
''';
      const packYaml = '''
name: acme
version: 1.1.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - rename_section: {doc_type: acme_note, from: {id: features, header: Features}, to: {id: rows, header: Rows}}
      - regenerate: {generators: [area_catalog]}
''';
      final fixture = await _regenFixture(
        grouped: false,
        packYaml: packYaml,
        noteType: reshaped,
        docs: {_regenNotePath: _regenAreaDoc('A', 'old')},
      );

      final plan = _planRegen(fixture, generators: _regenRegistry());

      expect(
        plan.toText(),
        contains('  from 1.0.0: regenerate: area_catalog: 1 docs\n'),
      );
      expect(plan.lists.steps.last.paths, [_regenNotePath]);
      // The regenerate step reads the doc after the rename in a probe that
      // records no change, so the rename step lists the doc once.
      expect(
        plan.toText(),
        contains('  from 1.0.0: rename_section acme_note features -> rows: '),
      );
      expect(plan.lists.steps.first.paths, [_regenNotePath]);
      expect(plan.lists.steps.first.text, endsWith(': 1 docs'));
      expect(
        _docText(plan, fixture.project, _regenNotePath),
        _regenAreaDoc(
          'A',
          'rows of $_regenNotePath',
        ).replaceFirst('## Features', '## Rows'),
      );
    });

    test('a regenerate step counts and lists the catalog and the group '
        'features docs it creates and deletes', () async {
      const formDoc = 'prds/features/form/FEATURES.md';
      const oldDoc = 'prds/features/old/FEATURES.md';
      const packYaml = '''
name: acme
version: 1.1.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - regenerate: {generators: [feature_catalog, group_feature_catalog]}
''';
      final groupOpen = generatedOpenMarker('group_feature_catalog');
      final fixture = _RegenFixture(
        await writeTree({
          '.specstone/config.yaml': _config('1.0.0'),
          '.specstone/templates/feature.yaml':
              'path: prds/features/{slug}/f{nn}_{slug}/FEATURE.md\n',
          'docs/$_regenFeaturesPath': _regenFeaturesDoc('stale'),
          'docs/prds/features/form/f01_input/FEATURE.md': '# Input\n',
          'docs/$oldDoc':
              '# old features\n\n## Features\n\n$groupOpen\nstale\n'
              '$generatedEndMarker\n',
        }),
        await writeTree({'.specstone/packs/acme/pack.yaml': packYaml}),
      );

      final plan = _planRegen(fixture, generators: shippedGenerators());

      final step = plan.lists.steps.single;
      expect(step.paths, [_regenFeaturesPath, formDoc, oldDoc]);
      expect(
        step.text,
        'from 1.0.0: regenerate: feature_catalog, group_feature_catalog: '
        '3 docs',
      );
      final create = plan.creates.single;
      expect(create.path, 'docs/$formDoc');
      expect(create.note, '');
      expect(plan.trashedDocs, ['docs/$oldDoc']);
      expect(plan.toText(), contains('commit 2, creates:\n  $formDoc\n'));
      expect(plan.toText(), isNot(contains('(draft)')));
    });
  });
}
