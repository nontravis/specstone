import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/git_repo.dart';
import '../../../../specstone_core/test/helpers/legacy_fixture.dart';
import '../../../../specstone_core/test/helpers/shipped_pins.dart';
import '../../../../specstone_core/test/helpers/temp_tree.dart';
import '../../helpers/built_cli.dart';
import '../../helpers/write_runner.dart';

Map<String, String> _bytesUnder(Directory root) => {
  for (final entity in root.listSync(recursive: true, followLinks: false))
    if (entity is File &&
        !entity.path.contains(
          '${Platform.pathSeparator}.git${Platform.pathSeparator}',
        ))
      entity.path: entity.readAsStringSync(),
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
    final root = await gitFixture(acmeLegacy);
    final before = _bytesUnder(root);
    final (:runner, :out, :err) = writeRunner(root);

    final status = await runner.run(['migrate', '--dry-run']);

    expect(status, 0);
    expect(err.toString(), isEmpty);
    expect(out.toString(), endsWith('dry run: nothing written\n'));
    expect(out.toString(), startsWith('legacy migration: '));
    expect(_bytesUnder(root), before);
    expect(Directory('${root.path}/.specstone').existsSync(), isFalse);
  }, skip: hasGit ? null : 'git is not available');

  test('a docs-root file named with # is read as a file name, not a URI '
      'fragment', () async {
    final root = await gitFixture({
      ...acmeLegacy,
      'docs/prds/notes#draft.md': '# Notes\n',
    });
    final (:runner, :out, :err) = writeRunner(root);

    expect(
      await runner.run(['migrate', '--dry-run']),
      0,
      reason: err.toString(),
    );
    expect(out.toString(), endsWith('dry run: nothing written\n'));
  }, skip: hasGit ? null : 'git is not available');

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
    final root = await gitFixture({
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
  }, skip: hasGit ? null : 'git is not available');

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
      final root = await gitFixture({
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
    skip: hasGit ? null : 'git is not available',
  );

  group('f06/us01/s15: a legacy collision', () {
    const featureWithSpecs = {
      'docs/prds/d01_context.md': '# D-01 — Context\n',
      'docs/prds/features/f01_login/FEATURE.md': '# F-01 — Login\n',
      'docs/specs/INDEX.md':
          '## Spec map\n\n'
          '| Code path | Spec path | feature_id |\n'
          '|-----------|-----------|------------|\n'
          '| `a/` | `specs/f01_login/` | `f01_login` |\n',
    };

    for (final (:name, :tree) in [
      (
        name: 'a move onto a file that stays',
        tree: {...acmeLegacy, 'docs/prds/FEATURES.md': '# Features\n'},
      ),
      (
        name: 'a move onto ARCHITECTURE.md beside a staying architecture.md',
        tree: {
          ...featureWithSpecs,
          'docs/specs/f01_login/s01_architecture.md': '# New\n',
          'docs/specs/f01_login/architecture.md': '# Mine\n',
        },
      ),
    ]) {
      for (final args in [
        ['migrate', '--dry-run'],
        ['migrate'],
      ]) {
        test(
          '$name refuses ${args.join(' ')}, exit 65, writes nothing',
          () async {
            final root = await gitFixture(tree);
            final before = _bytesUnder(root);
            final (:runner, :out, :err) = writeRunner(root);

            expect(await runner.run(args), 65);

            expect(out.toString(), isEmpty);
            expect(err.toString(), contains('moves to'));
            expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
            expect(_bytesUnder(root), before);
          },
          skip: hasGit ? null : 'git is not available',
        );
      }
    }
  });

  test('f06/us01/fr03/e12: Spec map rows outside specs/ sharing a last '
      'segment plan, exit 0', () async {
    final root = await gitFixture({
      'docs/prds/d01_context.md': '# D-01 — Context\n',
      'docs/specs/INDEX.md':
          '## Spec map\n\n'
          '| Code path | Spec path | feature_id |\n'
          '|-----------|-----------|------------|\n'
          '| `a/` | `auth/` | — |\n'
          '| `b/` | `lib/auth/` | — |\n',
    });
    final (:runner, :out, :err) = writeRunner(root);

    expect(
      await runner.run(['migrate', '--dry-run']),
      0,
      reason: err.toString(),
    );
    expect(out.toString(), endsWith('dry run: nothing written\n'));
  }, skip: hasGit ? null : 'git is not available');

  test('f06/us01/fr02/e04: migrate --dry-run over a dirty tree is '
      'working_tree_dirty, exit 75, with no plan', () async {
    final root = await gitFixture(acmeLegacy);
    File('${root.path}/notes.txt').writeAsStringSync('x\n');
    final (:runner, :out, :err) = writeRunner(root);

    expect(await runner.run(['migrate', '--dry-run']), 75);
    expect(out.toString(), isEmpty);
    expect(err.toString(), isNotEmpty);
  }, skip: hasGit ? null : 'git is not available');

  test('f06/us01/fr02/e03: migrate --dry-run outside a git work tree is '
      'git_work_tree_required, exit 78, with no plan', () async {
    final root = await writeTree(acmeLegacy);
    final (:runner, :out, :err) = writeRunner(root);

    expect(await runner.run(['migrate', '--dry-run']), 78);
    expect(out.toString(), isEmpty);
    expect(err.toString(), contains('not in a git work tree'));
  }, skip: hasGit ? null : 'git is not available');

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
    final root = await gitFixture(acmeLegacy);
    final (:runner, :out, :err) = writeRunner(root);

    expect(await runner.run(['migrate', '--dry-run']), 0);
    expect(
      out.toString(),
      matches(RegExp(r'\nplan [0-9a-f]{12}\ndry run: nothing written\n$')),
    );
  }, skip: hasGit ? null : 'git is not available');

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

  test('migrate --dry-run --json prints the plan as one object holding its '
      'hash and every path list, and nothing else', () async {
    final root = await gitFixture(acmeLegacy);
    final hash = await _dryRunPlanHash(root);
    final before = _bytesUnder(root);
    final (:runner, :out, :err) = writeRunner(root);

    expect(await runner.run(['migrate', '--dry-run', '--json']), 0);

    final object = jsonDecode(out.toString()) as Map<String, Object?>;
    expect(object['planHash'], hash);
    expect(object['plan'], startsWith('legacy migration: '));
    expect(object['plan'], contains('  format layout: 1 docs\n'));
    expect(object['formatLayout'], ['specs/f01_login/DOMAIN.md']);
    expect(object.keys, containsAll(['agentFiles', 'numberLabels', 'steps']));
    expect(err.toString(), isEmpty);
    expect(_bytesUnder(root), before);
  }, skip: hasGit ? null : 'git is not available');

  test('migrate --yes --plan --json applies the run, prints one object, and '
      'ends its notes with the closing count', () async {
    final root = await gitFixture(acmeLegacy);
    final hash = await _dryRunPlanHash(root);
    final (:runner, :out, :err) = writeRunner(root);

    expect(await runner.run(['migrate', '--yes', '--plan', hash, '--json']), 0);

    expect(
      (jsonDecode(out.toString()) as Map<String, Object?>)['planHash'],
      hash,
    );
    expect(
      err.toString().trim().split('\n').last,
      matches(r'^check: \d+ findings left; run specstone check to see them$'),
    );
    expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
  }, skip: hasGit ? null : 'git is not available');

  test('migrate --yes --plan ends with the count a check reports', () async {
    final root = await gitFixture(acmeLegacy);
    final hash = await _dryRunPlanHash(root);
    final (:runner, :out, :err) = writeRunner(root);

    expect(await runner.run(['migrate', '--yes', '--plan', hash]), 0);

    expect(
      out.toString().trim().split('\n').last,
      matches(r'^check: \d+ findings left; run specstone check to see them$'),
    );
  }, skip: hasGit ? null : 'git is not available');

  group('f06/us01/fr05/e14: the legacy run writes records', () {
    const storyFile =
        'docs/prds/features/f01_login/us01_email_login/USER_STORY.md';
    String story(String status) =>
        '---\nname: Email login\nstatus: $status\nimplements:\n'
        '  - lib/a.dart:A\n---\n\n# US-01 — Email login\n';

    test('the dry run lists the record, and the apply writes it in commit 2 '
        'with no status or implements left on the story', () async {
      final root = await gitFixture({
        ...acmeLegacy,
        storyFile: story('implemented'),
      });
      final (runner: dry, out: dryOut, err: _) = writeRunner(root);
      expect(await dry.run(['migrate', '--dry-run']), 0);
      expect(
        dryOut.toString(),
        contains('  specs/f01_login/IMPLEMENTATION.md (draft)\n'),
      );
      final hash = await _dryRunPlanHash(root);
      final (:runner, :out, :err) = writeRunner(root);

      expect(await runner.run(['migrate', '--yes', '--plan', hash]), 0);

      expect(err.toString(), isEmpty);
      final record = File('${root.path}/docs/specs/f01_login/IMPLEMENTATION.md')
          .readAsStringSync();
      expect(record, contains('draft: true\n'));
      expect(record, contains("  - 'email_login:implemented'\n"));
      expect(record, contains("  - 'email_login:lib/a.dart:A'\n"));
      final moved = File(
        '${root.path}/docs/prds/features/f01_login/us01_email_login/'
        'USER_STORY.md',
      ).readAsStringSync();
      expect(moved, isNot(contains('status:')));
      expect(moved, isNot(contains('implements:')));
      final committed = git(root, [
        'show',
        '--name-only',
        '--format=',
        'HEAD',
      ]).stdout;
      expect(committed, contains('docs/specs/f01_login/IMPLEMENTATION.md'));
      expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
    });

    test('a status no record entry takes refuses with value_unplaced, exit '
        '65, and writes nothing', () async {
      final root = await gitFixture({...acmeLegacy, storyFile: story('wip')});
      final before = _bytesUnder(root);
      final (:runner, :out, :err) = writeRunner(root);

      expect(await runner.run(['migrate', '--dry-run']), 65);

      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        startsWith('prds/features/f01_login/us01_email_login/USER_STORY.md: '),
      );
      expect(err.toString(), contains('status wip is no status'));
      expect(_bytesUnder(root), before);
    });
  }, skip: hasGit ? null : 'git is not available');

  test('f06/us01/s17: a commit that touches no input between the dry run and '
      'migrate --yes --plan leaves the hash, and the plan applies', () async {
    final root = await gitFixture(acmeLegacy);
    final hash = await _dryRunPlanHash(root);
    File('${root.path}/notes.txt').writeAsStringSync('later\n');
    commitAll(root, 'unrelated');
    final (:runner, :out, :err) = writeRunner(root);

    expect(await runner.run(['migrate', '--yes', '--plan', hash]), 0);

    expect(err.toString(), isEmpty);
    final subjects = (git(root, ['log', '--format=%s']).stdout as String)
        .trim()
        .split('\n');
    expect(subjects.take(3), [
      'rewrite titles, keys, and links; add project configuration',
      'move legacy docs to their new paths',
      'unrelated',
    ]);
  }, skip: hasGit ? null : 'git is not available');

  test('f06/us02/s17: a tracked file added between the dry run and migrate '
      '--yes --plan leaves the hash of an upgrade with a labelled code file, '
      'and the plan applies without reading it', () async {
    final root = await gitFixture({
      '.specstone/config.yaml':
          'packs:\n  prd-core: 1.0.0\n'
          '  software-tech: 1.0.0\n',
      'docs/prds/features/f01_a/FEATURE.md': '# A\n',
      'docs/prds/features/f01_a/us01_b/USER_STORY.md': '# B\n',
      'docs/prds/features/f01_a/us01_b/fr01_c.md': '# C\n',
      'docs/specs/TECH_STACK.md': '---\ncode:\n  - lib/\n---\n# Tech stack\n',
      'lib/a.dart': '// See F-01 US-01\n',
    });
    final hash = await _dryRunPlanHash(root);
    File('${root.path}/notes.txt').writeAsStringSync('later\n');
    commitAll(root, 'unrelated');
    final (:runner, :out, :err) = writeRunner(root);

    expect(
      await runner.run(['migrate', '--yes', '--plan', hash]),
      0,
      reason: err.toString(),
    );

    expect(
      File('${root.path}/lib/a.dart').readAsStringSync(),
      '// See F-01 US-01\n',
    );
    expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
  }, skip: hasGit ? null : 'git is not available');

  test(
    'f06/us01/s18: a committed edit to a doc between the dry run and '
    'migrate --yes --plan exits 75, plan_mismatch, and writes nothing',
    () async {
      final root = await gitFixture(acmeLegacy);
      final hash = await _dryRunPlanHash(root);
      File('${root.path}/docs/prds/d01_context.md')
          .writeAsStringSync('later\n');
      commitAll(root, 'edit a doc');
      final head = git(root, ['rev-parse', 'HEAD']).stdout;
      final (:runner, :out, :err) = writeRunner(root);

      expect(await runner.run(['migrate', '--yes', '--plan', hash]), 75);

      expect(
        err.toString(),
        startsWith('the plan is not the one the Owner saw'),
      );
      expect(git(root, ['rev-parse', 'HEAD']).stdout, head);
      expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
    },
    skip: hasGit ? null : 'git is not available',
  );

  test('setup_migration/migrate_legacy_docs/show_plan_and_apply_on_yes E07: '
      'migrate --yes --plan leaves the typed docs stamped and no stale '
      'approval for check', () async {
    final root = await gitFixture(acmeLegacy);
    final hash = await _dryRunPlanHash(root);
    final (:runner, :out, :err) = writeRunner(root);
    expect(await runner.run(['migrate', '--yes', '--plan', hash]), 0);

    final feature = File('${root.path}/docs/prds/features/f01_login/FEATURE.md')
        .readAsStringSync();
    final (runner: checker, out: checkOut, err: _) = writeRunner(root);
    await checker.run(['check']);

    expect(feature, startsWith('---\napproved: "'));
    expect(feature, isNot(contains('draft:')));
    expect(checkOut.toString(), isNot(contains('approval_stale')));
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

  group('f06/us01/fr02/e15: under an exported git repository variable', () {
    late String binary;
    setUpAll(() async {
      binary = await buildSpecstone();
    });

    Future<Directory> otherRepoWithUntrackedFile() async {
      final other = await writeTree({'untracked.txt': 'not committed\n'});
      expect(git(other, ['init', '-q']).exitCode, 0);
      return other;
    }

    test('migrate --dry-run plans the repository of its own folder and leaves '
        'the other one alone', () async {
      final root = await gitFixture(acmeLegacy);
      final other = await otherRepoWithUntrackedFile();
      final before = _bytesUnder(other);

      final shown = await Process.run(
        binary,
        ['migrate', '--dry-run'],
        workingDirectory: root.path,
        environment: {
          'GIT_DIR': '${other.path}/.git',
          'GIT_WORK_TREE': other.path,
        },
      );

      expect(shown.exitCode, 0, reason: '${shown.stderr}');
      expect(shown.stdout, startsWith('legacy migration: '));
      expect(shown.stdout, matches(RegExp(r'\nplan [0-9a-f]{12}\n')));
      expect(_bytesUnder(other), before);
      expect(
        git(other, ['status', '--porcelain']).stdout,
        '?? untracked.txt\n',
      );
    });

    test('a bare migrate without a terminal passes the git checks of its own '
        'folder and exits 77', () async {
      final root = await gitFixture(acmeLegacy);
      final other = await otherRepoWithUntrackedFile();

      final shown = await Process.run(
        binary,
        ['migrate'],
        workingDirectory: root.path,
        environment: {
          'GIT_DIR': '${other.path}/.git',
          'GIT_WORK_TREE': other.path,
        },
      );

      expect(shown.exitCode, 77, reason: '${shown.stderr}');
      expect(shown.stdout, startsWith('legacy migration: '));
    });

    test(
      'migrate --dry-run works under a GIT_DIR that names no folder',
      () async {
        final root = await gitFixture(acmeLegacy);

        final shown = await Process.run(
          binary,
          ['migrate', '--dry-run'],
          workingDirectory: root.path,
          environment: {'GIT_DIR': '/nonexistent'},
        );

        expect(shown.exitCode, 0, reason: '${shown.stderr}');
        expect(shown.stdout, startsWith('legacy migration: '));
      },
    );

    test(
      'f06/us01/fr02/g8-r8: migrate --dry-run never starts a git found in its '
      'own folder through a "." PATH entry',
      () async {
        final root = await gitFixture(acmeLegacy);
        final marker = '${(await writeTree({})).path}/ran';
        final planted = File('${root.path}/git')
          ..writeAsStringSync('#!/bin/sh\n: > "$marker"\nexit 1\n');
        expect(Process.runSync('chmod', ['755', planted.path]).exitCode, 0);
        File('${root.path}/.git/info/exclude')
            .writeAsStringSync('/git\n', mode: FileMode.append);

        final shown = await Process.run(
          binary,
          ['migrate', '--dry-run'],
          workingDirectory: root.path,
          environment: {'PATH': '.:${Platform.environment['PATH']}'},
        );

        expect(shown.exitCode, 0, reason: '${shown.stderr}');
        expect(shown.stdout, startsWith('legacy migration: '));
        expect(File(marker).existsSync(), isFalse);
      },
      skip: Platform.isWindows
          ? 'the planted git is a POSIX shell script'
          : null,
    );

    // CreateProcessW looks in the current folder before any PATH entry, so a
    // start of the bare name `git` would run this copy of the Specstone binary.
    test(
      'f06/us01/fr02/g8-r8: migrate --dry-run never starts a git.exe found in '
      'its own folder',
      () async {
        final root = await gitFixture(acmeLegacy);
        File(binary).copySync('${root.path}/git.exe');
        File('${root.path}/.git/info/exclude')
            .writeAsStringSync('/git.exe\n', mode: FileMode.append);

        final shown = await Process.run(binary, [
          'migrate',
          '--dry-run',
        ], workingDirectory: root.path);

        expect(shown.exitCode, 0, reason: '${shown.stderr}');
        expect(shown.stdout, startsWith('legacy migration: '));
      },
      skip: Platform.isWindows ? null : 'CreateProcessW searches the folder',
    );

    test(
      'migrate --dry-run refuses git_work_tree_required, exit 78, when git '
      'cannot list its repository variables',
      () async {
        final root = await gitFixture(acmeLegacy);
        final realGit = (Process.runSync('which', ['git']).stdout as String)
            .trim();
        final stub = await writeTree({
          'git': [
            '#!/bin/sh',
            r'case "$*" in',
            "  *--local-env-vars*) echo 'fatal: boom' >&2; exit 128 ;;",
            'esac',
            'exec "$realGit" "\$@"',
            '',
          ].join('\n'),
        });
        expect(
          Process.runSync('chmod', ['755', '${stub.path}/git']).exitCode,
          0,
        );

        final shown = await Process.run(
          binary,
          ['migrate', '--dry-run'],
          workingDirectory: root.path,
          environment: {'PATH': '${stub.path}:${Platform.environment['PATH']}'},
        );

        expect(shown.exitCode, 78, reason: '${shown.stderr}');
        expect(shown.stdout, isEmpty);
        expect(shown.stderr, contains('not in a git work tree'));
      },
      skip: Platform.isWindows ? 'the stub git is a POSIX shell script' : null,
    );
  }, skip: hasGit ? null : 'git is not available');
}
