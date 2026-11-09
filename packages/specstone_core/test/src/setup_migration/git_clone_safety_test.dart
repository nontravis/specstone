import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/document_writing/owner_confirmation.dart';
import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/setup_migration/git_gate.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/migrate_run.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/git_repo.dart';
import '../../helpers/legacy_fixture.dart';
import '../../helpers/relative_link.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart' show testHome;

const _scope = 'setup_migration/choose_migrate_run';

final String? _skip = !hasGit
    ? 'git is not available'
    : Platform.isWindows
    ? 'a link needs a privilege on Windows'
    : null;

/// A `RunGit` that starts git as an older release would, with no
/// `safe.bareRepository` config, and prints [version] for `--version`.
RunGit _olderGit(String version) =>
    (arguments, {required workingDirectory}) => arguments.first == '--version'
    ? ProcessResult(0, 0, '$version\n', '')
    : Process.runSync(
        'git',
        arguments,
        workingDirectory: workingDirectory,
        stdoutEncoding: utf8,
      );

/// Builds a clone whose `evil/` folder is a committed git dir laid out as a
/// work tree's `.git`, holding a legacy project, with `config` set to
/// [configLines]; `docs` at the clone root links to `evil/docs`.
///
/// Returns the clone, the root `migrate` runs from.
Future<Directory> _evilClone(List<(String, String)> configLines) async {
  final base = await writeTree({
    'clone/keep.txt': '',
    for (final MapEntry(:key, :value) in acmeLegacy.entries)
      'clone/evil/$key': value,
  });
  final clone = Directory('${base.path}/clone');
  final evil = Directory('${clone.path}/evil');
  commitRepo(evil);
  final dotGit = Directory('${evil.path}/.git');
  for (final entry in dotGit.listSync()) {
    entry.renameSync(
      '${evil.path}/${entry.uri.pathSegments.where((s) => s.isNotEmpty).last}',
    );
  }
  dotGit.deleteSync(recursive: true);
  for (final (key, value) in [
    ('core.bare', 'false'),
    ('core.worktree', '..'),
    ...configLines,
  ]) {
    expect(
      Process.runSync('git', [
        'config',
        '-f',
        '${evil.path}/config',
        key,
        value,
      ]).exitCode,
      0,
    );
  }
  createRelativeLink('${clone.path}/docs', 'evil/docs');
  return clone;
}

int _migrate(Directory root, StringBuffer out, {RunGit? runGit}) => runMigrate(
  MigrateRequest(
    workingDirectory: root,
    homeDirectory: testHome(),
    templates: TemplateResolver(),
    dryRun: false,
    confirmation: OwnerConfirmation.prompt,
    readLine: () => 'y',
    out: out,
    runGit: runGit ?? runRealGit,
  ),
);

Matcher _refusesAsNoWorkTree() => throwsA(
  isA<MigrateFault>()
      .having((f) => f.code, 'code', MigrateFaultCode.gitWorkTreeRequired)
      .having((f) => f.exitStatus, 'exit', 78)
      .having(
        (f) => f.message,
        'message',
        'the project is not in a git work tree with a first commit; put the '
            'project under git, git init and a first commit, then run '
            'specstone migrate again',
      ),
);

void main() {
  late File marker;

  setUp(() async {
    final scratch = await writeTree({'keep.txt': ''});
    marker = File('${scratch.path}/PWNED');
  });

  final configs = {
    'core.fsmonitor': (File marker) => [
      ('core.fsmonitor', 'touch ${marker.path}; false'),
    ],
    'core.hooksPath': (File marker) {
      final hooks = Directory('${marker.parent.path}/hooks')..createSync();
      for (final name in ['pre-commit', 'post-checkout']) {
        File('${hooks.path}/$name')
            .writeAsStringSync('#!/bin/sh\ntouch ${marker.path}\n');
        Process.runSync('chmod', ['+x', '${hooks.path}/$name']);
      }
      return [('core.hooksPath', hooks.path)];
    },
  };

  for (final MapEntry(:key, :value) in configs.entries) {
    test('$_scope E10: migrate refuses a committed git dir reached through a '
        'docs link and runs no command its $key names', () async {
      final clone = await _evilClone(value(marker));

      expect(() => _migrate(clone, StringBuffer()), _refusesAsNoWorkTree());

      expect(marker.existsSync(), isFalse);
    }, skip: _skip);

    test('$_scope E10: the same clone under a git before 2.38 is refused by '
        'the git dir check before any command runs ($key)', () async {
      final clone = await _evilClone(value(marker));

      expect(
        () => _migrate(
          clone,
          StringBuffer(),
          runGit: _olderGit('git version 2.37.0'),
        ),
        _refusesAsNoWorkTree(),
      );

      expect(marker.existsSync(), isFalse);
    }, skip: _skip);
  }

  group('$_scope E10: a repository the project really lives in still runs', () {
    test('a normal work tree passes on a git before 2.38', () async {
      final root = await gitFixture(acmeLegacy);

      expect(
        () => requireGitWorkTree(root, _olderGit('git version 2.37.0')),
        returnsNormally,
      );
      expect(() => requireGitWorkTree(root, runRealGit), returnsNormally);
    }, skip: _skip);

    test('a linked work tree passes on a git before 2.38', () async {
      final root = await gitFixture(acmeLegacy);
      final scratch = Directory.systemTemp.createTempSync('specstone_wt_');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final linked = Directory('${scratch.path}/linked');
      expect(git(root, ['worktree', 'add', '-q', linked.path]).exitCode, 0);

      expect(
        () => requireGitWorkTree(linked, _olderGit('git version 2.37.0')),
        returnsNormally,
      );
      expect(() => requireGitWorkTree(linked, runRealGit), returnsNormally);
    }, skip: _skip);

    test('a project in a subfolder of a work tree passes', () async {
      final root = await gitFixture({
        for (final MapEntry(:key, :value) in acmeLegacy.entries)
          'sub/$key': value,
      });

      expect(
        () => requireGitWorkTree(
          Directory('${root.path}/sub'),
          _olderGit('git version 2.37.0'),
        ),
        returnsNormally,
      );
    }, skip: _skip);
  });
}
