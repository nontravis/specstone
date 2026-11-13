import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/shipped_pins.dart';
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
  test('f02/us04/s1: delete prints one removed path per line', () async {
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
  test('f02/us04/s6: an approved unit without a terminal exits 77 with the sidecar message', () async {
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
  });
  const fr11Target = 'fr:login/email_login/validate_credentials';
  test('--dry-run prints a mention of a removed doc in an agent file '
      'before the plan line', () async {
    final root = await writeWriteProject(
      extra: {
        'CLAUDE.md': 'Read `fr:login/email_login/validate_credentials`.\n',
      },
    );
    final (:runner, :out, :err) = writeRunner(root);
    expect(await runner.run(['delete', fr11Target, '--dry-run']), 0);
    expect(
      out.toString(),
      contains(
        'mentions CLAUDE.md:1 fr:login/email_login/validate_credentials\nplan ',
      ),
    );
    expect(
      File('${root.path}/CLAUDE.md').readAsStringSync(),
      'Read `fr:login/email_login/validate_credentials`.\n',
    );
  });

  test('ms-r11: --dry-run lists the files and the plan line, removes '
      'nothing, and needs no terminal', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(root);
    expect(await runner.run(['delete', fr11Target, '--dry-run']), 0);
    expect(err.toString(), isEmpty);
    expect(
      out.toString(),
      matches(
        RegExp(
          '^${RegExp.escape(fr11)}\nplan [0-9a-f]{12}\n'
          'dry run: nothing removed\n\$',
        ),
      ),
    );
    expect(File('${root.path}/docs/$fr11').existsSync(), isTrue);
  });
  test(
    'ms-r11: --dry-run --json prints the files and the plan as one JSON object',
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
    test('ms-r11: delete ${args.join(' ')} is a usage error, exit 64, and '
        'removes nothing', () async {
      final root = await writeWriteProject();
      final (:runner, :out, :err) = writeRunner(root);
      expect(await runner.run(['delete', fr11Target, ...args]), 64);
      expect(out.toString(), isEmpty);
      expect(err.toString(), startsWith('$message\n'));
      expect(File('${root.path}/docs/$fr11').existsSync(), isTrue);
    });
  }
  test("ms-r11: --yes --plan with the dry run's hash deletes an approved "
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
    'ms-r11: --yes --plan --json prints the removed paths as one JSON object',
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
  test('ms-r11: --yes --plan after an uncommitted edit to a listed file '
      'exits 75 and removes nothing', () async {
    final root = await writeWriteProject();
    final hash = await _dryRunPlanHash(root, fr11Target);
    final file = File('${root.path}/docs/$fr11');
    file.writeAsStringSync('${file.readAsStringSync()}More.\n');
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run(['delete', fr11Target, '--yes', '--plan', hash]),
      75,
    );
    expect(out.toString(), isEmpty);
    expect(err.toString(), startsWith('the delete list is not the one'));
    expect(file.existsSync(), isTrue);
  });
  test(
    'ms-r11: --yes --plan with a stale hash exits 75 and removes nothing',
    () async {
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
    },
  );
  test('f02/us04/s3, f02/us04/fr02/e03: the Owner prompt goes to stdout, the removed paths after it', () async {
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
  test('f02/us04/s3, PD9: under --json the Owner prompt goes to stderr and stdout holds one JSON object', () async {
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
  test('f02/us04/fr01/e09: delete takes no --base', () async {
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
  test('f02/us04/fr01/e09: no target is argument_missing', () async {
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
  test('f02/us04/fr01/e10, f02/us04/fr04: two targets delete both, one removed path per line', () async {
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
  test("f02/us04/fr04/e02: an Agent's delete of an untyped doc with no draft exits 77", () async {
    final root = await writeWriteProject(extra: untyped);
    final (:runner, :out, :err) = writeRunner(root);
    expect(await runner.run(['delete', notes]), 77);
    expect(
      err.toString(),
      contains('holds guarded docs; only the Owner deletes them'),
    );
    expect(File('${root.path}/docs/$notes').existsSync(), isTrue);
  });
  test('f02/us04/s8, f02/us04/fr04/e03: at a terminal the Owner sees the list and the prompt, then the removed paths', () async {
    final root = await writeWriteProject(extra: untyped);
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(
        stdinIsTerminal: true,
        stdoutIsTerminal: true,
        answers: ['y'],
      ),
    );
    expect(await runner.run(['delete', notes, errors, index]), 0);
    expect(err.toString(), isEmpty);
    // The core lists a delete set sorted by code point, not in call order.
    const paths = '$index\n$errors\n$notes\n';
    expect(out.toString(), '${paths}delete 3 files? [y/N] $paths');
  });
  test('f02/us04/s9, f02/us04/fr04/e04: a referrer outside the set exits 64 and is named after ; also', () async {
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
  });
  const plan = 'superpowers/plans/plan.md';
  final withPlan = {
    ...untyped,
    'docs/$plan':
        '# Plan\n\nSee [the notes](../../specs/f01_login/api_notes.md).\n',
  };
  const dangles = '$plan links into $notes; the link will dangle';
  test('f02/us04/fr04/e08: --dry-run on a doc a plan links into exits 0 and warns on stderr that the link will dangle', () async {
    final root = await writeWriteProject(extra: withPlan);
    final (:runner, :out, :err) = writeRunner(root);

    final status = await runner.run(['delete', notes, '--dry-run']);

    expect(status, 0);
    expect(err.toString(), '⚠️ WARNING: $dangles\n');
    expect(out.toString(), startsWith('$notes\nplan '));
    expect(File('${root.path}/docs/$notes').existsSync(), isTrue);
  });
  test(
    'f02/us04/fr04/e08: under --json the link that will dangle is in warnings',
    () async {
      final root = await writeWriteProject(extra: withPlan);
      final (:runner, :out, :err) = writeRunner(root);

      final status = await runner.run(['delete', notes, '--dry-run', '--json']);

      expect(status, 0);
      expect(err.toString(), isEmpty);
      final json = jsonDecode(out.toString()) as Map;
      expect(json['files'], [notes]);
      expect(json['warnings'], [dangles]);
    },
  );
  test('f02/us04/fr04/e08: at a terminal, y deletes the doc a plan links into and warns that the link will dangle', () async {
    final root = await writeWriteProject(extra: withPlan);
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(
        stdinIsTerminal: true,
        stdoutIsTerminal: true,
        answers: ['y'],
      ),
    );

    final status = await runner.run(['delete', notes]);

    expect(status, 0);
    expect(err.toString(), '⚠️ WARNING: $dangles\n');
    expect(out.toString(), endsWith('delete 1 files? [y/N] $notes\n'));
    expect(File('${root.path}/docs/$notes').existsSync(), isFalse);
    expect(File('${root.path}/docs/$plan').existsSync(), isTrue);
  });
  const mentioningProject = 'prds/PROJECT.md';
  const mentionWarning =
      '$mentioningProject mentions $loginFeature; the mention will dangle';
  Future<Directory> mentionedLogin() => writeWriteProject(
    extra: {
      'docs/prds/FEATURES.md': '# Feature index\n\n## Systems\n- [Signup](features/f02_signup/FEATURE.md)\n',
      'docs/$persona':
          '---\ndraft: true\n---\n\n# Buyer\n\n## Profile\nBuys things.\n',
      'docs/$mentioningProject':
          '# Project context\n\nSee `features/f01_login/FEATURE.md`.\n',
    },
  );
  test('f02/us04/fr01/e13, ms-r11: --dry-run on a feature a typed doc mentions exits 0 and warns on stderr that the mention will dangle', () async {
    final root = await mentionedLogin();
    final (:runner, :out, :err) = writeRunner(root);

    expect(await runner.run(['delete', 'feature:login', '--dry-run']), 0);

    expect(err.toString(), '⚠️ WARNING: $mentionWarning\n');
    expect(File('${root.path}/docs/$loginFeature').existsSync(), isTrue);
  });
  test('f02/us04/fr01/e13: delete of a feature a typed doc mentions exits 0 and warns on stderr that the mention will dangle', () async {
    final root = await mentionedLogin();
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(
        stdinIsTerminal: true,
        stdoutIsTerminal: true,
        answers: ['y'],
      ),
    );

    expect(await runner.run(['delete', 'feature:login']), 0);

    expect(err.toString(), '⚠️ WARNING: $mentionWarning\n');
    expect(File('${root.path}/docs/$loginFeature').existsSync(), isFalse);
    expect(File('${root.path}/docs/$mentioningProject').existsSync(), isTrue);
  });
  test('f02/us04/fr04: delete --help shows several targets', () async {
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
  test('f02/us04/fr04/e01: an untyped DocPath that holds a space deletes that file', () async {
    const spaced = 'specs/f01_login/api notes.md';
    final root = await writeWriteProject(
      extra: {'docs/$spaced': '---\ndraft: true\n---\n\n# Notes\n'},
    );
    final (:runner, :out, :err) = writeRunner(root);
    expect(await runner.run(['delete', spaced]), 0);
    expect(out.toString(), '$spaced\n');
    expect(File('${root.path}/docs/$spaced').existsSync(), isFalse);
  });
  test('f02/us04/fr05: delete prints doc_referenced naming the journey, exit 64', () async {
    const journey = 'prds/journeys/sign_in/JOURNEY.md';
    final root = await writeWriteProject(
      extra: {
        // fr12 and story3 lose their links, so only the journey refers in.
        'docs/$fr12': '---\ndraft: true\ntraced_from: US-01\nverify_method: test\n---\n\n# Lock after failures\n\n## Statement\nThe system shall lock the account.\n',
        'docs/$story3': '---\nstatus: planned\ndraft: true\n---\n\n# Reset password\n\n## Use Case\nReset a password.\n',
        'docs/$journey':
            '---\ndraft: true\n---\n\n# Sign in\n\n## Goal\nGet in.\n\n'
            '## Flow\n\n## Steps\n'
            '### 1. Reset\nstep: login/reset_password S1\n',
      },
    );
    final (:runner, :out, :err) = writeRunner(root);
    expect(await runner.run(['delete', 'user_story:login/reset_password']), 64);
    expect(
      err.toString(),
      '$story3: docs outside user_story:login/reset_password link into it; also $journey\n',
    );
    expect(File('${root.path}/docs/$story3').existsSync(), isTrue);
  });

  group('record entries', () {
    const record = 'specs/f01_login/IMPLEMENTATION.md';
    const resetStory = 'user_story:login/reset_password';
    final removed = [story3, fr31, fr32];

    Future<Directory> recordProject() => writeWriteProject(
      extra: {
        // fr12 loses its link into story3, so the unit is free
        'docs/$fr12': '---\ndraft: true\ntraced_from: US-01\nverify_method: test\n---\n\n# Lock after failures\n\n## Statement\nThe system shall lock the account.\n',
        '.specstone/config.yaml': '${shippedPinsConfig()}code_root: app\n',
        '.specstone/templates/implementation.yaml':
            'id: implementation\n'
            'description: One feature record per target.\n'
            'path: specs/f{nn}_{slug}/IMPLEMENTATION.md\n'
            'parent: feature\n'
            'per_target: true\n'
            'fields:\n'
            '  - id: statuses\n'
            '    type: record_status\n'
            '    list: true\n',
        'docs/$record':
            "---\nstatuses:\n  - 'email_login:implemented'\n"
            "  - 'reset_password:implemented'\n---\n\n# Record\n",
      },
    );

    test('document_writing/delete_doc_subtree/delete_after_the_owners_ok_in_the_chat E11: --dry-run lists the record it rewrites before the plan line', () async {
      final root = await recordProject();
      final (:runner, :out, :err) = writeRunner(root);
      expect(await runner.run(['delete', resetStory, '--dry-run']), 0);
      expect(
        out.toString(),
        matches(
          RegExp(
            '^${removed.map(RegExp.escape).join(r'\n')}\n'
            'rewrites ${RegExp.escape(record)}: reset_password\n'
            'plan [0-9a-f]{12}\ndry run: nothing removed\n\$',
          ),
        ),
      );
    });

    test('document_writing/delete_doc_subtree/delete_after_the_owners_ok_in_the_chat E11: --dry-run --json prints each record with its path and entries', () async {
      final root = await recordProject();
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run(['delete', resetStory, '--dry-run', '--json']),
        0,
      );
      final answer = jsonDecode(out.toString()) as Map;
      expect(answer['files'], removed);
      expect(answer['records'], [
        {
          'path': record,
          'entries': ['reset_password'],
        },
      ]);
    });

    test('document_writing/delete_doc_subtree/delete_doc_subtree E16: --yes --plan removes the story and rewrites the record as a draft', () async {
      final root = await recordProject();
      final hash = await _dryRunPlanHash(root, resetStory);
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run(['delete', resetStory, '--yes', '--plan', hash]),
        0,
        reason: err.toString(),
      );
      expect(out.toString(), '${removed.join('\n')}\n');
      final text = File('${root.path}/docs/$record').readAsStringSync();
      expect(text, contains("'email_login:implemented'"));
      expect(text, isNot(contains('reset_password')));
      expect(text, contains('draft: true'));
    });

    test('document_writing/delete_doc_subtree/delete_after_the_owners_ok_in_the_chat E11: a record edited after the dry run is plan_mismatch, exit 75, and nothing changes', () async {
      final root = await recordProject();
      final hash = await _dryRunPlanHash(root, resetStory);
      final file = File('${root.path}/docs/$record');
      file.writeAsStringSync('${file.readAsStringSync()}More.\n');
      final edited = file.readAsStringSync();
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run(['delete', resetStory, '--yes', '--plan', hash]),
        75,
      );
      expect(File('${root.path}/docs/$story3').existsSync(), isTrue);
      expect(file.readAsStringSync(), edited);
    });
  });

  group('with two code targets', () {
    test('document_writing/delete_doc_subtree/delete_doc_subtree: --target keeps the names to one target; a target the project lacks exits 64', () async {
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
}
