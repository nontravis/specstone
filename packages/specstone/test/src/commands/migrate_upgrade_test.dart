@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/document_writing/approval.dart'
    show withApprovalHash;
import 'package:specstone_core/src/index_query/index_store.dart'
    show specstoneGitignoreLines;
import 'package:specstone_core/src/setup_migration/agent_files.dart'
    show agentMdText, importBlock;
import 'package:specstone_core/src/templates/shipped_pack_files.dart'
    show shippedPackVersions;
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/git_repo.dart';
import '../../../../specstone_core/test/helpers/legacy_fixture.dart';
import '../../../../specstone_core/test/helpers/posix_modes.dart';
import '../../../../specstone_core/test/helpers/record_fixture.dart'
    show twinConfig;
import '../../../../specstone_core/test/helpers/shipped_pins.dart';
import '../../../../specstone_core/test/helpers/skill_files.dart';
import '../../../../specstone_core/test/helpers/temp_tree.dart';
import '../../../../specstone_core/test/helpers/write_fixture.dart'
    show testHome;
import '../../helpers/built_cli.dart';
import '../../helpers/write_runner.dart';

const _gitignore = '.specstone/.gitignore';
final _ignoreFile = '${specstoneGitignoreLines.join('\n')}\n';
const _threeLineIgnoreFile = 'index.sqlite*\nbuild/\ntrash/\n';
const _overridePath = '.specstone/templates/runbook.yaml';
const _runbookPath = 'docs/prds/runbooks/deploy/RUNBOOK.md';

const _runbookDoc = '''
---
owner: sre
---
# Deploy

## Steps

Run it.
''';

const _renameMigrations = '''
migrations:
  - from: 1.0.0
    steps:
      - rename_section: {doc_type: runbook, from: {id: steps, header: Steps}, to: {id: procedure, header: Procedure}}
  - from: 1.1.0
    steps:
      - rename_field: {doc_type: runbook, from: owner, to: on_call}
''';

const _moveMigrations = '''
migrations:
  - from: 1.0.0
    steps:
      - move_file: {doc_type: runbook, from: "prds/runbooks/{slug}/RUNBOOK.md", to: "ops/runbooks/{slug}/RUNBOOK.md"}
''';

const _swapMigrations = '''
migrations:
  - from: 1.0.0
    steps:
      - move_file: {doc_type: runbook, from: "prds/runbooks/{slug}/RUNBOOK.md", to: "prds/runbooks/{slug}/NOTES.md"}
      - move_file: {doc_type: runbook, from: "prds/runbooks/{slug}/NOTES.md", to: "prds/runbooks/{slug}/RUNBOOK.md"}
''';

const _collideMigrations = '''
migrations:
  - from: 1.0.0
    steps:
      - move_file: {doc_type: runbook, from: "prds/runbooks/{slug}/RUNBOOK.md", to: "prds/runbooks/{slug}/PLAYBOOK.md"}
''';

/// Moves a doc onto the path the next step's doc leaves.
const _chainMigrations = '''
migrations:
  - from: 1.0.0
    steps:
      - move_file: {doc_type: runbook, from: "prds/ops/{slug}/RUNBOOK.md", to: "prds/runbooks/{slug}/RUNBOOK.md"}
      - move_file: {doc_type: runbook, from: "prds/runbooks/{slug}/NOTES.md", to: "prds/ops/{slug}/RUNBOOK.md"}
''';

/// Swaps RUNBOOK.md and NOTES.md through a temporary name, so the two docs
/// trade places.
const _rotationMigrations = '''
migrations:
  - from: 1.0.0
    steps:
      - move_file: {doc_type: runbook, from: "prds/runbooks/{slug}/RUNBOOK.md", to: "prds/runbooks/{slug}/TMP.md"}
      - move_file: {doc_type: runbook, from: "prds/runbooks/{slug}/NOTES.md", to: "prds/runbooks/{slug}/RUNBOOK.md"}
      - move_file: {doc_type: runbook, from: "prds/runbooks/{slug}/TMP.md", to: "prds/runbooks/{slug}/NOTES.md"}
''';

const _heldRenamedMigrations = '''
migrations:
  - from: 1.0.0
    steps:
      - rename_section: {doc_type: runbook, from: {id: steps, header: Steps}, to: {id: procedure, header: Procedure}}
  - from: 1.1.0
    steps:
      - rename_field: {doc_type: runbook, from: owner, to: on_call}
''';

String _pack(String version, String migrations) =>
    'name: acme\nversion: $version\nextends: software-tech\n$migrations';

String _runbookType(String path, String sectionId) =>
    '''
id: runbook
description: A runbook.
path: $path
fields:
  - {id: on_call, type: string}
sections:
  - {id: $sectionId, header: Steps, required: true}
''';

String _config(String acmePin) => '${shippedPinsConfig()}  acme: $acmePin\n';

/// The key every run that writes the config sets: the running Version.
const _stamp = 'agent_files_version: $specstoneVersion\n';

/// The temp personal-pack home holding `acme`.
Future<Directory> _home({
  String version = '1.2.0',
  String migrations = _renameMigrations,
  String type = '',
  String typeFile = 'runbook',
}) => writeTree({
  '.specstone/packs/acme/pack.yaml': _pack(version, migrations),
  '.specstone/packs/acme/$typeFile.yaml': type.isEmpty
      ? _runbookType('prds/runbooks/{slug}/RUNBOOK.md', 'procedure')
      : type,
});

/// A git project pinning `acme` at [pin], with the ignore file committed.
Future<Directory> _project({
  String pin = '1.0.0',
  Map<String, String> files = const {
    _runbookPath: _runbookDoc,
    _overridePath: 'sections: [{id: steps, required: true}]\n',
  },
}) => gitFixture({
  '.specstone/config.yaml': _config(pin),
  _gitignore: _ignoreFile,
  ...files,
});

FakeConsole _owner() =>
    FakeConsole(stdinIsTerminal: true, stdoutIsTerminal: true, answers: ['y']);

/// Runs [args] in [root] against the personal pack [home].
Future<({int status, String out, String err})> _run(
  Directory root,
  Directory home,
  List<String> args, {
  FakeConsole? console,
}) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final runner = SpecstoneCommandRunner(
    out: out,
    err: err,
    templates: TemplateResolver(),
    workingDirectory: root,
    homeDirectory: home,
    console: console ?? FakeConsole(),
  );
  final status = await runner.run(args);
  return (status: status, out: out.toString(), err: err.toString());
}

/// The `kind` of each finding in [checkJson], those at [docPath] alone when
/// given.
Set<String> _findingKinds(String checkJson, {String? docPath}) => {
  for (final finding
      in (jsonDecode(checkJson) as Map<String, Object?>)['findings']!
          as List<Object?>)
    if (finding case {'kind': final String kind, 'path': final Object? path})
      if (docPath == null || path == docPath) kind,
};

String _gitOut(Directory root, List<String> args) =>
    git(root, args).stdout as String;

List<String> _subjects(Directory root) =>
    _gitOut(root, ['log', '--format=%s']).trim().split('\n');

String _head(Directory root) => _gitOut(root, ['rev-parse', 'HEAD']).trim();

String _read(Directory root, String path) =>
    File('${root.path}/$path').readAsStringSync();

/// Installs a commit-msg hook that refuses commit 2, so a run stops after
/// commit 1; returns the hook, to delete before the resume.
File _refuseCommit2(Directory root) {
  final hook = File('${root.path}/.git/hooks/commit-msg')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      '#!/bin/sh\ngrep -q "upgrade pack pins" "\$1" && exit 1\nexit 0\n',
    );
  expect(Process.runSync('chmod', ['755', hook.path]).exitCode, 0);
  return hook;
}

Map<String, String> _bytesUnder(Directory root) => {
  for (final entity in root.listSync(recursive: true, followLinks: false))
    if (entity is File &&
        !entity.path.contains(
          '${Platform.pathSeparator}.git${Platform.pathSeparator}',
        ))
      entity.path: entity.readAsStringSync(),
};

/// Matches output that ends with [commitLine], then the closing count line.
Matcher _endingWith(String commitLine) => matches(
  RegExp(
    '${RegExp.escape(commitLine)}'
    r'check: \d+ findings left; run specstone check to see them\n$',
  ),
);

const _bulletMigrations = '''
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

const _bulletDoc =
    '# Deploy\n\n## Goals\n\n**Serves:** PV-01\n- **By:** v1\n\n'
    '## Notes\n\n**Serves:** kept\n';
const _bulletedDoc =
    '# Deploy\n\n## Goals\n\n- **Serves:** PV-01\n- **By:** v1\n\n'
    '## Notes\n\n**Serves:** kept\n';

void main() {
  group('bullet_lines step', () {
    test('bare migrate writes the bullet lines in commit 2 and changes '
        'nothing else, and --dry-run writes nothing', () async {
      final home = await _home(
        migrations: _bulletMigrations,
        type: _bulletType,
      );
      final root = await _project(files: {_runbookPath: _bulletDoc});
      final before = _bytesUnder(root);

      final dry = await _run(root, home, ['migrate', '--dry-run']);

      expect(dry.status, 0, reason: dry.err);
      expect(
        dry.out,
        contains('  from 1.0.0: bullet_lines runbook goals: 1 docs\n'),
      );
      expect(_bytesUnder(root), before);
      final subjects = _subjects(root);

      final result = await _run(root, home, ['migrate'], console: _owner());

      expect(result.status, 0, reason: result.err);
      expect(_subjects(root), hasLength(subjects.length + 1));
      expect(_read(root, _runbookPath), _bulletedDoc);
      expect(
        _gitOut(root, [
          'show',
          '--name-only',
          '--format=',
          'HEAD',
        ]).trim().split('\n').toSet(),
        {'.specstone/config.yaml', _runbookPath},
      );
      expect(_gitOut(root, ['status', '--porcelain']).trim(), isEmpty);
    });

    test('a step the pack load refuses stops bare migrate and --dry-run '
        'with exit 78 and writes nothing', () async {
      final home = await _home(
        migrations: _bulletMigrations.replaceFirst(
          'section: goals',
          'section: nope',
        ),
        type: _bulletType,
      );
      final root = await _project(files: {_runbookPath: _bulletDoc});
      final before = _bytesUnder(root);
      final head = _head(root);

      for (final args in [
        ['migrate', '--dry-run'],
        ['migrate'],
      ]) {
        final result = await _run(root, home, args, console: _owner());

        expect(result.status, 78, reason: args.join(' '));
        expect(result.err, contains('bullet_lines.section'));
        expect(result.out, isEmpty, reason: args.join(' '));
      }
      expect(_bytesUnder(root), before);
      expect(_head(root), head);
    });
  });
  group('mark_retrim step', () {
    const migrations = '''
migrations:
  - from: 1.0.0
    steps:
      - mark_retrim: {doc_types: [fr], sections: [edge_cases, verification]}
''';
    const frType = '''
id: fr
description: An FR.
path: prds/features/f{nn}_{slug}/us{nn}_{slug}/fr{nn}_{slug}.md
fields:
  - {id: traced_from, type: string, list: true, required: true}
sections:
  - {id: statement, header: Statement, required: true}
  - {id: edge_cases, header: Edge cases, required: true}
  - {id: rationale, header: Rationale, required: true}
  - {id: verification, header: Verification, required: true}
''';

    /// The merged `fr` type of the acme pack: the shipped one with the test's
    /// sections, as `withApprovalHash` hashes it.
    MergedDocType acmeFrType() => switch (DocTypeMatcher(
      TemplateResolver().resolveCarried(
        packNames: const ['prd-core', 'software-tech'],
        homeDirectory: null,
      ),
      targetNames: const [],
    ).match('prds/features/f01_login/us01_email_login/fr01_validate.md')) {
      MatchedDocType(:final docType) => docType,
      _ => throw StateError('no doc type matches the fr path'),
    };

    String storyWithScenario() =>
        '# Email login\n\n## Acceptance Criteria\n\n'
        '### Scenario 1 — [happy] Sign in\n\n- **Given** an account\n';
    const frPath =
        'docs/prds/features/f01_login/us01_email_login/fr01_validate.md';
    const featurePath = 'docs/prds/features/f01_login/FEATURE.md';
    const storyPath =
        'docs/prds/features/f01_login/us01_email_login/USER_STORY.md';
    const frBody =
        '# Validate\n\n'
        '## Statement\n\nThe system shall refuse a wrong password.\n\n'
        '## Edge cases\n\n1. E01 — An empty password → refused.\n\n'
        '## Rationale\n\nA wrong password must not sign in.\n\n'
        '## Verification\n\nTest: a wrong password is refused.\n';
    final frApproved = withApprovalHash(
      '---\ntraced_from: [S1]\n---\n\n$frBody',
      acmeFrType(),
    );

    test('an upgrade with a mark_retrim entry marks FRs in commit 2 and '
        'counts them on its plan line', () async {
      final home = await _home(
        migrations: migrations,
        type: frType,
        typeFile: 'fr',
      );
      final root = await _project(
        files: {
          frPath: frApproved,
          featurePath: '# Login\n',
          storyPath: storyWithScenario(),
        },
      );
      final before = _bytesUnder(root);

      final dry = await _run(root, home, ['migrate', '--dry-run', '--json']);

      expect(dry.status, 0, reason: dry.err);
      final plan = jsonDecode(dry.out) as Map<String, Object?>;
      expect(plan['steps'], [
        {
          'from': '1.0.0',
          'step': 'mark_retrim',
          'paths': [frPath.substring('docs/'.length)],
        },
      ]);
      expect(_bytesUnder(root), before);
      final subjects = _subjects(root);

      final result = await _run(root, home, ['migrate'], console: _owner());

      expect(result.status, 0, reason: result.err);
      expect(result.out, contains('  from 1.0.0: mark_retrim: 1 docs\n'));
      expect(_subjects(root), hasLength(subjects.length + 1));
      expect(
        _read(root, frPath),
        withApprovalHash(
          '---\nretrim:\n  - edge_cases\n  - verification\n'
          'traced_from: [S1]\n---\n\n$frBody',
          acmeFrType(),
        ),
      );
      expect(_gitOut(root, ['status', '--porcelain']).trim(), isEmpty);
      final check = await _run(root, home, ['check', '--json']);
      final kinds = _findingKinds(
        check.out,
        docPath: 'prds/features/f01_login/us01_email_login/fr01_validate.md',
      );
      expect(kinds, contains('retrim_due'));
      expect(kinds, isNot(contains('approval_stale')));
    });
  });
  group('drop_section step', () {
    const migrations = '''
migrations:
  - from: 1.0.0
    steps:
      - drop_section: {doc_types: [runbook], section: {id: legacy, header: Legacy}}
''';
    const before =
        '---\non_call: sre\n---\n# Deploy steps\n\n## Procedure\n\nRun it.\n\n'
        '## Legacy\n\nOld.\n';
    const after =
        '---\non_call: sre\n---\n# Deploy steps\n\n## Procedure\n\nRun it.\n';
    const type = '''
id: runbook
description: A runbook.
path: prds/runbooks/{slug}/RUNBOOK.md
fields:
  - {id: on_call, type: string}
sections:
  - {id: procedure, header: Procedure, required: true}
''';

    test('a release that drops a section removes it and prints its step '
        'line', () async {
      final home = await _home(migrations: migrations, type: type);
      final root = await _project(files: {_runbookPath: before});
      final bytes = _bytesUnder(root);

      final dry = await _run(root, home, ['migrate', '--dry-run']);

      expect(dry.status, 0, reason: dry.err);
      expect(
        dry.out,
        contains('  from 1.0.0: drop_section runbook legacy: 1 docs\n'),
      );
      expect(_bytesUnder(root), bytes);
      final subjects = _subjects(root);

      final result = await _run(root, home, ['migrate'], console: _owner());

      expect(result.status, 0, reason: result.err);
      expect(
        result.out,
        contains('  from 1.0.0: drop_section runbook legacy: 1 docs\n'),
      );
      expect(_subjects(root), hasLength(subjects.length + 1));
      expect(_read(root, _runbookPath), after);
      expect(_gitOut(root, ['status', '--porcelain']).trim(), isEmpty);
      final check = await _run(root, home, ['check', '--json']);
      // The doc never carried an approval, so only the Owner's wait is left.
      expect(
        _findingKinds(
          check.out,
          docPath: _runbookPath.substring('docs/'.length),
        ),
        {'approval_stale'},
      );
    });
  });
  group('regenerate step', () {
    const migrations = '''
migrations:
  - from: 1.0.0
    steps:
      - regenerate: {generators: [feature_catalog]}
''';
    const featuresPath = 'docs/prds/FEATURES.md';
    const featurePath = 'docs/prds/features/f01_recipes/FEATURE.md';
    final open = generatedOpenMarker('feature_catalog');
    String featuresDoc(String block) =>
        '# Features\n\n## Features\n\n$open\n$block\n'
        '$generatedEndMarker\n\n## System interaction diagram\n\n'
        '```mermaid\nflowchart LR\n  A --> B\n```\n\n## Systems\n\n'
        '| System | Description |\n|---|---|\n| S | d |\n';

    test('bare migrate writes the stale features catalog in commit 2 under '
        'a pin the carried version refuses', () async {
      final home = await _home(version: '1.1.0', migrations: migrations);
      final root = await _project(
        files: {featuresPath: featuresDoc('old'), featurePath: '# Recipes\n'},
      );
      final subjects = _subjects(root);

      final result = await _run(root, home, ['migrate'], console: _owner());

      expect(result.status, 0, reason: result.err);
      expect(
        result.out,
        contains('  from 1.0.0: regenerate: feature_catalog: 1 docs\n'),
      );
      expect(_subjects(root), hasLength(subjects.length + 1));
      final features = _read(root, featuresPath);
      expect(features, isNot(contains('\nold\n')));
      expect(features, contains('features/f01_recipes/FEATURE.md'));
      expect(_gitOut(root, ['status', '--porcelain']).trim(), isEmpty);
    });

    test('a features doc the write refuses stays as it was, the plan prints '
        '0 docs and warns naming the doc', () async {
      final home = await _home(version: '1.1.0', migrations: migrations);
      final refused = '${featuresDoc('old')}\n## Notes\n\nmine\n';
      final root = await _project(
        files: {featuresPath: refused, featurePath: '# Recipes\n'},
      );

      final result = await _run(root, home, ['migrate'], console: _owner());

      expect(result.status, 0, reason: result.err);
      expect(
        result.out,
        contains('  from 1.0.0: regenerate: feature_catalog: 0 docs\n'),
      );
      expect(
        result.err,
        contains(
          'WARNING: $featuresPath cannot be written by regenerate: unknown '
          'header "## Notes"; left as it was',
        ),
      );
      expect(_read(root, featuresPath), refused);
      expect(_gitOut(root, ['status', '--porcelain']).trim(), isEmpty);
    });

    test('a prd-core 1.31.0 pin in a grouped project regenerates the catalog '
        'and creates the group features doc approved', () async {
      const catalogLine =
          '  from 1.31.0: regenerate: feature_catalog, '
          'group_feature_catalog: 2 docs\n';
      const groupPath = 'prds/features/form/FEATURES.md';
      final shippedCore = shippedPackVersions()['prd-core'];
      final pins = shippedPinsConfig().replaceFirst(
        '  prd-core: $shippedCore\n',
        '  prd-core: 1.31.0\n',
      );
      final featuresType = TemplateResolver()
          .resolveCarried(
            packNames: const ['prd-core', 'software-tech'],
            homeDirectory: null,
          )
          .lookup('features');
      final root = await gitFixture({
        '.specstone/config.yaml': '$pins$_stamp',
        _gitignore: _ignoreFile,
        '.specstone/templates/feature.yaml':
            'path: prds/features/{slug}/f{nn}_{slug}/FEATURE.md\n',
        featuresPath: withApprovalHash(
          featuresDoc(
            '1 features · 0 stories · 0 implemented, 0 planned\n\n'
            '| Feature | What it does | Status | Stories | Serves |\n'
            '|---|---|---|---|---|\n'
            '| [Input](features/form/f01_input/FEATURE.md) | — | planned '
            '| 0/0 | — |',
          ).replaceFirst('# Features\n', '# Feature map\n'),
          featuresType,
        ),
        'docs/prds/features/form/f01_input/FEATURE.md': '# Input\n',
      });
      final home = await writeTree({});
      final bytes = _bytesUnder(root);

      final dry = await _run(root, home, ['migrate', '--dry-run']);

      expect(dry.status, 0, reason: dry.err);
      expect(dry.out, contains(catalogLine));
      expect(_bytesUnder(root), bytes);
      final json = await _run(root, home, ['migrate', '--dry-run', '--json']);
      final steps =
          (jsonDecode(json.out) as Map<String, Object?>)['steps']!
              as List<Object?>;
      expect(
        steps,
        contains(
          isA<Map<String, Object?>>().having((step) => step['paths'], 'paths', [
            'prds/FEATURES.md',
            groupPath,
          ]),
        ),
      );
      expect(_bytesUnder(root), bytes);
      final subjects = _subjects(root);

      final result = await _run(root, home, ['migrate'], console: _owner());

      expect(result.status, 0, reason: result.err);
      expect(result.out, contains(catalogLine));
      expect(result.out, contains('commit 2, creates:\n  $groupPath\n'));
      expect(result.out, isNot(contains('(draft)')));
      expect(_subjects(root), hasLength(subjects.length + 1));
      expect(_gitOut(root, ['status', '--porcelain']).trim(), isEmpty);
      final group = _read(root, 'docs/$groupPath');
      expect(group, contains('approved:'));
      expect(group, isNot(contains('draft: true')));
      final check = await _run(root, home, ['check', '--json']);
      for (final path in [groupPath, 'prds/FEATURES.md']) {
        expect(
          _findingKinds(check.out, docPath: path),
          isNot(contains('approval_stale')),
          reason: path,
        );
      }
    });

    test('a prd-core 1.31.0 pin with two group levels creates the doc of '
        'each level approved and links each row to its doc', () async {
      const formPath = 'prds/features/form/FEATURES.md';
      const inputPath = 'prds/features/form/input/FEATURES.md';
      final shippedCore = shippedPackVersions()['prd-core'];
      final pins = shippedPinsConfig().replaceFirst(
        '  prd-core: $shippedCore\n',
        '  prd-core: 1.31.0\n',
      );
      final root = await gitFixture({
        '.specstone/config.yaml': '$pins$_stamp',
        _gitignore: _ignoreFile,
        '.specstone/templates/feature.yaml':
            'path: prds/features/{slug}/{slug}/f{nn}_{slug}/FEATURE.md\n',
        featuresPath: featuresDoc('old'),
        'docs/prds/features/form/input/f01_text/FEATURE.md': '# Text\n',
        'docs/prds/features/form/input/f02_select/FEATURE.md': '# Select\n',
      });
      final home = await writeTree({});
      final subjects = _subjects(root);

      final result = await _run(root, home, ['migrate'], console: _owner());

      expect(result.status, 0, reason: result.err);
      expect(
        result.out,
        contains(
          '  from 1.31.0: regenerate: feature_catalog, '
          'group_feature_catalog: 3 docs\n',
        ),
      );
      expect(
        result.out,
        contains('commit 2, creates:\n  $formPath\n  $inputPath\n'),
      );
      expect(_subjects(root), hasLength(subjects.length + 1));
      expect(_gitOut(root, ['status', '--porcelain']).trim(), isEmpty);
      for (final path in [formPath, inputPath]) {
        final text = _read(root, 'docs/$path');
        expect(text, contains('approved: "'), reason: path);
        expect(text, isNot(contains('draft: true')), reason: path);
      }
      expect(
        _read(root, 'docs/$formPath'),
        contains('| [input](input/FEATURES.md) | 2 | 2 planned | 0/0 |'),
      );
      expect(
        _read(root, 'docs/$inputPath'),
        contains(
          '| [Text](f01_text/FEATURE.md) | — | planned | 0/0 | — |\n'
          '| [Select](f02_select/FEATURE.md) | — | planned | 0/0 | — |',
        ),
      );
      expect(
        _read(root, featuresPath),
        contains('| [form](features/form/FEATURES.md) | 2 | 2 planned | 0/0 |'),
      );
      final check = await _run(root, home, ['check', '--json']);
      for (final path in [formPath, inputPath]) {
        expect(
          _findingKinds(check.out, docPath: path),
          isNot(contains('approval_stale')),
          reason: path,
        );
      }
    });
  });
  group('merge_doc step', () {
    const migrations = '''
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
    const type = '''
id: runbook
description: A runbook.
path: prds/runbooks/{slug}/RUNBOOK.md
fields:
  - {id: on_call, type: string}
sections:
  - {id: goals, header: Goals}
  - {id: procedure, header: Procedure}
''';
    const playbookPath = 'docs/prds/runbooks/deploy/PLAYBOOK.md';
    const toText = '---\non_call: sre\n---\n# Deploy\n\n## Goals\n\nShip it.\n';
    const playbook = '# Deploy playbook\n\n## Moves\n\nRun it.\n';
    const merged =
        '---\non_call: sre\n---\n# Deploy\n\n## Goals\n\nShip it.\n\n'
        '## Procedure\n\nRun it.\n';
    const layerPath = '.specstone/templates/playbook.yaml';

    test('a run folds the sections into the to doc, moves the from file out '
        'of the docs, keeps the layer file, and prints both lines', () async {
      final home = await _home(migrations: migrations, type: type);
      final root = await _project(
        files: {
          _runbookPath: toText,
          playbookPath: playbook,
          layerPath: 'sections: []\n',
        },
      );
      final bytes = _bytesUnder(root);

      final dry = await _run(root, home, ['migrate', '--dry-run']);

      expect(dry.status, 0, reason: dry.err);
      expect(
        dry.out,
        contains(
          '  from 1.0.0: merge_doc playbook -> runbook: 1 docs\n'
          '  layers kept: 1\n',
        ),
      );
      expect(_bytesUnder(root), bytes);
      final subjects = _subjects(root);

      final result = await _run(root, home, ['migrate'], console: _owner());

      expect(result.status, 0, reason: result.err);
      expect(_subjects(root), hasLength(subjects.length + 1));
      expect(_read(root, _runbookPath), merged);
      expect(File('${root.path}/$playbookPath').existsSync(), isFalse);
      expect(_read(root, layerPath), 'sections: []\n');
      expect(_gitOut(root, ['status', '--porcelain']).trim(), isEmpty);
    });

    test('a to doc approved before the run is stamped again, so check '
        'reports no approval_stale on it', () async {
      final home = await _home(migrations: migrations, type: type);
      final runbookType = TemplateResolver()
          .resolveCarried(
            packNames: const ['prd-core', 'software-tech', 'acme'],
            homeDirectory: home,
          )
          .lookup('runbook');
      final root = await _project(
        files: {
          _runbookPath: withApprovalHash(toText, runbookType),
          playbookPath: playbook,
        },
      );

      final result = await _run(root, home, ['migrate'], console: _owner());

      expect(result.status, 0, reason: result.err);
      expect(_read(root, _runbookPath), contains('approved:'));
      final check = await _run(root, home, ['check', '--json']);
      expect(
        _findingKinds(
          check.out,
          docPath: _runbookPath.substring('docs/'.length),
        ),
        isNot(contains('approval_stale')),
      );
    });
  });
  group('upgrade a pack pin', () {
    test('a release that '
        'only adds makes one commit that changes only the pins', () async {
      final home = await _home(migrations: '');
      final root = await _project(files: {_runbookPath: _runbookDoc});
      final before = _subjects(root);

      final result = await _run(root, home, ['migrate'], console: _owner());

      expect(result.status, 0, reason: result.err);
      expect(_subjects(root), hasLength(before.length + 1));
      expect(
        _gitOut(root, ['show', '--name-only', '--format=', 'HEAD']).trim(),
        '.specstone/config.yaml',
      );
      expect(
        result.out,
        _endingWith(
          'commit 2 ${_head(root).substring(0, 7)}: upgrade pack pins\n',
        ),
      );
      expect(
        _read(root, '.specstone/config.yaml'),
        '${_config('1.2.0')}$_stamp',
      );
      expect(_gitOut(root, ['status', '--porcelain']).trim(), isEmpty);
    });

    test(
      'a project holding the three older ignore '
      'lines ends migrate with a clean tree and the five lines committed',
      () async {
        final home = await _home(migrations: '');
        final root = await _project(
          files: {_runbookPath: _runbookDoc, _gitignore: _threeLineIgnoreFile},
        );

        final result = await _run(root, home, ['migrate'], console: _owner());

        expect(result.status, 0, reason: result.err);
        expect(_gitOut(root, ['status', '--porcelain']).trim(), isEmpty);
        expect(_read(root, _gitignore), _ignoreFile);
        expect(_gitOut(root, ['show', 'HEAD:$_gitignore']), _ignoreFile);
      },
    );

    test(
      'a layout-only run over the three older '
      'ignore lines ends with a clean tree and the five lines committed',
      () async {
        final home = await _home(migrations: '');
        final root = await _project(
          pin: '1.2.0',
          files: {
            _runbookPath: _runbookDoc.replaceFirst('Run it.', 'Run it.  '),
            _gitignore: _threeLineIgnoreFile,
          },
        );

        final result = await _run(root, home, ['migrate'], console: _owner());

        expect(result.status, 0, reason: result.err);
        expect(_gitOut(root, ['status', '--porcelain']).trim(), isEmpty);
        expect(_gitOut(root, ['show', 'HEAD:$_gitignore']), _ignoreFile);
      },
    );

    test('a docs-root file named with # is read as a file name, not a URI '
        'fragment', () async {
      final home = await _home();
      final root = await _project(
        files: {
          _runbookPath: _runbookDoc,
          'docs/prds/notes#draft.md': '# Notes\n',
        },
      );

      final dry = await _run(root, home, ['migrate', '--dry-run']);

      expect(dry.status, 0, reason: dry.err);
      expect(dry.out, endsWith('dry run: nothing written\n'));
    });

    test('every doc of the type and the override carry the new '
        'section name, and the pin moves', () async {
      final home = await _home();
      final root = await _project();

      final dry = await _run(root, home, ['migrate', '--dry-run']);
      expect(dry.status, 0, reason: dry.err);
      expect(dry.out, startsWith('pack upgrade: acme 1.0.0 -> 1.2.0\n'));
      expect(dry.out, endsWith('dry run: nothing written\n'));
      expect(_read(root, _runbookPath), _runbookDoc);

      final result = await _run(root, home, ['migrate'], console: _owner());

      expect(result.status, 0, reason: result.err);
      expect(_read(root, _runbookPath), contains('## Procedure\n'));
      expect(_read(root, _runbookPath), contains('on_call: sre\n'));
      expect(_read(root, _overridePath), contains('id: procedure'));
      expect(
        _read(root, '.specstone/config.yaml'),
        '${_config('1.2.0')}$_stamp',
      );
      expect(_subjects(root).first, 'upgrade pack pins');
      expect(_gitOut(root, ['status', '--porcelain']).trim(), isEmpty);
    });

    test('a release that moves files makes a '
        'pure-rename first commit, then links and pins', () async {
      final home = await _home(
        migrations: _moveMigrations,
        type: _runbookType('ops/runbooks/{slug}/RUNBOOK.md', 'steps'),
      );
      final root = await _project(
        files: {
          _runbookPath: _runbookDoc,
          'docs/prds/notes.md':
              '# Notes\n\n[run](runbooks/deploy/RUNBOOK.md)\n',
        },
      );
      final before = _subjects(root);

      final result = await _run(root, home, ['migrate'], console: _owner());

      expect(result.status, 0, reason: result.err);
      expect(_subjects(root).take(2).toList(), [
        'upgrade pack pins',
        'move docs to their new pack paths',
      ]);
      expect(_subjects(root), hasLength(before.length + 2));
      final commit1 = _gitOut(root, [
        'show',
        '--name-status',
        '--format=',
        'HEAD~1',
      ]);
      expect(commit1, matches(RegExp(r'^R100\t')));
      expect(
        File('${root.path}/docs/ops/runbooks/deploy/RUNBOOK.md').existsSync(),
        isTrue,
      );
      expect(File('${root.path}/$_runbookPath').existsSync(), isFalse);
      expect(
        _read(root, 'docs/prds/notes.md'),
        contains('](../ops/runbooks/deploy/RUNBOOK.md)'),
      );
      final commit2 = _gitOut(root, [
        'show',
        '--name-only',
        '--format=',
        'HEAD',
      ]).trim().split('\n').toSet();
      expect(commit2, {'.specstone/config.yaml', 'docs/prds/notes.md'});
      final commits = RegExp(r'commit (\d) [0-9a-f]+: (.*)\n')
          .allMatches(result.out);
      expect(
        [for (final m in commits) '${m[1]}: ${m[2]}'],
        ['1: move docs to their new pack paths', '2: upgrade pack pins'],
      );
    });

    test('a removed section stays and check '
        'lists it', () async {
      final home = await _home(
        migrations: '',
        type: _runbookType('prds/runbooks/{slug}/RUNBOOK.md', 'rollback'),
      );
      final root = await _project(
        files: {
          _runbookPath:
              '---\nowner: sre\n---\n# Deploy\n\n## Rollback\n\nx\n\n'
              '## Steps\n\nkeep me\n',
        },
      );

      final result = await _run(root, home, ['migrate'], console: _owner());

      expect(result.status, 0, reason: result.err);
      expect(_read(root, _runbookPath), contains('## Steps\n\nkeep me\n'));
      final check = await _run(root, home, ['check', '--json']);
      final findings =
          (jsonDecode(check.out) as Map<String, Object?>)['findings']! as List;
      expect([
        for (final f in findings) (f as Map)['kind'],
      ], contains('section_undeclared'));
    });

    test('a release that removes a field and a doc type and makes a section '
        'required adds no section and leaves each for check to list', () async {
      const releaseType = '''
id: runbook
description: A runbook.
path: prds/runbooks/{slug}/RUNBOOK.md
fields:
  - {id: on_call, type: string}
sections:
  - {id: steps, header: Steps, required: true}
  - {id: verify, header: Verify, required: true}
''';
      const playbookPath = 'docs/prds/playbooks/p1/PLAYBOOK.md';
      const playbook = '# P\n\n## Steps\n\nx\n';
      final home = await _home(migrations: '', type: releaseType);
      final root = await _project(
        files: {_runbookPath: _runbookDoc, playbookPath: playbook},
      );

      final result = await _run(root, home, ['migrate'], console: _owner());

      expect(result.status, 0, reason: result.err);
      expect(_read(root, _runbookPath), _runbookDoc);
      expect(_read(root, playbookPath), playbook);
      final check = await _run(root, home, ['check', '--json']);
      expect(
        _findingKinds(check.out, docPath: 'prds/runbooks/deploy/RUNBOOK.md'),
        containsAll(['field_undeclared', 'required_section_missing']),
      );
      expect(
        _findingKinds(check.out, docPath: 'prds/playbooks/p1/PLAYBOOK.md'),
        contains('untyped_doc'),
      );
    });

    test(
      'a step that renames a section and a field and the layout pass '
      'write the doc once, so the first check raises no format_drift',
      () async {
        final home = await _home(
          type: _runbookType(
            'prds/runbooks/{slug}/RUNBOOK.md',
            'procedure',
          ).replaceFirst('header: Steps', 'header: Procedure'),
        );
        final root = await _project(
          files: {
            _runbookPath: _runbookDoc.replaceFirst('Run it.', 'Run it.   '),
            _overridePath: 'sections: [{id: steps, required: true}]\n',
          },
        );
        final writes = _gitOut(root, [
          'log',
          '--format=%h',
          '--',
          _runbookPath,
        ]).trim().split('\n').length;

        final result = await _run(root, home, ['migrate'], console: _owner());

        expect(result.status, 0, reason: result.err);
        expect(
          _read(root, _runbookPath),
          '---\non_call: sre\n---\n# Deploy\n\n## Procedure\n\nRun it.\n',
        );
        expect(
          _gitOut(root, [
            'log',
            '--format=%h',
            '--',
            _runbookPath,
          ]).trim().split('\n'),
          hasLength(writes + 1),
        );
        final check = await _run(root, home, ['check', '--json']);
        expect(_findingKinds(check.out), isNot(contains('format_drift')));
      },
    );

    test('a doc the format command refuses stays as it is and keeps the '
        'finding that names its cause', () async {
      const refusedPath = 'docs/prds/features/f01_a/FEATURE.md';
      const refused = '## Notes\nx   \n';
      final home = await _home(migrations: '');
      final root = await _project(
        pin: '1.2.0',
        files: {
          _runbookPath: _runbookDoc.replaceFirst('Run it.', 'Run it.  '),
          refusedPath: refused,
        },
      );

      final result = await _run(root, home, ['migrate'], console: _owner());

      expect(result.status, 0, reason: result.err);
      expect(result.out, contains('  format layout: 1 docs\n'));
      expect(_read(root, refusedPath), refused);
      final check = await _run(root, home, ['check', '--json']);
      expect(
        _findingKinds(check.out, docPath: 'prds/features/f01_a/FEATURE.md'),
        contains('section_undeclared'),
      );
    });

    test('a doc that cannot be read refuses the dry run with exit 73 before '
        'anything prints and writes nothing', () async {
      final home = await _home();
      final root = await _project(files: {_runbookPath: _runbookDoc});
      final before = _bytesUnder(root);
      final head = _head(root);
      final doc = '${root.path}/$_runbookPath';
      expect(Process.runSync('chmod', ['000', doc]).exitCode, 0);
      addTearDown(() => Process.runSync('chmod', ['644', doc]));

      final result = await _run(root, home, ['migrate', '--dry-run']);

      expect(result.status, 73);
      expect(result.out, isEmpty);
      expect(
        result.err,
        startsWith('cannot read prds/runbooks/deploy/RUNBOOK.md: '),
      );
      Process.runSync('chmod', ['644', doc]);
      expect(_bytesUnder(root), before);
      expect(_head(root), head);
    }, skip: unreadablePathSkipReason());

    test('pins equal and one doc off its layout makes one layout-only '
        'commit, then a rerun has nothing to migrate', () async {
      final home = await _home(migrations: '');
      final root = await _project(
        pin: '1.2.0',
        files: {_runbookPath: _runbookDoc.replaceFirst('Run it.', 'Run it.  ')},
      );
      final before = _subjects(root);

      final result = await _run(root, home, ['migrate'], console: _owner());

      expect(result.status, 0, reason: result.err);
      expect(
        result.out,
        startsWith(
          'pack upgrade: pins unchanged, layout only\n'
          'commit 2, rewrites:\n'
          '  format layout: 1 docs\n',
        ),
      );
      expect(
        result.out,
        _endingWith(
          'commit 2 ${_head(root).substring(0, 7)}: '
          'lay docs out as format writes them\n',
        ),
      );
      expect(_subjects(root), hasLength(before.length + 1));
      expect(
        _gitOut(root, ['show', '--name-only', '--format=', 'HEAD']).trim(),
        _runbookPath,
      );
      expect(_read(root, _runbookPath), _runbookDoc);
      expect(_read(root, '.specstone/config.yaml'), _config('1.2.0'));

      final again = await _run(root, home, ['migrate'], console: _owner());

      expect(again.status, 0, reason: again.err);
      expect(again.out, 'nothing to migrate\n');
    });

    test('a layout-only run adds neither a required nor an optional section '
        'the doc lacks', () async {
      final home = await _home(
        migrations: '',
        type: '''
id: runbook
description: A runbook.
path: prds/runbooks/{slug}/RUNBOOK.md
sections:
  - {id: steps, header: Steps, required: true}
  - {id: checks, header: Checks, required: true}
  - {id: notes, header: Notes}
''',
      );
      final root = await _project(
        pin: '1.2.0',
        files: {_runbookPath: _runbookDoc.replaceFirst('Run it.', 'Run it.  ')},
      );

      final result = await _run(root, home, ['migrate'], console: _owner());

      expect(result.status, 0, reason: result.err);
      expect(result.out, contains('format layout: 1 docs\n'));
      expect(_read(root, _runbookPath), _runbookDoc);
    });

    test('nothing to upgrade prints nothing to migrate and writes '
        'nothing', () async {
      final home = await _home(
        version: '1.0.0',
        migrations: '',
        type: _runbookType('prds/runbooks/{slug}/RUNBOOK.md', 'steps'),
      );
      final root = await _project(files: {_runbookPath: _runbookDoc});
      final before = _bytesUnder(root);

      final result = await _run(root, home, ['migrate'], console: _owner());

      expect(result.status, 0, reason: result.err);
      expect(result.out, 'nothing to migrate\n');
      expect(_bytesUnder(root), before);
    });

    test(
      'with equal pins, an override that does not merge stops migrate '
      'and check with override_id_not_found naming the override file',
      () async {
        final home = await _home(version: '1.0.0', migrations: '');
        final root = await _project();

        for (final args in [
          ['migrate'],
          ['check'],
        ]) {
          final result = await _run(root, home, args, console: _owner());

          expect(result.status, 78, reason: args.join(' '));
          expect(result.err, contains(_overridePath), reason: args.join(' '));
          expect(
            result.err,
            contains('sections.steps'),
            reason: args.join(' '),
          );
        }
      },
    );

    test('an override that names a section the merged type lacks refuses '
        'bare migrate and the dry run with exit 78 before a run is chosen, '
        'and writes nothing', () async {
      final home = await _home(version: '1.0.0', migrations: '');
      final root = await _project();
      final before = _bytesUnder(root);
      final head = _head(root);

      for (final args in [
        ['migrate', '--dry-run'],
        ['migrate'],
      ]) {
        final result = await _run(root, home, args, console: _owner());

        expect(result.status, 78, reason: args.join(' '));
        expect(
          result.err,
          '$_overridePath: sections.steps: no section "steps" in the merged '
          'doc type and no header to add it\n',
          reason: args.join(' '),
        );
        expect(result.out, isEmpty, reason: args.join(' '));
      }
      expect(_bytesUnder(root), before);
      expect(_head(root), head);
    });

    test('a project override that gives a doc type the code field puts the '
        'repository top its docs list into the agent-only upgrade', () async {
      final home = await _home(
        version: '1.0.0',
        migrations: '',
        type: _runbookType('prds/runbooks/{slug}/RUNBOOK.md', 'steps'),
      );
      Future<Directory> project(String override) => _project(
        files: {
          _runbookPath:
              '---\ncode:\n  - other/\n---\n# Deploy\n\n## Steps\n\nRun it.\n',
          _overridePath: 'sections: [{id: steps, required: true}]\n$override',
          'other/.git/HEAD': 'ref: refs/heads/main\n',
          '.gitignore': 'other/\n',
        },
      );

      final without = await _run(await project(''), home, [
        'migrate',
        '--dry-run',
      ]);
      final withCode = await _run(
        await project('fields: [{id: code, type: string, list: true}]\n'),
        home,
        ['migrate', '--dry-run'],
      );

      expect(without.out, 'nothing to migrate\n');
      expect(
        withCode.out,
        startsWith(
          'pack upgrade: pins unchanged, agent files only\n'
          'commit 2, rewrites:\n'
          '  agent files: ${1 + skillFileCount} files\n',
        ),
      );
    });

    test('a pin newer than Specstone refuses', () async {
      final home = await _home(version: '1.2.0');
      final root = await _project(pin: '9.0.0');

      for (final args in [
        ['migrate'],
        ['migrate', '--dry-run'],
      ]) {
        final result = await _run(root, home, args, console: _owner());
        expect(result.status, 78, reason: args.join(' '));
        expect(
          result.err,
          startsWith(
            '.specstone/config.yaml: packs.acme: Pack acme is pinned at 9.0.0, '
            'and this Specstone carries 1.2.0. Upgrade Specstone',
          ),
        );
        expect(result.out, isEmpty);
      }
    });

    test('an override left pointing at nothing '
        'refuses in the dry run and in bare migrate, and the edited override '
        'prints the plan', () async {
      final home = await _home();
      final root = await _project(
        files: {
          _runbookPath: _runbookDoc,
          _overridePath: 'sections: [{id: checklist, required: true}]\n',
        },
      );
      final before = _bytesUnder(root);

      for (final args in [
        ['migrate', '--dry-run'],
        ['migrate'],
      ]) {
        final result = await _run(root, home, args, console: _owner());
        expect(result.status, 78, reason: args.join(' '));
        expect(
          result.err,
          '.specstone/templates/runbook.yaml: sections.checklist: pack acme '
          '1.2.0 defines no section checklist and no step renames it; edit the '
          'override, then run specstone migrate again\n',
        );
        expect(result.out, isEmpty);
      }
      expect(_bytesUnder(root), before);

      File('${root.path}/$_overridePath')
          .writeAsStringSync('sections: [{id: steps, required: true}]\n');
      commitAll(root, 'edit the override');
      final edited = await _run(root, home, ['migrate', '--dry-run']);
      expect(edited.status, 0, reason: edited.err);
      expect(edited.out, startsWith('pack upgrade: acme 1.0.0 -> 1.2.0\n'));
    });

    test('a malformed migrations list refuses with the pack '
        'fault', () async {
      final home = await _home(
        migrations: 'migrations:\n  - from: 1.0\n    steps: []\n',
      );
      final root = await _project();

      final result = await _run(root, home, ['migrate', '--dry-run']);

      expect(result.status, 78);
      expect(
        result.err,
        startsWith('~/.specstone/packs/acme/pack.yaml: migrations[0].from: '),
      );
      expect(result.out, isEmpty);
    });

    /// Runs the dry run and bare migrate over a pack whose [migrations] the
    /// load refuses, and expects exit 78 at [key], nothing printed, and the
    /// tree as it was.
    Future<void> expectPackRefused(String migrations, String key) async {
      final home = await _home(migrations: migrations);
      final root = await _project();
      final before = _bytesUnder(root);
      final head = _head(root);

      for (final args in [
        ['migrate', '--dry-run'],
        ['migrate'],
      ]) {
        final result = await _run(root, home, args, console: _owner());

        expect(result.status, 78, reason: '$key ${args.join(' ')}');
        expect(
          result.err,
          startsWith('~/.specstone/packs/acme/pack.yaml: $key'),
          reason: args.join(' '),
        );
        expect(result.out, isEmpty, reason: '$key ${args.join(' ')}');
      }
      expect(_bytesUnder(root), before, reason: key);
      expect(_head(root), head, reason: key);
    }

    test('a step of an unknown kind, a step with a key missing, and a step '
        'with a key unknown each refuse with exit 78 and leave the tree '
        'as it was', () async {
      const cases = [
        (
          'migrations[0].steps[0]',
          'migrations:\n  - from: 1.0.0\n    steps:\n'
              '      - frob_section: {doc_type: runbook}\n',
        ),
        (
          'migrations[0].steps[0].rename_field.to',
          'migrations:\n  - from: 1.0.0\n    steps:\n'
              '      - rename_field: {doc_type: runbook, from: owner}\n',
        ),
        (
          'migrations[0].steps[0].rename_field.extra',
          'migrations:\n  - from: 1.0.0\n    steps:\n'
              '      - rename_field: {doc_type: runbook, from: owner, '
              'to: on_call, extra: x}\n',
        ),
      ];

      for (final (key, migrations) in cases) {
        await expectPackRefused(migrations, key);
      }
    });

    test('a move_file step whose to pattern holds other placeholders or the '
        'same ones in another order refuses with exit 78 and leaves the tree '
        'as it was', () async {
      const cases = [
        (
          'migrations[0].steps[0].move_file.to',
          'migrations:\n  - from: 1.0.0\n    steps:\n'
              '      - move_file: {doc_type: runbook, '
              'from: "prds/runbooks/{slug}/RUNBOOK.md", '
              'to: "ops/{slug}/{extra}/RUNBOOK.md"}\n',
        ),
        (
          'migrations[0].steps[0].move_file.to',
          'migrations:\n  - from: 1.0.0\n    steps:\n'
              '      - move_file: {doc_type: runbook, '
              'from: "prds/{a}/{b}/RUNBOOK.md", '
              'to: "prds/{b}/{a}/RUNBOOK.md"}\n',
        ),
      ];

      for (final (key, migrations) in cases) {
        await expectPackRefused(migrations, key);
      }
    });

    test('a hook that prepends a paragraph to each message '
        'still lists both commits', () async {
      final home = await _home(
        migrations: _moveMigrations,
        type: _runbookType('ops/runbooks/{slug}/RUNBOOK.md', 'steps'),
      );
      final root = await _project(files: {_runbookPath: _runbookDoc});
      final hook = File('${root.path}/.git/hooks/commit-msg')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          '#!/bin/sh\n'
          'printf "ticket: T-1\\n\\n" | cat - "\$1" > "\$1.new"\n'
          'mv "\$1.new" "\$1"\n',
        );
      expect(Process.runSync('chmod', ['755', hook.path]).exitCode, 0);

      final result = await _run(root, home, ['migrate'], console: _owner());

      expect(result.status, 0, reason: result.err);
      expect(_subjects(root).take(2).toList(), ['ticket: T-1', 'ticket: T-1']);
      final commits = RegExp(r'commit (\d) [0-9a-f]+: ').allMatches(result.out);
      expect([for (final m in commits) m[1]], ['1', '2']);
    }, skip: Platform.isWindows ? 'the hook is a sh script' : null);

    test('an upgrade stopped after commit 1 '
        'resumes with its own output and the closing count', () async {
      final home = await _home(
        migrations: _moveMigrations,
        type: _runbookType('ops/runbooks/{slug}/RUNBOOK.md', 'steps'),
      );
      final root = await _project(files: {_runbookPath: _runbookDoc});
      final hook = _refuseCommit2(root);

      final stopped = await _run(root, home, ['migrate'], console: _owner());
      expect(stopped.status, 75, reason: stopped.err);
      expect(_subjects(root).first, 'move docs to their new pack paths');
      hook.deleteSync();

      final resumed = await _run(root, home, ['migrate'], console: _owner());

      expect(resumed.status, 0, reason: resumed.err);
      expect(_subjects(root).first, 'upgrade pack pins');
      expect(resumed.out, contains('commit 2 '));
      expect(
        resumed.out,
        matches(
          RegExp(
            r'check: \d+ findings left; run specstone check to see them\n$',
          ),
        ),
      );
      expect(_gitOut(root, ['status', '--porcelain']).trim(), isEmpty);
    }, skip: Platform.isWindows ? 'the hook is a sh script' : null);

    test('a move onto a staying doc refuses in the dry '
        'run and in bare migrate, exits 65, and writes nothing', () async {
      final home = await _home(
        migrations: _collideMigrations,
        type: _runbookType('prds/runbooks/{slug}/PLAYBOOK.md', 'steps'),
      );
      final root = await _project(
        files: {
          _runbookPath: _runbookDoc,
          'docs/prds/runbooks/deploy/PLAYBOOK.md': '# Kept\n\n## Steps\n\ny\n',
        },
      );
      final before = _bytesUnder(root);

      for (final args in [
        ['migrate', '--dry-run'],
        ['migrate'],
      ]) {
        final result = await _run(root, home, args, console: _owner());
        expect(result.status, 65, reason: args.join(' '));
        expect(
          result.err,
          'prds/runbooks/deploy/RUNBOOK.md: move_file of runbook moves '
          'prds/runbooks/{slug}/RUNBOOK.md to prds/runbooks/{slug}/PLAYBOOK.md, '
          'which the doc already there holds; move, rename, or merge each '
          'listed doc or entry so the step no longer lands on it, then run '
          'specstone migrate again\n',
        );
        expect(result.out, isEmpty);
      }
      expect(_bytesUnder(root), before);
    });

    test('a rename onto a header or key the doc already '
        'holds refuses, exits 65, listing the doc once', () async {
      final home = await _home(
        migrations: _heldRenamedMigrations,
        type: _runbookType('prds/runbooks/{slug}/RUNBOOK.md', 'steps'),
      );
      final root = await _project(
        files: {
          _runbookPath:
              '---\nowner: sre\non_call: ira\n---\n# Deploy\n\n## Steps\n\n'
              'x\n\n## Procedure\n\ny\n',
        },
      );

      final result = await _run(root, home, ['migrate'], console: _owner());

      expect(result.status, 65);
      expect(
        result.err,
        'prds/runbooks/deploy/RUNBOOK.md: rename_section of runbook renames '
        'Steps to Procedure, which the doc already holds; move, rename, or '
        'merge each listed doc or entry so the step no longer lands on it, '
        'then run specstone migrate again\n',
      );
      expect(_subjects(root).single, 'legacy');
    });

    test('a swap composes onto one path and refuses at the '
        'terminal', () async {
      final home = await _home(
        migrations: _swapMigrations,
        type: _runbookType('prds/runbooks/{slug}/RUNBOOK.md', 'steps'),
      );
      const runbookText = '# Deploy\n\n## Steps\n\nrunbook body\n';
      const notesText = '# Notes\n\n## Steps\n\nnotes body\n';
      final root = await _project(
        files: {
          _runbookPath: runbookText,
          'docs/prds/runbooks/deploy/NOTES.md': notesText,
        },
      );

      final result = await _run(root, home, ['migrate'], console: _owner());

      expect(result.status, 65);
      expect(
        result.err,
        startsWith(
          'prds/runbooks/deploy/NOTES.md: move_file of runbook moves '
          'prds/runbooks/{slug}/NOTES.md to prds/runbooks/{slug}/RUNBOOK.md',
        ),
      );
      expect(_read(root, _runbookPath), runbookText);
      expect(_read(root, 'docs/prds/runbooks/deploy/NOTES.md'), notesText);
      expect(_subjects(root).single, 'legacy');
    });

    test('a chained move through a freed path lands with no '
        'content lost', () async {
      final home = await _home(
        migrations: _chainMigrations,
        type: _runbookType('prds/runbooks/{slug}/RUNBOOK.md', 'steps'),
      );
      const runbookText = '# Deploy\n\n## Steps\n\nrunbook body\n';
      const notesText = '# Notes\n\n## Steps\n\nnotes body\n';
      final root = await _project(
        files: {
          'docs/prds/ops/deploy/RUNBOOK.md': runbookText,
          'docs/prds/runbooks/deploy/NOTES.md': notesText,
        },
      );

      final result = await _run(root, home, ['migrate'], console: _owner());

      expect(result.status, 0, reason: result.err);
      expect(_read(root, _runbookPath), runbookText);
      expect(_read(root, 'docs/prds/ops/deploy/RUNBOOK.md'), notesText);
      expect(_gitOut(root, ['status', '--porcelain']).trim(), isEmpty);
    });

    test('a chained move stopped after commit 1 '
        'resumes without overwriting the doc it landed', () async {
      final home = await _home(
        migrations: _chainMigrations,
        type: _runbookType('prds/runbooks/{slug}/RUNBOOK.md', 'steps'),
      );
      const runbookText = '# Deploy\n\n## Steps\n\nrunbook body\n';
      const notesText = '# Notes\n\n## Steps\n\nnotes body\n';
      final root = await _project(
        files: {
          'docs/prds/ops/deploy/RUNBOOK.md': runbookText,
          'docs/prds/runbooks/deploy/NOTES.md': notesText,
        },
      );
      final hook = _refuseCommit2(root);
      final stopped = await _run(root, home, ['migrate'], console: _owner());
      expect(stopped.status, 75, reason: stopped.err);
      hook.deleteSync();

      final resumed = await _run(root, home, ['migrate'], console: _owner());

      expect(resumed.status, 0, reason: resumed.err);
      expect(_read(root, _runbookPath), runbookText);
      expect(_read(root, 'docs/prds/ops/deploy/RUNBOOK.md'), notesText);
      expect(_subjects(root).first, 'upgrade pack pins');
      expect(_gitOut(root, ['status', '--porcelain']).trim(), isEmpty);
    }, skip: Platform.isWindows ? 'the hook is a sh script' : null);

    group('a rotation through a temporary name', () {
      const notesPath = 'docs/prds/runbooks/deploy/NOTES.md';
      const runbookText = '# Deploy\n\n## Steps\n\nrunbook body\n';
      const notesText = '# Notes\n\n## Steps\n\nnotes body\n';
      late Directory home;
      late Directory root;

      setUp(() async {
        home = await _home(
          migrations: _rotationMigrations,
          type: _runbookType('prds/runbooks/{slug}/RUNBOOK.md', 'steps'),
        );
        root = await _project(
          files: {_runbookPath: runbookText, notesPath: notesText},
        );
      });

      void expectTraded() {
        expect(_read(root, notesPath), runbookText);
        expect(_read(root, _runbookPath), notesText);
        expect(_gitOut(root, ['status', '--porcelain']).trim(), isEmpty);
      }

      test('trades the two docs and prints no '
          'stage path', () async {
        final result = await _run(root, home, ['migrate'], console: _owner());

        expect(result.status, 0, reason: result.err);
        expect(result.out, isNot(contains('.specstone/trash')));
        expectTraded();
      });

      test('stopped after commit 1, resumes '
          'without trading them back', () async {
        final hook = _refuseCommit2(root);
        final stopped = await _run(root, home, ['migrate'], console: _owner());
        expect(stopped.status, 75, reason: stopped.err);
        hook.deleteSync();

        final resumed = await _run(root, home, ['migrate'], console: _owner());

        expect(resumed.status, 0, reason: resumed.err);
        expect(resumed.out, isNot(contains('.specstone/trash/stage')));
        expectTraded();
      }, skip: Platform.isWindows ? 'the hook is a sh script' : null);
    });

    group('agent files', () {
      const begin = '<!-- BEGIN specstone v$specstoneVersion -->';
      const staleBlock = '$begin\nold rules\n<!-- END specstone -->\n';

      Future<Directory> agentProject(
        Map<String, String> files,
        String config,
      ) => gitFixture({
        '.specstone/config.yaml': config,
        _gitignore: _ignoreFile,
        '.gitignore': 'code/\n',
        ...files,
      });

      test('a stale block is rewritten alone and '
          'the pins stay', () async {
        final root = await agentProject({
          '.specstone/AGENT.md': agentMdText,
          'CLAUDE.md': '# Owner rules\n\n$staleBlock',
        }, shippedPinsConfig());
        final config = _read(root, '.specstone/config.yaml');
        final before = _subjects(root);
        final home = await writeTree({});

        final result = await _run(root, home, ['migrate'], console: _owner());

        expect(result.status, 0);
        expect(
          result.out,
          startsWith(
            'pack upgrade: pins unchanged, agent files only\n'
            'commit 2, rewrites:\n'
            '  agent files: 1 files\n'
            'apply? [y/N] ',
          ),
        );
        expect(
          result.out,
          matches(
            RegExp(
              r'commit 2 [0-9a-f]+: refresh the Specstone agent files\n'
              r'check: \d+ findings left; run specstone check to see them\n$',
            ),
          ),
        );
        expect(_subjects(root), hasLength(before.length + 1));
        expect(
          _gitOut(root, [
            'show',
            '--name-only',
            '--format=',
            'HEAD',
          ]).trim().split('\n'),
          unorderedEquals(['CLAUDE.md', '.specstone/config.yaml']),
        );
        expect(_read(root, '.specstone/config.yaml'), '$config$_stamp');
        expect(
          _read(root, 'CLAUDE.md'),
          startsWith('# Owner rules\n\n$begin\n'),
        );
        expect(_read(root, 'CLAUDE.md'), isNot(contains('old rules')));
      });

      test('a top the config '
          'does not list takes its files outside both commits', () async {
        final root = await agentProject(
          {},
          '${shippedPinsConfig()}code_root: code\n',
        );
        Directory('${root.path}/code/.git').createSync(recursive: true);
        File('${root.path}/code/.git/HEAD')
            .writeAsStringSync('ref: refs/heads/main\n');
        final home = await writeTree({});

        final result = await _run(root, home, ['migrate'], console: _owner());

        expect(result.status, 0);
        expect(
          result.out,
          contains('  agent files: ${1 + skillFileCount} files\n'),
        );
        expect(File('${root.path}/code/AGENTS.md').existsSync(), isTrue);
        for (final path in skillPaths('code/')) {
          expect(File('${root.path}/$path').existsSync(), isTrue, reason: path);
        }
        expect(
          _gitOut(root, ['show', '--name-only', '--format=', 'HEAD']).trim(),
          '.specstone/config.yaml',
        );
        expect(
          _read(root, '.specstone/config.yaml'),
          contains('agent_file_roots:\n  - code\n'),
        );
        final rerun = await _run(root, home, ['migrate'], console: _owner());
        expect(rerun.out, 'nothing to migrate\n');
      });

      test('a hand-edited skill file with every pin equal is the '
          'agent-only upgrade, one file listed and rewritten', () async {
        final texts = skillFileTexts();
        final path = texts.keys.first;
        final root = await agentProject({
          ...texts,
          path: '${texts[path]}hand edit\n',
        }, shippedPinsConfig());
        final home = await writeTree({});

        final json = await _run(root, home, ['migrate', '--dry-run', '--json']);
        final result = await _run(root, home, ['migrate'], console: _owner());

        expect(json.status, 0, reason: json.err);
        final plan = jsonDecode(json.out) as Map<String, Object?>;
        expect(plan['agentFiles'], [path]);
        expect(result.status, 0, reason: result.err);
        expect(result.out, contains('  agent files: 1 files\n'));
        expect(_read(root, path), texts[path]);
        expect(
          _gitOut(root, [
            'show',
            '--name-only',
            '--format=',
            'HEAD',
          ]).trim().split('\n'),
          unorderedEquals([path, '.specstone/config.yaml']),
        );
      });

      test('every pin equal and an agent file with malformed marker lines '
          'refuses with exit 65, prints nothing, and writes nothing', () async {
        final root = await agentProject({
          'AGENTS.md': '$begin\nbody\n',
        }, shippedPinsConfig());
        final home = await writeTree({});
        final before = _bytesUnder(root);
        final head = _head(root);

        for (final args in [
          ['migrate', '--dry-run'],
          ['migrate'],
        ]) {
          final result = await _run(root, home, args, console: _owner());

          expect(result.status, 65, reason: args.join(' '));
          expect(result.out, isEmpty, reason: args.join(' '));
          expect(
            result.err,
            startsWith('AGENTS.md:1: the Specstone marker lines are malformed'),
            reason: args.join(' '),
          );
        }
        expect(_bytesUnder(root), before);
        expect(_head(root), head);
      });

      test('an import block whose AGENT.md is missing plans the agent files '
          'step alone', () async {
        final root = await agentProject({
          'CLAUDE.md': importBlock(
            cliVersion: specstoneVersion,
            agentMdPath: '.specstone/AGENT.md',
            projectDocPath: 'docs/prds/PROJECT.md',
            goalDocPath: 'docs/prds/GOAL.md',
            featuresDocPath: 'docs/prds/FEATURES.md',
          ),
        }, shippedPinsConfig());
        final home = await writeTree({});

        final dry = await _run(root, home, ['migrate', '--dry-run', '--json']);
        final result = await _run(root, home, ['migrate'], console: _owner());

        expect(dry.status, 0, reason: dry.err);
        expect((jsonDecode(dry.out) as Map<String, Object?>)['agentFiles'], [
          '.specstone/AGENT.md',
        ]);
        expect(result.status, 0, reason: result.err);
        expect(
          result.out,
          startsWith(
            'pack upgrade: pins unchanged, agent files only\n'
            'commit 2, rewrites:\n'
            '  agent files: 1 files\n',
          ),
        );
        expect(_read(root, '.specstone/AGENT.md'), agentMdText);
      });

      test('a repository top the config does not list plans the agent files '
          'step alone', () async {
        final root = await agentProject(
          {},
          '${shippedPinsConfig()}code_root: code\n',
        );
        Directory('${root.path}/code/.git').createSync(recursive: true);
        File('${root.path}/code/.git/HEAD')
            .writeAsStringSync('ref: refs/heads/main\n');
        final home = await writeTree({});

        final result = await _run(root, home, ['migrate', '--dry-run']);

        expect(result.status, 0, reason: result.err);
        expect(
          result.out,
          startsWith(
            'pack upgrade: pins unchanged, agent files only\n'
            'commit 2, rewrites:\n'
            '  agent files: ${1 + skillFileCount} files\n',
          ),
        );
      });

      group('an unshipped skill or agent file', () {
        const oldSkill = '.claude/skills/specstone-old';
        const refreshMessage = 'refresh the Specstone agent files';

        /// The fixture files: every shipped file, an unshipped skill folder
        /// with two files, an extra file inside a shipped skill folder, and
        /// two files the Owner owns.
        ({Map<String, String> files, List<String> unshipped}) fixture() {
          final texts = skillFileTexts();
          final shipped = texts.keys.firstWhere(
            (path) => path.startsWith('.claude/skills/'),
          );
          final extra =
              '${shipped.substring(0, shipped.lastIndexOf('/'))}/extra.md';
          final unshipped = [
            '$oldSkill/SKILL.md',
            '$oldSkill/references/more.md',
            extra,
          ];
          return (
            files: {
              ...texts,
              for (final path in unshipped) path: 'old\n',
              '.claude/skills/own-skill/SKILL.md': 'own\n',
              '.claude/agents/own-agent.md': 'own\n',
            },
            unshipped: unshipped,
          );
        }

        File refuseRefresh(Directory root) {
          final hook = File('${root.path}/.git/hooks/commit-msg')
            ..parent.createSync(recursive: true)
            ..writeAsStringSync(
              '#!/bin/sh\ngrep -q "$refreshMessage" "\$1" && exit 1\nexit 0\n',
            );
          expect(Process.runSync('chmod', ['755', hook.path]).exitCode, 0);
          return hook;
        }

        test('moves to the trash, counted on the line, and no other file '
            'is deleted', () async {
          final (:files, :unshipped) = fixture();
          final root = await agentProject(files, shippedPinsConfig());
          final home = await writeTree({});

          final dry = await _run(root, home, [
            'migrate',
            '--dry-run',
            '--json',
          ]);
          final result = await _run(root, home, ['migrate'], console: _owner());

          expect(dry.status, 0, reason: dry.err);
          expect(
            (jsonDecode(dry.out) as Map<String, Object?>)['agentFiles'],
            unorderedEquals(unshipped),
          );
          expect(result.status, 0, reason: result.err);
          expect(result.out, contains('  agent files: 3 files\n'));
          for (final path in unshipped) {
            expect(
              File('${root.path}/$path').existsSync(),
              isFalse,
              reason: path,
            );
          }
          expect(Directory('${root.path}/$oldSkill').existsSync(), isFalse);
          for (final path in [
            ...files.keys.where((path) => !unshipped.contains(path)),
          ]) {
            expect(_read(root, path), files[path], reason: path);
          }
          expect(
            _gitOut(root, [
              'show',
              '--name-only',
              '--format=',
              'HEAD',
            ]).trim().split('\n'),
            unorderedEquals([...unshipped, '.specstone/config.yaml']),
          );
          expect(
            Directory('${root.path}/.specstone/trash').existsSync(),
            isFalse,
          );
          expect(_gitOut(root, ['status', '--porcelain']).trim(), isEmpty);
          final rerun = await _run(root, home, ['migrate'], console: _owner());
          expect(rerun.out, 'nothing to migrate\n');
        });

        test('at a listed repository top moves outside both commits', () async {
          final root = await agentProject({}, '''
${shippedPinsConfig()}code_root: code
agent_file_roots:
  - code
''');
          final top = Directory('${root.path}/code')..createSync();
          Directory('${top.path}/.git').createSync();
          File('${top.path}/.git/HEAD')
              .writeAsStringSync('ref: refs/heads/main\n');
          for (final MapEntry(:key, :value) in {
            ...skillFileTexts('code/'),
            'code/$oldSkill/SKILL.md': 'old\n',
          }.entries) {
            File('${root.path}/$key')
              ..createSync(recursive: true)
              ..writeAsStringSync(value);
          }
          final home = await writeTree({});
          final before = _subjects(root);

          final result = await _run(root, home, ['migrate'], console: _owner());

          expect(result.status, 0, reason: result.err);
          expect(result.out, contains('  agent files: 1 files\n'));
          expect(
            Directory('${root.path}/code/$oldSkill').existsSync(),
            isFalse,
          );
          expect(_subjects(root), [refreshMessage, ...before]);
          expect(
            _gitOut(root, ['show', '--name-only', '--format=', 'HEAD']).trim(),
            '.specstone/config.yaml',
          );
          final rerun = await _run(root, home, ['migrate'], console: _owner());
          expect(rerun.out, 'nothing to migrate\n');
        });

        test('a run stopped after the move resumes without moving it '
            'again', () async {
          final (:files, :unshipped) = fixture();
          final root = await agentProject(files, shippedPinsConfig());
          final home = await writeTree({});
          final hook = refuseRefresh(root);

          final stopped = await _run(root, home, [
            'migrate',
          ], console: _owner());
          expect(stopped.status, 75, reason: stopped.err);
          expect(Directory('${root.path}/$oldSkill').existsSync(), isFalse);
          expect(
            File('${root.path}/.specstone/trash/files/$oldSkill/SKILL.md')
                .existsSync(),
            isTrue,
          );
          hook.deleteSync();

          final pending = await _run(root, home, ['migrate', '--dry-run']);
          final resumed = await _run(root, home, [
            'migrate',
          ], console: _owner());

          expect(pending.out, contains('remaining steps:'));
          expect(pending.out, isNot(contains('move ')));
          expect(resumed.status, 0, reason: resumed.err);
          expect(
            _gitOut(root, [
              'show',
              '--name-only',
              '--format=',
              'HEAD',
            ]).trim().split('\n'),
            unorderedEquals([...unshipped, '.specstone/config.yaml']),
          );
          expect(_gitOut(root, ['status', '--porcelain']).trim(), isEmpty);
        }, skip: Platform.isWindows ? 'the hook is a sh script' : null);
      });

      test('a group none of whose folders holds a specstone entry starts '
          'no run', () async {
        final root = await agentProject({
          '.claude/skills/own-skill/SKILL.md': 'own\n',
        }, shippedPinsConfig());
        final home = await writeTree({});

        final result = await _run(root, home, ['migrate']);

        expect(result.out, 'nothing to migrate\n');
      });

      test('the plan hash moves when the bytes of one skill file '
          'change', () async {
        final texts = skillFileTexts();
        final path = texts.keys.first;
        final root = await agentProject({
          ...texts,
          path: '${texts[path]}first edit\n',
        }, shippedPinsConfig());
        final home = await writeTree({});
        String hashOf(String out) => RegExp(
          r'^plan ([0-9a-f]+)$',
          multiLine: true,
        ).firstMatch(out)!.group(1)!;

        final first = await _run(root, home, ['migrate', '--dry-run']);
        File('${root.path}/$path')
            .writeAsStringSync('${texts[path]}second edit\n');
        commitAll(root, 'second edit');
        final second = await _run(root, home, ['migrate', '--dry-run']);

        expect(first.status, 0, reason: first.err);
        expect(second.status, 0, reason: second.err);
        expect(hashOf(first.out), isNot(hashOf(second.out)));
      });

      test('a malformed file refuses before '
          'anything prints', () async {
        final root = await agentProject({
          'AGENTS.md': '$begin\nbody\n',
        }, shippedPinsConfig());
        final home = await writeTree({});

        final result = await _run(root, home, ['migrate', '--dry-run']);

        expect(result.status, 65);
        expect(result.out, isEmpty);
        expect(result.err, contains('AGENTS.md'));
      });
    });

    group('a second code target over a one-target spec tree', () {
      const featurePath = 'docs/prds/features/f02_feedback/FEATURE.md';
      const oldArch = 'docs/specs/f02_feedback/ARCHITECTURE.md';
      const newArch = 'docs/specs/flutter/f02_feedback/ARCHITECTURE.md';
      const oldTech = 'docs/specs/TECH_STACK.md';
      const newTech = 'docs/specs/flutter/TECH_STACK.md';

      String approvedAs(String docTypeId, String text) => withApprovalHash(
        text,
        TemplateResolver()
            .resolveCarried(
              packNames: const ['prd-core', 'software-tech'],
              homeDirectory: null,
            )
            .lookup(docTypeId),
      );

      Future<Directory> project() => gitFixture({
        '.specstone/config.yaml': twinConfig(),
        _gitignore: _ignoreFile,
        featurePath: approvedAs(
          'feature',
          '# Feedback\n\n[a](../../../specs/f02_feedback/ARCHITECTURE.md)\n',
        ),
        oldArch: approvedAs(
          'architecture',
          '# Architecture\n\n[f](../../prds/features/f02_feedback/FEATURE.md)\n',
        ),
        oldTech: '---\ndraft: true\n---\n# Tech stack\n',
      });

      test('a first commit that only moves the spec docs under '
          "the first target's folder, a second that rewrites their links, and "
          'every approval kept', () async {
        final home = await writeTree({});
        final root = await project();
        final before = _subjects(root);

        final dry = await _run(root, home, ['migrate', '--dry-run']);

        expect(dry.status, 0, reason: dry.err);
        expect(
          dry.out,
          startsWith('pack upgrade: pins unchanged, spec tree to flutter\n'),
        );
        expect(File('${root.path}/$newArch').existsSync(), isFalse);

        final result = await _run(root, home, ['migrate'], console: _owner());

        expect(result.status, 0, reason: result.err);
        expect(_subjects(root), hasLength(before.length + 2));
        final commit1 = _gitOut(root, [
          'show',
          '--name-status',
          '--format=',
          'HEAD~1',
        ]).trim().split('\n');
        expect(commit1, hasLength(2));
        expect(commit1, everyElement(startsWith('R100\t')));
        expect(
          commit1.join('\n'),
          allOf(contains('$oldArch\t$newArch'), contains('$oldTech\t$newTech')),
        );
        final commit2 = _gitOut(root, [
          'show',
          '--name-only',
          '--format=',
          'HEAD',
        ]).trim().split('\n').toSet();
        expect(commit2, {featurePath, newArch});
        expect(File('${root.path}/$oldArch').existsSync(), isFalse);
        expect(
          _read(root, featurePath),
          contains('](../../../specs/flutter/f02_feedback/ARCHITECTURE.md)'),
        );
        expect(
          _read(root, newArch),
          contains('](../../../prds/features/f02_feedback/FEATURE.md)'),
        );
        expect(_gitOut(root, ['status', '--porcelain']).trim(), isEmpty);
        for (final path in [featurePath, newArch]) {
          expect(_read(root, path), contains('approved: "'));
        }
        final check = await _run(root, home, ['check', '--json']);
        final stale = [
          for (final finding
              in (jsonDecode(check.out) as Map<String, Object?>)['findings']!
                  as List<Object?>)
            if (finding case {
              'kind': 'approval_stale',
              'path': final String docPath,
            })
              docPath,
        ];
        expect(stale, isEmpty);
        final again = await _run(root, home, ['migrate'], console: _owner());
        expect(again.out, 'nothing to migrate\n');
      });

      test('a tree move onto a path a doc already holds refuses with exit 65 '
          'and leaves the tree unwritten', () async {
        final home = await writeTree({});
        final root = await gitFixture({
          '.specstone/config.yaml': twinConfig(),
          _gitignore: _ignoreFile,
          featurePath: approvedAs(
            'feature',
            '# Feedback\n\n[a](../../../specs/f02_feedback/ARCHITECTURE.md)\n',
          ),
          oldArch: approvedAs(
            'architecture',
            '# Architecture\n\n[f](../../prds/features/f02_feedback/FEATURE.md)\n',
          ),
          newArch: approvedAs(
            'architecture',
            '# Architecture\n\n[f](../../../prds/features/f02_feedback/FEATURE.md)\n',
          ),
        });
        final before = _bytesUnder(root);
        final head = _head(root);

        for (final args in [
          ['migrate', '--dry-run'],
          ['migrate'],
        ]) {
          final result = await _run(root, home, args, console: _owner());

          expect(result.status, 65, reason: args.join(' '));
          expect(result.out, isEmpty, reason: args.join(' '));
          expect(
            result.err,
            startsWith('specs/f02_feedback/ARCHITECTURE.md: '),
            reason: args.join(' '),
          );
          expect(
            result.err,
            contains('specs/flutter/f02_feedback/ARCHITECTURE.md'),
            reason: args.join(' '),
          );
        }
        expect(_bytesUnder(root), before);
        expect(_head(root), head);
      });
    });
  }, skip: hasGit ? null : 'git is not available');

  group('migrate --add, in the built CLI', () {
    late String binary;

    setUpAll(() async {
      binary = await buildSpecstone();
    });

    Future<ProcessResult> migrate(
      Directory workingDirectory,
      List<String> args, {
      Directory? home,
    }) => runSpecstone(
      binary,
      ['migrate', ...args],
      workingDirectory: workingDirectory.path,
      environment: {
        'HOME': (home ?? testHome()).path,
        'USERPROFILE': (home ?? testHome()).path,
      },
    );

    test('an add value outside kebab-case exits 64 before any project is '
        'found', () async {
      final bare = await writeTree({'keep.txt': ''});

      final result = await migrate(bare, ['--add', 'My_Pack']);

      expect(result.exitCode, 64, reason: '${result.stdout}\n${result.stderr}');
      expect(
        result.stderr,
        startsWith('--add takes a pack name in kebab-case\n'),
      );
    });

    test(
      'an add value holding a comma exits 64 as outside kebab-case',
      () async {
        final bare = await writeTree({'keep.txt': ''});

        final result = await migrate(bare, ['--add', 'a,b']);

        expect(
          result.exitCode,
          64,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(
          result.stderr,
          startsWith('--add takes a pack name in kebab-case\n'),
        );
      },
    );

    test('a personal pack in the home folder passes the name '
        'checks', () async {
      final project = await gitFixture({
        '.specstone/config.yaml': shippedPinsConfig(),
      });
      final home = await writeTree({
        '.specstone/packs/mine/pack.yaml': 'name: mine\nversion: 1.0.0\n',
      });

      final result = await migrate(project, [
        '--dry-run',
        '--add',
        'mine',
      ], home: home);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        result.stdout,
        startsWith('pack upgrade: mine 1.0.0 (added)\ncommit 2, rewrites:\n'),
      );
      expect(result.stdout, contains('dry run: nothing written'));
    });

    Future<Directory> pinProject() => gitFixture({
      '.specstone/config.yaml': shippedPinsConfig(),
      _gitignore: _ignoreFile,
    });

    final planLine = RegExp(r'^plan ([0-9a-f]+)$', multiLine: true);
    final skills = shippedPackVersions()['agent-skills'];

    test('a dry run with an add prints its plan and hash and writes '
        'nothing', () async {
      final project = await pinProject();
      final before = _bytesUnder(project);

      final result = await migrate(project, [
        '--dry-run',
        '--add',
        'agent-skills',
      ]);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        result.stdout,
        startsWith('pack upgrade: agent-skills $skills (added)\n'),
      );
      expect(
        result.stdout,
        contains('  .specstone/config.yaml: agent-skills $skills (added)\n'),
      );
      expect(planLine.hasMatch(result.stdout as String), isTrue);
      expect(result.stdout, contains('dry run: nothing written'));
      expect(_bytesUnder(project), before);
    });

    test('a json dry run with an add carries addedPins', () async {
      final project = await pinProject();

      final result = await migrate(project, [
        '--dry-run',
        '--json',
        '--add',
        'agent-skills',
      ]);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final plan = jsonDecode(result.stdout as String) as Map<String, Object?>;
      expect(plan['addedPins'], [
        {'pack': 'agent-skills', 'version': skills},
      ]);
    });

    test('applying agent-skills over an untyped skill spec file leaves it a '
        'draft', () async {
      final project = await gitFixture({
        '.specstone/config.yaml': shippedPinsConfig(),
        'docs/specs/skills/review.md': '# Review\n\n## Purpose\n\nReviews.\n',
        _gitignore: _ignoreFile,
      });
      final dry = await migrate(project, [
        '--dry-run',
        '--add',
        'agent-skills',
      ]);
      expect(dry.stdout, contains('  typed by the add: 1 docs\n'));
      final hash = planLine.firstMatch(dry.stdout as String)!.group(1)!;

      final applied = await migrate(project, [
        '--yes',
        '--plan',
        hash,
        '--add',
        'agent-skills',
      ]);

      expect(
        applied.exitCode,
        0,
        reason: '${applied.stdout}\n${applied.stderr}',
      );
      final text = _read(project, 'docs/specs/skills/review.md');
      expect(text, startsWith('---\ndraft: true\n---\n'));
      expect(text, isNot(contains('approved:')));
    });

    test('the apply with the same adds pins agent-skills at the shipped '
        'version', () async {
      final project = await pinProject();
      final dry = await migrate(project, [
        '--dry-run',
        '--add',
        'agent-skills',
      ]);
      final hash = planLine.firstMatch(dry.stdout as String)!.group(1)!;

      final applied = await migrate(project, [
        '--yes',
        '--plan',
        hash,
        '--add',
        'agent-skills',
      ]);

      expect(
        applied.exitCode,
        0,
        reason: '${applied.stdout}\n${applied.stderr}',
      );
      expect(
        _read(project, '.specstone/config.yaml'),
        contains(
          '  software-tech: ${shippedPackVersions()['software-tech']}\n'
          '  agent-skills: $skills\n',
        ),
      );
      expect(_subjects(project).first, 'upgrade pack pins');
      expect(_gitOut(project, ['status', '--porcelain']).trim(), isEmpty);
    });

    test('adds in another order give the same hash, a repeated name '
        'included', () async {
      final project = await pinProject();
      final orders = [
        ['--add', 'marketing', '--add', 'agent-skills'],
        ['--add', 'agent-skills', '--add', 'marketing'],
        [
          '--add',
          'agent-skills',
          '--add',
          'agent-skills',
          '--add',
          'marketing',
        ],
      ];

      final outputs = [
        for (final order in orders)
          (await migrate(project, ['--dry-run', ...order])).stdout as String,
      ];

      expect(planLine.hasMatch(outputs.first), isTrue);
      expect(
        outputs.first,
        startsWith(
          'pack upgrade: agent-skills $skills (added), marketing '
          '${shippedPackVersions()['marketing']} (added)\n',
        ),
      );
      expect(outputs[1], outputs.first);
      expect(outputs[2], outputs.first);
    });

    test('the apply with a different add list is plan_mismatch', () async {
      final project = await pinProject();
      final dry = await migrate(project, [
        '--dry-run',
        '--add',
        'agent-skills',
      ]);
      final hash = planLine.firstMatch(dry.stdout as String)!.group(1)!;
      final before = _bytesUnder(project);

      final applied = await migrate(project, [
        '--yes',
        '--plan',
        hash,
        '--add',
        'marketing',
      ]);

      expect(
        applied.exitCode,
        75,
        reason: '${applied.stdout}\n${applied.stderr}',
      );
      expect(
        applied.stderr,
        startsWith('the plan is not the one the Owner saw in the dry run'),
      );
      expect(_bytesUnder(project), before);
    });
  });
  group('step patterns in a grouped project', () {
    test('a move_file that crosses the feature folder stops --dry-run and '
        'bare migrate with exit 78 and writes nothing', () async {
      final home = await _home(
        migrations: '''
migrations:
  - from: 1.0.0
    steps:
      - move_file: {doc_type: api, from: "specs/f{nn}_{slug}/API.md", to: "specs/apis/a{nn}_{slug}/API.md"}
''',
      );
      final root = await _project(
        files: {
          '.specstone/templates/feature.yaml':
              'path: prds/features/{slug}/f{nn}_{slug}/FEATURE.md\n',
          'docs/specs/ui/f01_button/API.md': '# Button\n',
        },
      );
      final before = _bytesUnder(root);
      final head = _head(root);

      for (final args in [
        ['migrate', '--dry-run'],
        ['migrate'],
      ]) {
        final result = await _run(root, home, args, console: _owner());

        expect(result.status, 78, reason: args.join(' '));
        expect(result.err, contains('migrations[0].steps[0].move_file.to'));
        expect(result.out, isEmpty, reason: args.join(' '));
      }
      expect(_bytesUnder(root), before);
      expect(_head(root), head);
    });

    test('the plan prints a grouped move_file step as the pack wrote it and '
        'counts the grouped docs', () async {
      final home = await _home(
        migrations: '''
migrations:
  - from: 1.0.0
    steps:
      - move_file: {doc_type: api, from: "specs/f{nn}_{slug}/API.md", to: "specs/f{nn}_{slug}/api/API.md"}
''',
        typeFile: 'api',
        type: 'path: specs/f{nn}_{slug}/api/API.md\n',
      );
      final root = await _project(
        files: {
          '.specstone/templates/feature.yaml':
              'path: prds/features/{slug}/f{nn}_{slug}/FEATURE.md\n',
          'docs/specs/ui/f01_button/API.md': '# Button\n',
          'docs/specs/ui/f02_field/API.md': '# Field\n',
        },
      );

      final dry = await _run(root, home, ['migrate', '--dry-run']);

      expect(dry.status, 0, reason: dry.err);
      expect(
        dry.out,
        contains(
          '  from 1.0.0: move_file api specs/f{nn}_{slug}/API.md -> '
          'specs/f{nn}_{slug}/api/API.md: 2 docs\n',
        ),
      );
      final json = await _run(root, home, ['migrate', '--dry-run', '--json']);
      final steps =
          (jsonDecode(json.out) as Map<String, Object?>)['steps']!
              as List<Object?>;
      expect(steps, [
        {
          'from': '1.0.0',
          'step':
              'move_file api specs/f{nn}_{slug}/API.md -> '
              'specs/f{nn}_{slug}/api/API.md',
          'paths': [
            'specs/ui/f01_button/api/API.md',
            'specs/ui/f02_field/api/API.md',
          ],
        },
      ]);
    });

    test('the plan prints a grouped merge_doc step as the pack wrote it and '
        'counts the grouped docs', () async {
      final home = await _home(
        migrations: '''
migrations:
  - from: 1.0.0
    steps:
      - merge_doc:
          from: {id: playbook, path: "specs/f{nn}_{slug}/PLAYBOOK.md"}
          to: api
          sections:
            - from: {id: moves, header: Moves}
              to: playbook_moves
''',
        typeFile: 'api',
        type: 'sections:\n  - {id: playbook_moves, header: Playbook moves}\n',
      );
      final root = await _project(
        files: {
          '.specstone/templates/feature.yaml':
              'path: prds/features/{slug}/f{nn}_{slug}/FEATURE.md\n',
          'docs/specs/ui/f01_button/PLAYBOOK.md':
              '# Button playbook\n\n## Moves\n\nRun it.\n',
          'docs/specs/ui/f01_button/API.md': '# Button\n',
        },
      );

      final dry = await _run(root, home, ['migrate', '--dry-run']);

      expect(dry.status, 0, reason: dry.err);
      expect(
        dry.out,
        contains('  from 1.0.0: merge_doc playbook -> api: 1 docs\n'),
      );
      final json = await _run(root, home, ['migrate', '--dry-run', '--json']);
      final steps =
          (jsonDecode(json.out) as Map<String, Object?>)['steps']!
              as List<Object?>;
      expect(steps, [
        {
          'from': '1.0.0',
          'step': 'merge_doc playbook -> api',
          'paths': ['specs/ui/f01_button/API.md'],
        },
      ]);
    });
  });
}
