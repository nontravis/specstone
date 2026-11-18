import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/nested_fixture.dart';
import '../../../../specstone_core/test/helpers/record_fixture.dart';
import '../../../../specstone_core/test/helpers/target_fixture.dart';
import '../../../../specstone_core/test/helpers/write_fixture.dart';
import '../../helpers/built_cli.dart';
import '../../helpers/write_runner.dart';

/// Returns the hash on the `plan <hash>` line `delete --dry-run` prints for
/// [target] in [root].
Future<String> _dryRunPlanHash(Directory root, String target) async {
  final (:runner, :out, :err) = writeRunner(root);
  expect(await runner.run(['delete', target, '--dry-run', '--json']), 0);
  return (jsonDecode(out.toString()) as Map)['plan']! as String;
}

void main() {
  test('delete prints one removed path per line', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run(['delete', 'fr:login/reset_password/expire_reset_link']),
      0,
    );
    expect(err.toString(), isEmpty);
    expect(out.toString(), '$fr32\n');
    expect(File('${root.path}/docs/$fr32').existsSync(), isFalse);
  });
  test(
    'an approved unit without a terminal exits 77 with the sidecar message',
    () async {
      final root = await writeWriteProject();
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run([
          'delete',
          'fr:login/email_login/validate_credentials',
          '--json',
        ]),
        77,
      );
      expect(out.toString(), isEmpty);
      final error = (jsonDecode(err.toString()) as Map)['error'] as Map;
      expect(error['code'], 'owner_terminal_required');
      expect(
        error['message'],
        'fr:login/email_login/validate_credentials holds guarded docs; '
        'only the Owner deletes them, at an interactive terminal, or with '
        "--yes after the Owner's ok in the chat",
      );
      expect(File('${root.path}/docs/$fr11').existsSync(), isTrue);
    },
  );
  const fr11Target = 'fr:login/email_login/validate_credentials';

  test('--dry-run lists the files and the plan line, removes '
      'nothing, and needs no terminal', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(root);
    expect(await runner.run(['delete', fr11Target, '--dry-run']), 0);
    expect(err.toString(), isEmpty);
    expect(
      out.toString(),
      matches(
        RegExp(
          '^${RegExp.escape(fr11)} \\(guarded\\)'
          r'\n'
          "guarded: 1 docs; the delete needs the Owner's ok"
          r'\nplan [0-9a-f]{12}\ndry run: nothing removed\n$',
        ),
      ),
    );
    expect(File('${root.path}/docs/$fr11').existsSync(), isTrue);
  });
  test(
    '--dry-run --json prints the files and the plan as one JSON object',
    () async {
      final root = await writeWriteProject();
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run(['delete', fr11Target, '--dry-run', '--json']),
        0,
      );
      final answer = jsonDecode(out.toString()) as Map;
      expect(answer['files'], [fr11]);
      expect(answer['plan'], matches(RegExp(r'^[0-9a-f]{12}$')));
    },
  );
  for (final (args, message) in [
    (
      ['--yes'],
      '--yes needs --plan <hash>, the plan line specstone delete --dry-run '
          'prints.',
    ),
    (['--plan', '1a2b3c4d5e6f'], '--plan goes only with --yes.'),
    (
      ['--yes', '--plan', '1a2b3c4d5e6f', '--dry-run'],
      '--yes cannot go with --dry-run.',
    ),
  ]) {
    test('delete ${args.join(' ')} is a usage error, exit 64, and '
        'removes nothing', () async {
      final root = await writeWriteProject();
      final (:runner, :out, :err) = writeRunner(root);
      expect(await runner.run(['delete', fr11Target, ...args]), 64);
      expect(out.toString(), isEmpty);
      expect(err.toString(), startsWith('$message\n'));
      expect(File('${root.path}/docs/$fr11').existsSync(), isTrue);
    });
  }
  test("--yes --plan with the dry run's hash deletes an approved "
      'unit with no terminal and no prompt', () async {
    final root = await writeWriteProject();
    final hash = await _dryRunPlanHash(root, fr11Target);
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run(['delete', fr11Target, '--yes', '--plan', hash]),
      0,
    );
    expect(err.toString(), isEmpty);
    expect(out.toString(), '$fr11\n');
    expect(File('${root.path}/docs/$fr11').existsSync(), isFalse);
  });
  test(
    '--yes --plan --json prints the removed paths as one JSON object',
    () async {
      final root = await writeWriteProject();
      final hash = await _dryRunPlanHash(root, fr11Target);
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run([
          'delete',
          fr11Target,
          '--yes',
          '--plan',
          hash,
          '--json',
        ]),
        0,
      );
      expect(err.toString(), isEmpty);
      expect((jsonDecode(out.toString()) as Map)['removed'], [fr11]);
    },
  );
  test('--yes --plan with a stale hash exits 75 and removes nothing', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run([
        'delete',
        fr11Target,
        '--yes',
        '--plan',
        '000000000000',
      ]),
      75,
    );
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      'the delete list is not the one the Owner saw in the dry run; run '
      'specstone delete --dry-run again, show it, and ask for a new ok\n',
    );
    expect(File('${root.path}/docs/$fr11').existsSync(), isTrue);
  });
  test('the Owner prompt goes to stdout, the removed paths after it', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(
        stdinIsTerminal: true,
        stdoutIsTerminal: true,
        answers: ['y'],
      ),
    );
    expect(
      await runner.run(['delete', 'fr:login/email_login/validate_credentials']),
      0,
    );
    expect(out.toString(), '$fr11\ndelete 1 files? [y/N] $fr11\n');
    expect(err.toString(), isEmpty);
  });
  test('under --json the Owner prompt goes to stderr and stdout holds one JSON '
      'object', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(
        stdinIsTerminal: true,
        stdoutIsTerminal: true,
        answers: ['y'],
      ),
    );
    expect(
      await runner.run([
        'delete',
        'fr:login/email_login/validate_credentials',
        '--json',
      ]),
      0,
    );
    expect(err.toString(), '$fr11\ndelete 1 files? [y/N] ');
    expect(jsonDecode(out.toString()), {
      'removed': [fr11],
      'mentions': <Object>[],
      'warnings': <String>[],
    });
  });
  test('delete takes no --base', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(
      await runner.run([
        'delete',
        'fr:login/reset_password/expire_reset_link',
        '--base',
        'x',
      ]),
      64,
    );
  });
  test('no target is argument_missing', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['delete']), 64);
    expect(err.toString(), startsWith('delete needs a target'));
  });
  const notes = 'specs/f01_login/api_notes.md';
  const errors = 'specs/f01_login/api_errors.md';
  const index = 'specs/INDEX.md';
  final untyped = <String, String>{
    'docs/$notes': '# Notes\n\nSee [errors](api_errors.md).\n',
    'docs/$errors': '# Errors\n\nSee [index](../INDEX.md).\n',
    'docs/$index': '# Index\n\nNothing links here but api_errors.md.\n',
  };
  test('two targets delete both, one removed path per line', () async {
    const one = 'specs/f01_login/one.md';
    const two = 'specs/f01_login/two.md';
    final root = await writeWriteProject(
      extra: {
        'docs/$one': '---\ndraft: true\n---\n\n# One\n',
        'docs/$two': '---\ndraft: true\n---\n\n# Two\n',
      },
    );
    final (:runner, :out, :err) = writeRunner(root);
    expect(await runner.run(['delete', one, two]), 0);
    expect(err.toString(), isEmpty);
    expect(out.toString(), '$one\n$two\n');
    expect(File('${root.path}/docs/$one').existsSync(), isFalse);
    expect(File('${root.path}/docs/$two').existsSync(), isFalse);
  });
  test(
    'a referrer outside the set exits 64 and is named after ; also',
    () async {
      final root = await writeWriteProject(
        extra: {
          ...untyped,
          'docs/$story1':
              '${writeProject['docs/$story1']}\n'
              'See [errors](../../../../specs/f01_login/api_errors.md).\n',
        },
      );
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(
          stdinIsTerminal: true,
          stdoutIsTerminal: true,
          answers: ['y'],
        ),
      );
      expect(await runner.run(['delete', notes, errors]), 64);
      expect(
        err.toString(),
        '$errors: docs outside the delete set link into it; also $story1\n',
      );
      expect(File('${root.path}/docs/$notes').existsSync(), isTrue);
      expect(File('${root.path}/docs/$errors').existsSync(), isTrue);
    },
  );
  const plan = 'superpowers/plans/plan.md';
  final withPlan = {
    ...untyped,
    'docs/$plan':
        '# Plan\n\nSee [the notes](../../specs/f01_login/api_notes.md).\n',
  };
  const dangles = '$plan links into $notes; the link will dangle';
  test('--dry-run on a doc a plan links into exits 0 and warns on stderr that '
      'the link will dangle', () async {
    final root = await writeWriteProject(extra: withPlan);
    final (:runner, :out, :err) = writeRunner(root);

    final status = await runner.run(['delete', notes, '--dry-run']);

    expect(status, 0);
    expect(err.toString(), '⚠️ WARNING: $dangles\n');
    expect(
      out.toString(),
      startsWith(
        '$notes (guarded)\n'
        "guarded: 1 docs; the delete needs the Owner's ok\nplan ",
      ),
    );
    expect(File('${root.path}/docs/$notes').existsSync(), isTrue);
  });
  test('delete --help shows several targets', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['delete', '--help']), 0);
    expect(
      out.toString(),
      contains(
        'Usage: specstone delete <target> … [--target <name>] '
        '[--dry-run | --yes --plan <hash>] [--json]',
      ),
    );
  });
  test('an untyped DocPath that holds a space deletes that file', () async {
    const spaced = 'specs/f01_login/api notes.md';
    final root = await writeWriteProject(
      extra: {'docs/$spaced': '---\ndraft: true\n---\n\n# Notes\n'},
    );
    final (:runner, :out, :err) = writeRunner(root);
    expect(await runner.run(['delete', spaced]), 0);
    expect(out.toString(), '$spaced\n');
    expect(File('${root.path}/docs/$spaced').existsSync(), isFalse);
  });

  group('matrix rows of a deleted item', () {
    const record = '.specstone/records/f01_login/IMPLEMENTATION.md';
    const item = 'reset_password/expire_reset_link';
    const target = 'fr:login/$item';

    Future<Directory> projectWithRows() => writeWriteProject(
      extra: {
        '.specstone/config.yaml': oneTargetConfig(),
        '.specstone/templates/implementation.yaml': recordLayerAtRoot,
        record:
            '${recordText()}\n## Verification matrix\n\n'
            '- $item E01: `expires a link` 5d1e0c4b7a92\n'
            '- $item E02 skipped: needs a clock  9a1c03be55d2\n',
      },
    );

    Future<List<String>> matrixKindsOn(Directory root) async {
      final (:runner, :out, :err) = writeRunner(root);
      await runner.run(['check', '--json']);
      final findings = (jsonDecode(out.toString()) as Map)['findings']! as List;
      return [
        for (final f in findings.cast<Map<String, Object?>>())
          if (f['docPath'] == record &&
              (f['kind']! as String).startsWith('matrix_'))
            f['kind']! as String,
      ];
    }

    test('delete --dry-run --json lists an item whose rows leave', () async {
      final root = await projectWithRows();
      final (:runner, :out, :err) = writeRunner(root);

      expect(await runner.run(['delete', target, '--dry-run', '--json']), 0);

      expect((jsonDecode(out.toString()) as Map)['records'], [
        {
          'path': record,
          'entries': [item],
        },
      ]);
    });

    test('check after the delete gives no matrix finding', () async {
      final root = await projectWithRows();
      expect(await matrixKindsOn(root), isNotEmpty);

      final (:runner, :out, :err) = writeRunner(root);
      expect(await runner.run(['delete', target]), 0, reason: err.toString());

      expect(await matrixKindsOn(root), isEmpty);
    });
  });

  group('with two code targets', () {
    test('--target keeps the names to one target; a target the project lacks '
        'exits 64', () async {
      final root = await writeTwinProject();
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run([
          'delete',
          'user_story:login/email_login',
          '--target',
          'flutter',
          '--dry-run',
          '--json',
        ]),
        0,
        reason: err.toString(),
      );
      expect((jsonDecode(out.toString()) as Map)['files'], hasLength(3));

      final (runner: second, out: _, err: secondErr) = writeRunner(root);
      expect(
        await second.run([
          'delete',
          'user_story:login/email_login',
          '--target',
          'dart',
        ]),
        64,
      );
      expect(
        secondErr.toString(),
        '--target dart: the code targets are flutter, jaspr\n',
      );
    });
  });

  group('through the built CLI', () {
    late String binary;
    setUpAll(() async {
      binary = await buildSpecstone();
    });

    test('delete --dry-run and then delete --yes --plan do not refuse '
        'when git is missing or fails', () async {
      final root = await writeWriteProject();
      final emptyPath = Directory.systemTemp.createTempSync('specstone_path_');
      addTearDown(() => emptyPath.deleteSync(recursive: true));
      final home = testHome().path;
      final environment = {
        'PATH': emptyPath.path,
        'HOME': home,
        'USERPROFILE': home,
      };
      Future<ProcessResult> run(List<String> args) => Process.run(
        binary,
        ['delete', fr11Target, ...args],
        workingDirectory: root.path,
        environment: environment,
      );

      final dry = await run(['--dry-run', '--json']);
      expect(dry.exitCode, 0, reason: '${dry.stderr}');
      final hash = (jsonDecode('${dry.stdout}') as Map)['plan']! as String;

      final yes = await run(['--yes', '--plan', hash]);
      expect(yes.exitCode, 0, reason: '${yes.stderr}');
      expect(File('${root.path}/docs/$fr11').existsSync(), isFalse);
    });
  });

  group('an untyped file under measurements/', () {
    const scratch = 'measurements/scratch.md';
    const referrer = 'measurements/referrer.md';
    final inside = <String, String>{
      'docs/$scratch': '---\ndraft: true\n---\n\n# Scratch\n',
      'docs/$referrer': '# Referrer\n\nSee [scratch](scratch.md).\n',
    };

    test(
      'is no history file: a link into the delete set refuses doc_referenced',
      () async {
        final root = await writeWriteProject(extra: inside);
        final (:runner, :out, :err) = writeRunner(root);
        expect(await runner.run(['delete', scratch, '--dry-run']), 64);
        expect(
          err.toString(),
          '$scratch: docs outside $scratch link into it; also $referrer\n',
        );
        expect(File('${root.path}/docs/$scratch').existsSync(), isTrue);
      },
    );
  });
  group('a delete target named by the end of its name', () {
    test(
      'delete --dry-run refuses a suffix of no identity, naming it',
      () async {
        final (:runner, :out, :err) = writeRunner(await writeNestedProject());
        expect(await runner.run(['delete', 'feature:ay', '--dry-run']), 64);
        expect(out.toString(), isEmpty);
        expect(err.toString(), 'no feature doc carries the name ay\n');
      },
    );
  });
}
