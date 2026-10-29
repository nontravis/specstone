import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/git_repo.dart';
import '../../../../specstone_core/test/helpers/legacy_fixture.dart';
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

Map<String, String> _bytesUnder(Directory root) => {
  for (final entity in root.listSync(recursive: true, followLinks: false))
    if (entity is File &&
        !entity.path.contains(
          '${Platform.pathSeparator}.git${Platform.pathSeparator}',
        ))
      entity.path: entity.readAsStringSync(),
};

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
        endsWith(
          'commit 2 ${_head(root).substring(0, 7)}: upgrade pack pins\n',
        ),
      );
      expect(_read(root, '.specstone/config.yaml'), _config('1.2.0'));
      expect(_gitOut(root, ['status', '--porcelain']).trim(), isEmpty);
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

    test('f06/us02/s6: nothing to upgrade prints nothing to migrate and writes '
        'nothing', () async {
      final home = await _home(version: '1.0.0', migrations: '');
      final root = await _project();
      final before = _bytesUnder(root);

      final result = await _run(root, home, ['migrate'], console: _owner());

      expect(result.status, 0);
      expect(result.out, 'nothing to migrate\n');
      expect(_bytesUnder(root), before);
    });

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
        'resumes with its own output and no legacy closing line', () async {
      final home = await _home(
        migrations: _moveMigrations,
        type: _runbookType('ops/runbooks/{slug}/RUNBOOK.md', 'steps'),
      );
      final root = await _project(files: {_runbookPath: _runbookDoc});
      final hook = File('${root.path}/.git/hooks/commit-msg')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          '#!/bin/sh\ngrep -q "upgrade pack pins" "\$1" && exit 1\nexit 0\n',
        );
      expect(Process.runSync('chmod', ['755', hook.path]).exitCode, 0);

      final stopped = await _run(root, home, ['migrate'], console: _owner());
      expect(stopped.status, 75, reason: stopped.err);
      expect(_subjects(root).first, 'move docs to their new pack paths');
      hook.deleteSync();

      final resumed = await _run(root, home, ['migrate'], console: _owner());

      expect(resumed.status, 0, reason: resumed.err);
      expect(_subjects(root).first, 'upgrade pack pins');
      expect(resumed.out, contains('commit 2 '));
      expect(resumed.out, isNot(contains('specstone check')));
      expect(_gitOut(root, ['status', '--porcelain']).trim(), isEmpty);
    }, skip: Platform.isWindows ? 'the hook is a sh script' : null);
  }, skip: hasGit ? null : 'git is not available');
}
