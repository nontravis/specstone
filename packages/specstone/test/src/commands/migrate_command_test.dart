import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/git_repo.dart';
import '../../../../specstone_core/test/helpers/legacy_fixture.dart';
import '../../../../specstone_core/test/helpers/shipped_pins.dart';
import '../../../../specstone_core/test/helpers/temp_tree.dart';
import '../../helpers/write_runner.dart';

Map<String, String> _bytesUnder(Directory root) => {
  for (final entity in root.listSync(recursive: true, followLinks: false))
    if (entity is File) entity.path: entity.readAsStringSync(),
};

void main() {
  test('f06/us01/s2: migrate --dry-run prints the plan, writes nothing, and '
      'exits 0', () async {
    final root = await writeTree(acmeLegacy);
    final before = _bytesUnder(root);
    final (:runner, :out, :err) = writeRunner(root);

    final status = await runner.run(['migrate', '--dry-run']);

    expect(status, 0);
    expect(err.toString(), isEmpty);
    expect(out.toString(), endsWith('dry run: nothing written\n'));
    expect(out.toString(), startsWith('legacy migration: '));
    expect(_bytesUnder(root), before);
    expect(Directory('${root.path}/.specstone').existsSync(), isFalse);
  });

  test(
    'f06/us01/fr01/e04: nothing to migrate, with and without --dry-run',
    () async {
      final root = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
      });

      for (final args in [
        ['migrate'],
        ['migrate', '--dry-run'],
      ]) {
        final (:runner, :out, :err) = writeRunner(root);

        expect(await runner.run(args), 0);
        expect(out.toString(), 'nothing to migrate\n');
        expect(err.toString(), isEmpty);
      }
    },
  );

  test('f06/us01/fr01/e01: no project is project_not_found, exit 78', () async {
    final root = await writeTree({'notes.txt': 'x\n'});
    final (:runner, :out, :err) = writeRunner(root);

    expect(await runner.run(['migrate']), 78);
    expect(out.toString(), isEmpty);
    expect(err.toString(), startsWith('no Specstone project'));
  });

  test('f06/us01/fr01/e06: a newer pin refuses before the run, exit 78, in '
      '--dry-run', () async {
    final root = await writeTree({
      '.specstone/config.yaml': 'packs:\n  prd-core: 99.0.0\n',
    });
    final (:runner, :out, :err) = writeRunner(root);

    expect(await runner.run(['migrate', '--dry-run']), 78);
    expect(out.toString(), isEmpty);
    expect(err.toString(), contains('prd-core'));
  });

  test(
    'f06/us01/s14: two groups with one name refuse in the dry run',
    () async {
      final root = await writeTree({
        ...duplicateGroupLegacy,
        'docs/prds/d01_context.md': '# D-01 — Context\n',
      });
      final (:runner, :out, :err) = writeRunner(root);

      expect(await runner.run(['migrate', '--dry-run']), 65);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        'prds/features/components/co01_utilities: two group folders give the '
        'group utilities; rename one, then run specstone migrate again; also '
        'prds/features/core/cr02_utilities\n',
      );
    },
  );

  test('f06/us01/fr02: migrate takes no argument', () async {
    final root = await writeTree(acmeLegacy);
    final (:runner, :out, :err) = writeRunner(root);

    expect(await runner.run(['migrate', 'docs']), 64);
    expect(out.toString(), isEmpty);
  });

  test("f06/us01/s1: the Owner's y at a terminal makes two commits", () async {
    final root = await gitFixture(acmeLegacy);
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(
        stdinIsTerminal: true,
        stdoutIsTerminal: true,
        answers: ['y'],
      ),
    );

    expect(await runner.run(['migrate']), 0);
    expect(err.toString(), isEmpty);
    final subjects = (git(root, ['log', '--format=%s']).stdout as String)
        .trim()
        .split('\n');
    expect(subjects.take(2), [
      'rewrite titles, keys, and links; add project configuration',
      'move legacy docs to their new paths',
    ]);
    expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
  }, skip: hasGit ? null : 'git is not available');

  test(
    'f06/us01/fr07/e09, f06/us01/fr07/e03: a refused commit exits 75, and '
    'the next migrate at a terminal resumes with no answer',
    () async {
      final root = await gitFixture(acmeLegacy);
      final hook = File('${root.path}/.git/hooks/pre-commit')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\necho "lint failed" >&2\nexit 1\n');
      expect(Process.runSync('chmod', ['755', hook.path]).exitCode, 0);
      final first = writeRunner(
        root,
        console: FakeConsole(
          stdinIsTerminal: true,
          stdoutIsTerminal: true,
          answers: ['y'],
        ),
      );

      expect(await first.runner.run(['migrate']), 75);
      expect(
        first.err.toString(),
        'git commit failed: lint failed; fix the cause, then run specstone '
        'migrate at an interactive terminal to finish the run\n',
      );

      hook.deleteSync();
      final second = writeRunner(
        root,
        console: FakeConsole(stdinIsTerminal: true, stdoutIsTerminal: true),
      );

      expect(await second.runner.run(['migrate']), 0);
      expect(second.err.toString(), isEmpty);
      expect(second.out.toString(), startsWith('pending migration: '));
      final subjects = (git(root, ['log', '--format=%s']).stdout as String)
          .trim()
          .split('\n');
      expect(subjects.take(2), [
        'rewrite titles, keys, and links; add project configuration',
        'move legacy docs to their new paths',
      ]);
      expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
    },
    skip: Platform.isWindows
        ? 'the hook is a sh script'
        : (hasGit ? null : 'git is not available'),
  );

  test("f06/us01/s13: an Agent's shell gets the plan and exit 77", () async {
    final root = await gitFixture(acmeLegacy);
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(stdinIsTerminal: false),
    );

    expect(await runner.run(['migrate']), 77);
    expect(out.toString(), startsWith('legacy migration: '));
    expect(
      err.toString(),
      'migrate applies only at an interactive terminal; ask the Owner to '
      'run specstone migrate\n',
    );
    expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
  }, skip: hasGit ? null : 'git is not available');
}
