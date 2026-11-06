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

/// Returns the hash on the `plan <hash>` line `migrate --dry-run` prints in
/// [root].
Future<String> _dryRunPlanHash(Directory root) async {
  final (:runner, :out, :err) = writeRunner(root);
  expect(await runner.run(['migrate', '--dry-run']), 0);
  final lines = out.toString().split('\n');
  return lines[lines.length - 3].substring('plan '.length);
}

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

  test('f06/us01/fr04/e16: migrate --dry-run labels a doc changed by a path '
      'mention', () async {
    final root = await writeTree({
      ...acmeLegacy,
      'docs/prds/d04_glossary.md': [
        '# Glossary\n\nSee features/f01_login/us01_email_login/',
        'functional_requirements/fr01_validate_credentials.md:85.\n',
      ].join(),
    });
    final (:runner, :out, :err) = writeRunner(root);

    expect(await runner.run(['migrate', '--dry-run']), 0);

    expect(err.toString(), isEmpty);
    expect(out.toString(), contains('  prds/d04_glossary.md: 1 mention\n'));
  });

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

  test(
    'ms-r11: migrate --yes with --dry-run is a usage error, exit 64',
    () async {
      final root = await writeTree(acmeLegacy);
      final before = _bytesUnder(root);
      final (:runner, :out, :err) = writeRunner(root);

      expect(await runner.run(['migrate', '--yes', '--dry-run']), 64);
      expect(out.toString(), isEmpty);
      expect(err.toString(), startsWith('--yes cannot go with --dry-run.\n'));
      expect(_bytesUnder(root), before);
    },
  );

  test('ms-r11: migrate --dry-run prints plan <hash> above its last '
      'line', () async {
    final root = await writeTree(acmeLegacy);
    final (:runner, :out, :err) = writeRunner(root);

    expect(await runner.run(['migrate', '--dry-run']), 0);
    expect(
      out.toString(),
      matches(RegExp(r'\nplan [0-9a-f]{12}\ndry run: nothing written\n$')),
    );
  });

  for (final (args, message) in [
    (
      ['--yes'],
      '--yes needs --plan <hash>, the plan line specstone migrate '
          '--dry-run prints.',
    ),
    (['--plan', '1a2b3c4d5e6f'], '--plan goes only with --yes.'),
  ]) {
    test(
      'ms-r11: migrate ${args.join(' ')} is a usage error, exit 64',
      () async {
        final root = await writeTree(acmeLegacy);
        final before = _bytesUnder(root);
        final (:runner, :out, :err) = writeRunner(root);

        expect(await runner.run(['migrate', ...args]), 64);
        expect(out.toString(), isEmpty);
        expect(err.toString(), startsWith('$message\n'));
        expect(_bytesUnder(root), before);
      },
    );
  }

  test('ms-r11: migrate --yes --plan with a stale hash prints the plan, '
      'exits 75, and writes nothing', () async {
    final root = await gitFixture(acmeLegacy);
    final head = git(root, ['rev-parse', 'HEAD']).stdout;
    final (:runner, :out, :err) = writeRunner(root);

    expect(
      await runner.run(['migrate', '--yes', '--plan', '000000000000']),
      75,
    );
    expect(out.toString(), startsWith('legacy migration: '));
    expect(
      err.toString(),
      'the plan is not the one the Owner saw in the dry run; run specstone '
      'migrate --dry-run again, show it, and ask for a new ok\n',
    );
    expect(git(root, ['rev-parse', 'HEAD']).stdout, head);
    expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
  }, skip: hasGit ? null : 'git is not available');

  test("ms-r11: migrate --yes --plan with the dry run's hash applies the plan "
      'with no terminal and no prompt', () async {
    final root = await gitFixture(acmeLegacy);
    final hash = await _dryRunPlanHash(root);
    final (:runner, :out, :err) = writeRunner(root);

    expect(await runner.run(['migrate', '--yes', '--plan', hash]), 0);
    expect(err.toString(), isEmpty);
    expect(out.toString(), isNot(contains('apply? [y/N] ')));
    final subjects = (git(root, ['log', '--format=%s']).stdout as String)
        .trim()
        .split('\n');
    expect(subjects.take(2), [
      'rewrite titles, keys, and links; add project configuration',
      'move legacy docs to their new paths',
    ]);
    expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
  }, skip: hasGit ? null : 'git is not available');

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

  test('setup_migration/migrate_legacy_docs/rewrite_titles_keys_and_links E17, '
      'setup_migration/migrate_legacy_docs/write_first_fingerprints: the first '
      'check after a legacy run reports no format_drift and no '
      'confirmed_entry_stale', () async {
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

    final (runner: checkRunner, out: checkOut, err: _) = writeRunner(root);
    await checkRunner.run(['check']);

    expect(checkOut.toString(), isNotEmpty, reason: 'check ran');
    expect(checkOut.toString(), isNot(contains('format_drift')));
    expect(checkOut.toString(), isNot(contains('confirmed_entry_stale')));
    expect(
      File('${root.path}/docs/specs/f01_login/DOMAIN.md').readAsStringSync(),
      contains('| Entity | Kind | Identity |\n'),
    );
  }, skip: hasGit ? null : 'git is not available');

  test(
    'f06/us01/s9, f06/us01/fr07/e09, f06/us01/fr07/e03: a refused commit '
    'exits 75, and '
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
        'migrate at an interactive terminal, or with --yes after the '
        "Owner's ok in the chat, to finish "
        'the run\n',
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

  test("f06/us01/s13, ms-r11: an Agent's shell without --yes gets the plan and "
      'exit 77 naming both ways', () async {
    final root = await gitFixture(acmeLegacy);
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(stdinIsTerminal: false),
    );

    expect(await runner.run(['migrate']), 77);
    expect(out.toString(), startsWith('legacy migration: '));
    expect(
      err.toString(),
      'migrate applies only at an interactive terminal, or with --yes after '
      "the Owner's ok in the chat\n",
    );
    expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
  }, skip: hasGit ? null : 'git is not available');
}
