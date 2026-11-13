import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';
import 'package:specstone_core/src/consistency_check/fingerprint.dart'
    show fingerprintOf, legacyFingerprintOf;
import 'package:specstone_core/src/doc_model/doc.dart' show Doc;
import 'package:specstone_core/src/document_writing/approval.dart'
    show withApprovalHash;
import 'package:specstone_core/src/setup_migration/agent_files.dart'
    show agentMdText;
import 'package:specstone_core/src/setup_migration/record_placement.dart'
    show typeBeforeMoves;
import 'package:specstone_core/src/templates/pack_migration.dart'
    show MoveToRecord;
import 'package:specstone_core/src/templates/shipped_pack_files.dart'
    show shippedPackVersions;
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/git_repo.dart';
import '../../../../specstone_core/test/helpers/legacy_fixture.dart';
import '../../../../specstone_core/test/helpers/record_fixture.dart'
    show recordLayer, twinConfig;
import '../../../../specstone_core/test/helpers/shipped_pins.dart';
import '../../../../specstone_core/test/helpers/temp_tree.dart';
import '../../helpers/write_runner.dart';

const _gitignore = '.specstone/.gitignore';
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

/// The temp personal-pack home holding `acme`.
Future<Directory> _home({
  String version = '1.2.0',
  String migrations = _renameMigrations,
  String type = '',
}) => writeTree({
  '.specstone/packs/acme/pack.yaml': _pack(version, migrations),
  '.specstone/packs/acme/runbook.yaml': type.isEmpty
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
  _gitignore: 'index.sqlite*\nbuild/\ntrash/\n',
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

void main() {
  group('f06/us02: upgrade a pack pin', () {
    test('f06/us02/s1, f06/us02/fr02/e01, f06/us01/fr07/e01: a release that '
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
      expect(_read(root, '.specstone/config.yaml'), _config('1.2.0'));
      expect(_gitOut(root, ['status', '--porcelain']).trim(), isEmpty);
    });

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

    test('f06/us02/s2: every doc of the type and the override carry the new '
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
      expect(_read(root, '.specstone/config.yaml'), _config('1.2.0'));
      expect(_subjects(root).first, 'upgrade pack pins');
      expect(_gitOut(root, ['status', '--porcelain']).trim(), isEmpty);
    });

    test('f06/us02/fr02/e04, f06/us02/s3: a release that moves files makes a '
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

    test('f06/us02/fr02/e06, f06/us02/s5: a removed section stays and check '
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

    test('setup_migration/upgrade_pack_pins/apply_steps_and_pins E11, '
        'setup_migration/migrate_legacy_docs/find_project_root E04: pins equal '
        'and one doc off its layout makes one layout-only commit, then a rerun '
        'has nothing to migrate', () async {
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

    test('f06/us02/s6: nothing to upgrade prints nothing to migrate and writes '
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
      'R51: with equal pins, an override that does not merge stops migrate '
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

    test('f06/us02/s7, f06/us02/fr01/e03: a pin newer than Specstone refuses', () async {
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

    test('f06/us02/s8, f06/us02/fr03/e05: an override left pointing at nothing '
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

    test('f06/us02/fr01/e06: a malformed migrations list refuses with the pack '
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

    test('f06/us01/fr07: a hook that prepends a paragraph to each message '
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

    test('f06/us01/fr07, f06/us02/fr02: an upgrade stopped after commit 1 '
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

    test('f06/us02/fr02/e08: a move onto a staying doc refuses in the dry '
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

    test('f06/us02/fr02/e08: a rename onto a header or key the doc already '
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

    test('f06/us02/fr02/e08: a swap composes onto one path and refuses at the '
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

    test('f06/us02/fr02/e08: a chained move through a freed path lands with no '
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

    test('f06/us02/fr02/e08, F6-D35: a chained move stopped after commit 1 '
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

    group('f06/us02/fr02/e08, F6-D34: a rotation through a temporary name', () {
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

      test('f06/us02/fr02/e08, F6-D34: trades the two docs and prints no '
          'stage path', () async {
        final result = await _run(root, home, ['migrate'], console: _owner());

        expect(result.status, 0, reason: result.err);
        expect(result.out, isNot(contains('.specstone/trash')));
        expectTraded();
      });

      test('f06/us02/fr02/e08, F6-D35: stopped after commit 1, resumes '
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

    group('setup_migration/upgrade_pack_pins agent files', () {
      const begin = '<!-- BEGIN specstone v$specstoneVersion -->';
      const staleBlock = '$begin\nold rules\n<!-- END specstone -->\n';
      const belowSince = 'packs:\n  prd-core: 1.0.0\n  software-tech: 1.0.0\n';

      Future<Directory> agentProject(
        Map<String, String> files,
        String config,
      ) => gitFixture({
        '.specstone/config.yaml': config,
        _gitignore: 'index.sqlite*\nbuild/\ntrash/\n',
        '.gitignore': 'code/\n',
        ...files,
      });

      test('user_story:setup_migration/upgrade_pack_pins S9: a stale block is '
          'rewritten alone and the pins stay', () async {
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
          _gitOut(root, ['show', '--name-only', '--format=', 'HEAD']).trim(),
          'CLAUDE.md',
        );
        expect(_read(root, '.specstone/config.yaml'), config);
        expect(
          _read(root, 'CLAUDE.md'),
          startsWith('# Owner rules\n\n$begin\n'),
        );
        expect(_read(root, 'CLAUDE.md'), isNot(contains('old rules')));
      });

      test(
        'user_story:setup_migration/upgrade_pack_pins S10: a mixed pair '
        'with one pin below agentFilesSince triggers the one-time write',
        () async {
          final root = await agentProject({
            'CLAUDE.md': '# Owner rules\n',
          }, 'packs:\n  prd-core: 1.6.9\n  software-tech: 1.3.0\n');
          final home = await writeTree({});

          final result = await _run(root, home, ['migrate'], console: _owner());

          expect(result.status, 0, reason: result.err);
          expect(result.out, contains('  agent files: 2 files\n'));
          expect(_read(root, 'CLAUDE.md'), startsWith('# Owner rules\n'));
          expect(_read(root, 'CLAUDE.md'), contains(begin));
        },
      );

      test('user_story:setup_migration/upgrade_pack_pins S10: a pin below '
          'agentFilesSince writes the files once and a deleted block stays '
          'deleted', () async {
        final root = await agentProject({
          'CLAUDE.md': '# Owner rules\n',
        }, belowSince);
        final home = await writeTree({});

        final first = await _run(root, home, ['migrate'], console: _owner());

        expect(first.status, 0);
        expect(first.out, contains('  agent files: 2 files\n'));
        expect(_read(root, 'CLAUDE.md'), startsWith('# Owner rules\n'));
        expect(_read(root, 'CLAUDE.md'), contains(begin));
        expect(_read(root, '.specstone/AGENT.md'), agentMdText);
        expect(
          _gitOut(root, [
            'show',
            '--name-only',
            '--format=',
            'HEAD',
          ]).trim().split('\n').toSet(),
          {'.specstone/AGENT.md', 'CLAUDE.md', '.specstone/config.yaml'},
        );

        File('${root.path}/CLAUDE.md').writeAsStringSync('# Owner rules\n');
        commitAll(root, 'owner deletes the block');
        final second = await _run(root, home, ['migrate'], console: _owner());

        expect(second.out, 'nothing to migrate\n');
        expect(_read(root, 'CLAUDE.md'), '# Owner rules\n');
      });

      test('user_story:setup_migration/upgrade_pack_pins S10: a top the config '
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
        expect(result.out, contains('  agent files: 1 files\n'));
        expect(File('${root.path}/code/AGENTS.md').existsSync(), isTrue);
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

      test('setup_migration/upgrade_pack_pins E16: a malformed file refuses '
          'before anything prints', () async {
        final root = await agentProject({
          'AGENTS.md': '$begin\nbody\n',
        }, belowSince);
        final home = await writeTree({});

        final result = await _run(root, home, ['migrate', '--dry-run']);

        expect(result.status, 65);
        expect(result.out, isEmpty);
        expect(result.err, contains('AGENTS.md'));
      });
    });

    group('setup_migration/upgrade_pack_pins renumber pass', () {
      const fr = 'setup_migration/upgrade_pack_pins/apply_steps_and_pins';
      const topicPath = 'docs/specs/topics/doc_model.md';
      const storyPath = 'docs/prds/features/f01_a/us01_b/USER_STORY.md';
      const tracingPath = 'docs/prds/features/f01_a/us01_b/fr01_c.md';
      const suspectPath = 'docs/prds/features/f01_a/us01_b/fr02_g.md';
      const proseTracingPath = 'docs/prds/features/f01_a/us01_b/fr03_h.md';
      const apiPath = 'docs/specs/f01_a/API.md';
      const lettered = '### Scenario 6a — [edge] lettered\n\n- **Given** g';
      const eight =
          '### Scenario 8 — [error] eight, unlike Scenario 6a\n\n- **Given** g';
      const topic =
          '# Doc model\n\n## Rules\n\n- **RULE-1** — One.\n'
          '- **RULE-7a** — Lettered.\n- **RULE-30** — Thirty.\n';

      String tracing(
        String fingerprint, {
        String scenario = 'S6a',
        String body = '',
      }) =>
          '---\ntraced_from:\n  - $scenario\nconfirmed:\n'
          '  - $scenario $fingerprint\n---\n# C\n$body';

      /// The `docPath` of each finding of [kind] a `check --json` run reports.
      Future<List<Object?>> findingsOf(
        Directory root,
        Directory home,
        String kind,
      ) async {
        final check = await _run(root, home, ['check', '--json']);
        expect(check.out, isNotEmpty, reason: check.err);
        final report = jsonDecode(check.out) as Map<String, Object?>;
        return [
          for (final finding in report['findings']! as List<Object?>)
            if (finding case {'kind': final String found, 'docPath': final path}
                when found == kind)
              path,
        ];
      }

      test('$fr E18: the first check after the run raises no item_id_lettered '
          'and no suspect link the pass made, a later upgrade renumbers '
          'nothing, and a lettered ID written after it gets the '
          'finding', () async {
        final citing = tracing(
          fingerprintOf(lettered),
          body: '\n## Statement\n\n`doc_model` RULE-7a\n',
        );
        final statement = Doc.parse(citing).sections.single.body;
        final root = await gitFixture({
          '.specstone/config.yaml':
              'packs:\n  prd-core: 1.0.0\n  software-tech: 1.0.0\n',
          _gitignore: 'index.sqlite*\nbuild/\ntrash/\n',
          topicPath: topic,
          'docs/prds/features/f01_a/FEATURE.md': '# A\n',
          storyPath:
              '# B\n\n## Acceptance Criteria\n\n### Scenario 1 — [happy] one'
              '\n\n- **Given** g\n\n$eight\n\n$lettered\n',
          tracingPath: citing,
          suspectPath: tracing('000000000000'),
          proseTracingPath: tracing(fingerprintOf(eight), scenario: 'S8'),
          apiPath:
              '---\nconfirmed:\n  - b/c ${fingerprintOf(statement)}\n---\n'
              '# A\n\n## FR trace\n\n| FR | Operation |\n|----|-----------|\n'
              '| b/c | get |\n',
        });
        final home = await writeTree({});

        final result = await _run(root, home, ['migrate'], console: _owner());

        expect(result.status, 0, reason: result.err);
        expect(result.out, contains('  renumber ids: 2 IDs in 4 docs\n'));
        // The renumber pass renames labels only; the stamp pass re-stamps
        // the two entries, so their docs are on its line, not the references.
        expect(
          result.out,
          contains('  stamps: 7 approval hashes, 3 fingerprints\n'),
        );
        expect(_read(root, tracingPath), contains('`doc_model` RULE-31\n'));
        expect(_read(root, storyPath), contains('unlike Scenario 9\n'));
        expect(await findingsOf(root, home, 'item_id_lettered'), isEmpty);
        expect(await findingsOf(root, home, 'suspect'), [
          suspectPath.substring(5),
        ]);

        final rerun = await _run(root, home, ['migrate'], console: _owner());
        expect(rerun.out, 'nothing to migrate\n');

        void edit(String path, String from, String to) =>
            File('${root.path}/$path')
                .writeAsStringSync(_read(root, path).replaceFirst(from, to));
        edit(
          topicPath,
          '- **RULE-30**',
          '- **RULE-40b** — New.\n- **RULE-30**',
        );
        // The two re-stamped links are live: an edit upstream makes each
        // suspect.
        edit(storyPath, 'unlike Scenario 9', 'unlike Scenario 1');
        edit(tracingPath, '`doc_model` RULE-31', '`doc_model` RULE-1');
        expect(await findingsOf(root, home, 'item_id_lettered'), [
          topicPath.substring(5),
        ]);
        expect(
          await findingsOf(root, home, 'suspect'),
          unorderedEquals([
            for (final path in [suspectPath, proseTracingPath, apiPath])
              path.substring(5),
          ]),
        );
      });

      test('$fr E18 (W15): an upgrade over every renumber case raises no '
          'finding of any kind the tree lacked before, and a second upgrade '
          'changes nothing', () async {
        const anchor = 'scenario-6a--edge-lettered';
        const story =
            '---\ngoals: [PG-2a]\n---\n# B\n\n## Acceptance Criteria\n\n'
            '### Scenario 1 — [happy] one\n\n- **Given** g\n\n'
            '### Scenario 8 — [error] eight\n\n- **Given** g\n\n'
            '$lettered\n\nSee [it](#$anchor), S6a.\n';
        final blockFingerprint = fingerprintOf(
          '$lettered\n\nSee [it](#$anchor), S6a.',
        );
        const paddedStory =
            '# E\n\n## Acceptance Criteria\n\n'
            '### Scenario 01 — [happy] one\n\n- **Given** g\n\n'
            '### Scenario 08 — [error] eight\n\n- **Given** g\n\n'
            '$lettered\n';
        final docs = {
          'docs/prds/PROJECT.md':
              '# P\n\n## Project vision\n\n### PV-01 — One\n\n'
              '### PV-1a — Lettered\n\n## Project goals\n\n'
              '### PG-01 — One\n\n**Serves:** PV-01\n\n'
              '### PG-2a — Two\n\n**Serves:** PV-1a\n',
          'docs/prds/GNFR.md':
              '# G\n\n## Performance\n\n### NFR-P07 — Seven\n\n'
              '- **Statement:** s7\n\n### NFR-P06a — Latency\n\n'
              '- **Statement:** s6a\n',
          'docs/prds/features/f01_a/FEATURE.md':
              '---\nvision: [PV-1a]\ngoals: [PG-2a]\n---\n# A\n',
          storyPath: story,
          tracingPath:
              '---\ntraced_from:\n  - S6a\nconfirmed:\n'
              '  - S6a $blockFingerprint\n---\n# C\n\n## Statement\n\n'
              'See [the lockout](USER_STORY.md#$anchor) and S6a.\n',
          suspectPath:
              '---\ntraced_from: [S6]\nconfirmed:\n  - S6 $blockFingerprint\n'
              '---\n# G\n',
          'docs/prds/features/f01_a/us01_b/nf01_d.md':
              '---\nkind: tighten\noverrides: NFR-P06a\nconfirmed:\n'
              '  - NFR-P06a ${fingerprintOf('- **Statement:** s6a')}\n'
              '---\n# D\n',
          'docs/prds/journeys/onboard/JOURNEY.md':
              '---\nconfirmed:\n  - a/b#S6a $blockFingerprint\n---\n'
              '# Onboard\n\n## Steps\n\n### 1. Start\nstep: a/b S6a\n',
          'docs/prds/notes.md':
              '# Notes\n\n[latency](GNFR.md#nfr-p06a--latency)\n',
          'docs/prds/features/f01_a/us02_e/USER_STORY.md': paddedStory,
          'docs/prds/journeys/padded/JOURNEY.md':
              '---\nconfirmed:\n  - a/e#S6a ${fingerprintOf(lettered)}\n---\n'
              '# Padded\n\n## Steps\n\n### 1. Start\nstep: a/e S6a\n',
          topicPath:
              '# Doc model\n\n## Purpose\n\n'
              '[RULE-7a](https://example.com/RULE-7a.md) and '
              '<https://example.com/RULE-7a>, `RULE-7a`.\n\n'
              '## Rules\n\n- **RULE-1** — One.\n- **RULE-7a** — Lettered.\n'
              '- **RULE-9a2** — Odd.\n- **RULE-30** — Thirty.\n',
          'docs/specs/f01_a/DOMAIN.md':
              '# A\n\n## Invariants\n\n'
              '[rules](../topics/doc_model.md) RULE-7a, '
              '[latency](../../prds/GNFR.md#nfr-p06a--latency).\n',
          'docs/specs/f01_a/ARCHITECTURE.md':
              '# A\n\n## Concerns\n\n- Errors — see '
              '../../prds/features/f01_a/us01_b/USER_STORY.md#$anchor\n',
        };
        Future<Set<String>> findings(Directory root, Directory home) async {
          final check = await _run(root, home, ['check', '--json']);
          final report = jsonDecode(check.out) as Map<String, Object?>;
          return {
            for (final finding in report['findings']! as List<Object?>)
              if (finding case {'kind': final kind, 'docPath': final path})
                '$kind $path',
          };
        }

        final home = await writeTree({});
        final before = await findings(
          await gitFixture({
            '.specstone/config.yaml': shippedPinsConfig(),
            _gitignore: 'index.sqlite*\nbuild/\ntrash/\n',
            ...docs,
          }),
          home,
        );
        final root = await gitFixture({
          '.specstone/config.yaml':
              'packs:\n  prd-core: 1.0.0\n  software-tech: 1.0.0\n',
          _gitignore: 'index.sqlite*\nbuild/\ntrash/\n',
          ...docs,
        });

        final result = await _run(root, home, ['migrate'], console: _owner());

        expect(result.status, 0, reason: result.err);
        expect(before, contains('item_id_lettered specs/topics/doc_model.md'));
        expect(
          before,
          contains('reference_malformed specs/topics/doc_model.md'),
        );
        expect(
          _read(root, 'docs/prds/journeys/padded/JOURNEY.md'),
          allOf(contains('  - a/e#S09 '), contains('step: a/e S09\n')),
        );
        expect(
          _read(root, 'docs/specs/f01_a/ARCHITECTURE.md'),
          contains('USER_STORY.md#scenario-9--edge-lettered\n'),
        );
        final after = await findings(root, home);
        expect(after.difference(before), isEmpty);
        expect(
          after.where((finding) => finding.startsWith('item_id_lettered')),
          isEmpty,
        );
        final rerun = await _run(root, home, ['migrate'], console: _owner());
        expect(rerun.out, 'nothing to migrate\n');
      });
    });

    group('setup_migration/upgrade_pack_pins label pass', () {
      const fr = 'setup_migration/upgrade_pack_pins/apply_steps_and_pins';

      test('$fr E26, E27: the run converts a label in a doc, keeps the rest '
          'listed, and reads no file under the code roots', () async {
        final home = await writeTree({});
        final root = await gitFixture({
          '.specstone/config.yaml':
              'packs:\n  prd-core: 1.0.0\n  software-tech: 1.0.0\n',
          _gitignore: 'index.sqlite*\nbuild/\ntrash/\n',
          'docs/specs/TECH_STACK.md':
              '---\ncode:\n  - lib/\n---\n# Tech stack\n',
          'docs/prds/features/f01_a/FEATURE.md': '# A\n',
          'docs/prds/features/f01_a/us01_b/USER_STORY.md': '# B\n',
          'docs/prds/features/f01_a/us01_b/fr01_c.md': '# C\n',
          'docs/specs/topics/labelled.md':
              '# Labelled\n\n## Rules\n\nSee F-01 US-01 FR-01 and FR-09.\n',
          'lib/a.dart': '// See F-01 US-01 and FR-01\nint a = 0;\n',
        });

        final result = await _run(root, home, ['migrate'], console: _owner());

        expect(result.status, 0, reason: result.err);
        expect(
          result.out,
          contains('  number labels: 1 rewrites in 1 files; left: 1\n'),
        );
        expect(
          _read(root, 'docs/specs/topics/labelled.md'),
          contains('See `a/b/c` and FR-09.\n'),
        );
        expect(
          _read(root, 'docs/specs/topics/labelled.md').split('\n')[8],
          contains('FR-09'),
        );
        expect(
          _read(root, 'lib/a.dart'),
          '// See F-01 US-01 and FR-01\nint a = 0;\n',
        );
        final committed = _gitOut(root, [
          'show',
          '--name-only',
          '--format=',
          'HEAD',
        ]);
        expect(committed, isNot(contains('lib/a.dart')));
        expect(committed, contains('docs/specs/topics/labelled.md'));
        expect(_gitOut(root, ['status', '--porcelain']).trim(), isEmpty);
      });
    });

    group('setup_migration/upgrade_pack_pins item limit', () {
      const fr = 'setup_migration/upgrade_pack_pins/apply_steps_and_pins';

      test('$fr E32: the upgrade of E14 keeps an over-limit invariant as one '
          'item, and the first check reports it with waitsFor owner', () async {
        const domainPath = 'docs/specs/f01_a/DOMAIN.md';
        final invariant = '- **INV-1** ${'A long rule'.padRight(15600, '.')}';
        final domain =
            '# A domain\n\n## Entities\n\n'
            '| Entity | Kind | Identity | Owns | Notes |\n'
            '| --- | --- | --- | --- | --- |\n'
            '| Account | Aggregate root | id | balance | - |\n\n'
            '## Invariants\n\n$invariant\n'
            '  - **Enforcer:** Account\n'
            '  - **Consistency:** immediate\n';
        Future<List<Map<String, Object?>>> overLimit(
          Directory root,
          Directory home,
        ) async {
          final check = await _run(root, home, ['check', '--json']);
          final report = jsonDecode(check.out) as Map<String, Object?>;
          return [
            for (final finding in report['findings']! as List<Object?>)
              if (finding case {'kind': 'item_over_limit'} && final item)
                item as Map<String, Object?>,
          ];
        }

        final home = await writeTree({});
        final root = await gitFixture({
          '.specstone/config.yaml':
              'packs:\n  prd-core: 1.0.0\n  software-tech: 1.0.0\n',
          _gitignore: 'index.sqlite*\nbuild/\ntrash/\n',
          'docs/prds/features/f01_a/FEATURE.md': '# A\n',
          domainPath: domain,
        });

        final result = await _run(root, home, ['migrate'], console: _owner());

        expect(result.status, 0, reason: result.err);
        expect(_read(root, '.specstone/config.yaml'), shippedPinsConfig());
        final lines = _read(root, domainPath).split('\n');
        expect(lines.where((line) => line.startsWith('- **INV-')), [invariant]);
        expect(lines, contains('  - **Enforcer:** Account'));
        expect(lines, contains('  - **Consistency:** immediate'));
        final after = await overLimit(root, home);
        expect(after, hasLength(1));
        expect(after.single, containsPair('section', 'invariants'));
        expect(after.single, containsPair('id', 'INV-1'));
        expect(after.single, containsPair('waitsFor', 'owner'));
        expect(after.single, containsPair('limit', 600));
        expect(after.single, containsPair('actual', invariant.length));
      });
    });

    group('setup_migration/upgrade_pack_pins stamp pass', () {
      const fr = 'setup_migration/upgrade_pack_pins/apply_steps_and_pins';

      test('$fr E30, E31: the first check after the upgrade of a 1.1.0 tree '
          'raises no suspect and no approval_stale', () async {
        const table =
            '### Scenario 1 — [happy] Table\n| Item | Count |\n| --- | --- |\n'
            '| apple | 2 |';
        const storyPath = 'docs/prds/features/f01_a/us01_b/USER_STORY.md';
        const frPath = 'docs/prds/features/f01_a/us01_b/fr01_c.md';
        const draftPath = 'docs/prds/features/f01_a/us01_b/fr02_d.md';
        final docs = {
          storyPath:
              '---\napproved: true\n---\n# B\n\n'
              '## Acceptance Criteria\n\n$table\n',
          frPath:
              '---\ntraced_from: [S1]\nconfirmed:\n'
              '  - S1 ${legacyFingerprintOf(table)}\n---\n# C\n',
          draftPath: '---\ndraft: true\ntraced_from: [S1]\n---\n# D\n',
        };
        Future<List<Object?>> findings(Directory root, Directory home) async {
          final check = await _run(root, home, ['check', '--json']);
          final report = jsonDecode(check.out) as Map<String, Object?>;
          return report['findings']! as List<Object?>;
        }

        final home = await writeTree({});
        final root = await gitFixture({
          '.specstone/config.yaml':
              'packs:\n  prd-core: 1.0.0\n  software-tech: 1.0.0\n',
          _gitignore: 'index.sqlite*\nbuild/\ntrash/\n',
          ...docs,
        });

        final result = await _run(root, home, ['migrate'], console: _owner());

        expect(result.status, 0, reason: result.err);
        expect(
          result.out,
          contains('stamps: 2 approval hashes, 1 fingerprints'),
        );
        expect(_read(root, frPath), contains('S1 ${fingerprintOf(table)}\n'));
        expect(_read(root, draftPath), docs[draftPath]);
        final kinds = [
          for (final finding in await findings(root, home))
            if (finding case {'kind': final String kind}) kind,
        ];
        expect(kinds, isNot(contains('suspect')));
        expect(kinds, isNot(contains('approval_stale')));
        final rerun = await _run(root, home, ['migrate'], console: _owner());
        expect(rerun.out, 'nothing to migrate\n');
      });
    });

    group('f06/us02: status and code paths move into records', () {
      const featurePath = 'docs/prds/features/f01_login/FEATURE.md';
      const storyPath =
          'docs/prds/features/f01_login/us01_email_login/USER_STORY.md';
      const frPath =
          'docs/prds/features/f01_login/us01_email_login/'
          'fr01_validate_credentials.md';
      const recordPath = 'docs/specs/f01_login/IMPLEMENTATION.md';
      const story =
          '---\nstatus: implemented\nimplements:\n'
          '  - app/lib/login/sign_in.dart:SignIn\n---\n# Email login\n';
      const fr = '---\nstatus: planned\n---\n# Validate credentials\n';

      Future<Directory> home() => writeTree({
        '.specstone/packs/acme/pack.yaml': _pack(
          '1.2.0',
          'migrations:\n'
              '  - from: 1.0.0\n'
              '    steps:\n'
              '      - move_to_record: {doc_types: [user_story, fr], '
              'fields: [status, implements], to: implementation}\n',
        ),
        '.specstone/packs/acme/implementation.yaml': recordLayer,
      });

      Future<Directory> project({
        String storyText = story,
        String frText = fr,
      }) => _project(
        files: {featurePath: '# Login\n', storyPath: storyText, frPath: frText},
      );

      // Approved as the shipped pack stood before the step: the type still
      // declared `implements`, a field the hash leaves out.
      String approved(String text, String docTypeId) => withApprovalHash(
        text,
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

      String planHash(String dryOut) {
        final lines = dryOut.split('\n');
        return lines[lines.length - 3].substring('plan '.length);
      }

      test('f06/us02/s11: the dry run lists the record, and the run writes it '
          'as a draft with the values the docs held', () async {
        final h = await home();
        final root = await project();

        final dry = await _run(root, h, ['migrate', '--dry-run']);

        expect(dry.status, 0, reason: dry.err);
        expect(
          dry.out,
          contains(
            'from 1.0.0: move_to_record user_story, fr status, implements '
            '-> implementation: 2 docs\n',
          ),
        );
        expect(
          dry.out,
          contains('commit 2, creates:\n  specs/f01_login/IMPLEMENTATION.md '),
        );
        expect(File('${root.path}/$recordPath').existsSync(), isFalse);

        final applied = await _run(root, h, [
          'migrate',
          '--yes',
          '--plan',
          planHash(dry.out),
        ]);

        expect(applied.status, 0, reason: applied.err);
        final record = _read(root, recordPath);
        expect(record, contains('draft: true'));
        expect(record, contains("'email_login:implemented'"));
        expect(record, contains("'email_login/validate_credentials:planned'"));
        expect(
          record,
          contains("'email_login:app/lib/login/sign_in.dart:SignIn'"),
        );
        for (final path in [storyPath, frPath]) {
          expect(_read(root, path), isNot(contains('status:')));
          expect(_read(root, path), isNot(contains('implements:')));
        }
        expect(_subjects(root).first, 'upgrade pack pins');
        expect(_gitOut(root, ['status', '--porcelain']).trim(), isEmpty);
      });

      test('f06/us02/s11: a story and an FR approved before the run are still '
          'approved after it', () async {
        final h = await home();
        final root = await project(
          storyText: approved(story, 'user_story'),
          frText: approved(fr, 'fr'),
        );

        final result = await _run(root, h, ['migrate'], console: _owner());

        expect(result.status, 0, reason: result.err);
        for (final path in [storyPath, frPath]) {
          expect(_read(root, path), contains('approved: "'));
        }
        final check = await _run(root, h, ['check', '--json']);
        final report = jsonDecode(check.out) as Map<String, Object?>;
        final stale = [
          for (final finding in report['findings']! as List<Object?>)
            if (finding case {
              'kind': 'approval_stale',
              'docPath': final String docPath,
            })
              docPath,
        ];
        expect(stale, isNot(contains(storyPath.substring('docs/'.length))));
        expect(stale, isNot(contains(frPath.substring('docs/'.length))));
      });

      test('f06/us02/fr02/e36: a record override the plan lists lands in '
          'commit 2 with the pins', () async {
        final h = await home();
        final root = await _project(
          files: {
            featurePath: '# Login\n',
            '.specstone/templates/architecture.yaml':
                'path: specs/{slug}/f{nn}_{slug}/ARCHITECTURE.md\n',
          },
        );

        final result = await _run(root, h, ['migrate'], console: _owner());

        expect(result.status, 0, reason: result.err);
        expect(
          result.out,
          contains('commit 2, creates:\n  .specstone/templates/'),
        );
        expect(
          _read(root, '.specstone/templates/implementation.yaml'),
          'path: specs/{slug}/f{nn}_{slug}/IMPLEMENTATION.md\n',
        );
        expect(
          _gitOut(root, ['show', '--name-only', '--format=', 'HEAD']),
          contains('.specstone/templates/implementation.yaml'),
        );
        expect(_gitOut(root, ['status', '--porcelain']).trim(), isEmpty);
      });

      test('f06/us02/s13: a value no record entry takes refuses on the dry '
          'run and the bare run alike, and writes nothing', () async {
        final h = await home();
        final root = await project(
          storyText: '---\nstatus: wip\n---\n# Email login\n',
        );
        final before = _head(root);

        final dry = await _run(root, h, ['migrate', '--dry-run']);
        final bare = await _run(root, h, ['migrate'], console: _owner());

        for (final result in [dry, bare]) {
          expect(result.status, 65, reason: result.err);
          expect(
            result.err,
            startsWith('${storyPath.substring('docs/'.length)}: status: '),
          );
        }
        expect(_head(root), before);
        expect(_gitOut(root, ['status', '--porcelain']).trim(), isEmpty);
        expect(File('${root.path}/$recordPath').existsSync(), isFalse);
      });
    });

    group('f06/us02: the shipped software-tech 1.5.0 record', () {
      const featurePath = 'docs/prds/features/f01_login/FEATURE.md';
      const storyPath =
          'docs/prds/features/f01_login/us01_email_login/USER_STORY.md';
      const frPath =
          'docs/prds/features/f01_login/us01_email_login/'
          'fr01_validate_credentials.md';
      const recordPath = 'docs/specs/f01_login/IMPLEMENTATION.md';

      Future<Directory> project(String storyText) => gitFixture({
        '.specstone/config.yaml':
            'packs:\n  prd-core: ${shippedPackVersions()['prd-core']}\n'
            '  software-tech: 1.4.0\n',
        _gitignore: 'index.sqlite*\nbuild/\ntrash/\n',
        featurePath: '# Login\n',
        storyPath: storyText,
        frPath: '---\nstatus: planned\n---\n# Validate credentials\n',
      });

      test('f06/us02/s11: a 1.4.0 project moves its values into a draft '
          'record of the shipped implementation type, with no one-time '
          'pass', () async {
        final h = await writeTree({});
        final root = await project(
          '---\nstatus: implemented\nimplements:\n'
          '  - app/lib/login/sign_in.dart:SignIn\n---\n# Email login\n',
        );

        final dry = await _run(root, h, ['migrate', '--dry-run']);

        expect(dry.status, 0, reason: dry.err);
        expect(dry.out, contains('software-tech 1.4.0 -> 1.5.0'));
        expect(
          dry.out,
          contains(
            'from 1.4.0: move_to_record user_story, fr status, implements '
            '-> implementation: 2 docs\n',
          ),
        );
        expect(dry.out, isNot(contains('renumber ids:')));
        expect(dry.out, isNot(contains('agent files:')));

        final lines = dry.out.split('\n');
        final applied = await _run(root, h, [
          'migrate',
          '--yes',
          '--plan',
          lines[lines.length - 3].substring('plan '.length),
        ]);

        expect(applied.status, 0, reason: applied.err);
        final record = _read(root, recordPath);
        expect(record, contains('draft: true'));
        expect(record, contains("'email_login:implemented'"));
        expect(
          record,
          contains("'email_login:app/lib/login/sign_in.dart:SignIn'"),
        );
        expect(_read(root, storyPath), isNot(contains('status:')));
        expect(_read(root, frPath), isNot(contains('status:')));
        final check = await _run(root, h, ['check', '--json']);
        final kinds = [
          for (final finding
              in (jsonDecode(check.out) as Map<String, Object?>)['findings']!
                  as List<Object?>)
            (finding! as Map<String, Object?>)['kind'],
        ];
        expect(kinds, isNot(contains('field_undeclared')));
        expect(kinds, isNot(contains('requirement_status_written')));
      });

      test('f06/us02/s13: a status no entry takes refuses the shipped run '
          'and writes nothing', () async {
        final h = await writeTree({});
        final root = await project('---\nstatus: wip\n---\n# Email login\n');
        final before = _head(root);

        final dry = await _run(root, h, ['migrate', '--dry-run']);

        expect(dry.status, 65, reason: dry.err);
        expect(
          dry.err,
          startsWith('${storyPath.substring('docs/'.length)}: status: '),
        );
        expect(_head(root), before);
        expect(File('${root.path}/$recordPath').existsSync(), isFalse);
      });
    });

    group('f06/us02: a second code target over a one-target spec tree', () {
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
        _gitignore: 'index.sqlite*\nbuild/\ntrash/\n',
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

      test('f06/us02/s12: a first commit that only moves the spec docs under '
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
              'docPath': final String docPath,
            })
              docPath,
        ];
        expect(stale, isEmpty);
        final again = await _run(root, home, ['migrate'], console: _owner());
        expect(again.out, 'nothing to migrate\n');
      });
    });
  }, skip: hasGit ? null : 'git is not available');
}
