// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/check_fixture.dart';
import '../../../../specstone_core/test/helpers/git_repo.dart';
import '../../../../specstone_core/test/helpers/relative_link.dart';
import '../../../../specstone_core/test/helpers/target_fixture.dart';
import '../../../../specstone_core/test/helpers/temp_tree.dart';
import '../../../../specstone_core/test/helpers/write_fixture.dart';
import '../../helpers/built_cli.dart';
import '../../helpers/write_runner.dart';

/// Returns `<address>@<hash>`, the hash `get --json` prints as bases.doc.
String _seen(Directory root, String address) =>
    '$address@${(getDoc(root, address)['bases']! as Map)['doc']}';

void main() {
  test('f02/us03/s7, f02/us03/fr01/e04: approve without a terminal exits 77 and shows nothing', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['approve']), 77);
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      "approve runs only at an interactive terminal, or with --yes after the Owner's ok in the chat\n",
    );
  });
  test('a terminal on stdin alone is still refused', () async {
    final (:runner, :out, :err) = writeRunner(
      await writeWriteProject(),
      console: FakeConsole(stdinIsTerminal: true),
    );
    expect(await runner.run(['approve']), 77);
    expect(out.toString(), isEmpty);
  });
  test('at a terminal, y approves the draft', () async {
    final root = await writeWriteProject();
    final console = FakeConsole(
      stdinIsTerminal: true,
      stdoutIsTerminal: true,
      answers: ['y', 'y'],
    );
    final (:runner, :out, :err) = writeRunner(root, console: console);
    expect(await runner.run(['approve', 'signup']), 0);
    expect(err.toString(), isEmpty);
    expect(out.toString(), contains('approve? [y/n/q] '));
    final text = File('${root.path}/docs/$signupFeature').readAsStringSync();
    expect(text, matches(RegExp(r'\napproved: "[0-9a-f]{12}"\n')));
    expect(text, isNot(contains('draft: true')));
  });
  test(
    'ms-r10: at a terminal, two names walk the drafts under either',
    () async {
      final root = await writeWriteProject();
      final console = FakeConsole(
        stdinIsTerminal: true,
        stdoutIsTerminal: true,
        answers: List.filled(12, 'n'),
      );
      final (:runner, :out, :err) = writeRunner(root, console: console);
      expect(
        await runner.run([
          'approve',
          'feature:signup',
          'user_story:login/email_login',
        ]),
        0,
      );
      expect(err.toString(), isEmpty);
      expect('approve? [y/n/q] '.allMatches(out.toString()), hasLength(4));
    },
  );
  test('ms-r10: --yes approves each <type>:<name>@<hash> draft with no terminal and no prompt, one line each', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run([
        'approve',
        _seen(root, 'feature:signup'),
        _seen(root, 'fr:login/email_login/lock_after_failures'),
        '--yes',
      ]),
      0,
    );
    expect(err.toString(), isEmpty);
    expect(
      out.toString(),
      'approved fr:login/email_login/lock_after_failures\n'
      'approved feature:signup\n',
    );
    final text = File('${root.path}/docs/$signupFeature').readAsStringSync();
    expect(text, matches(RegExp(r'\napproved: "[0-9a-f]{12}"\n')));
    expect(text, isNot(contains('draft: true')));
  });
  test('ms-r10: --yes with no name is a usage error, exit 64', () async {
    final (:runner, :out, :err) = writeRunner(
      await writeWriteProject(),
      console: FakeConsole(stdinIsTerminal: true, stdoutIsTerminal: true),
    );
    expect(await runner.run(['approve', '--yes']), 64);
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      startsWith('--yes needs the names of the drafts it approves.\n'),
    );
  });
  test('ms-r10: --yes on a name without @<hash> is a usage error, exit 64, and approves nothing', () async {
    final root = await writeWriteProject();
    final before = File('${root.path}/docs/$signupFeature').readAsStringSync();
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run([
        'approve',
        _seen(root, 'feature:signup'),
        'architecture:signup',
        '--yes',
      ]),
      64,
    );
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      startsWith(
        '--yes needs each draft as <name>@<hash>, the hash from bases.doc of '
        'specstone get --json; got architecture:signup.\n',
      ),
    );
    expect(File('${root.path}/docs/$signupFeature').readAsStringSync(), before);
  });
  test('ms-r10: a @<hash> without --yes is a usage error, exit 64', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(stdinIsTerminal: true, stdoutIsTerminal: true),
    );
    final named = _seen(root, 'feature:signup');
    expect(await runner.run(['approve', named]), 64);
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      startsWith('$named: a @<hash> goes only with --yes.\n'),
    );
  });
  test('ms-r10: --yes on a draft changed since the Owner saw it exits 75 naming it, and approves nothing', () async {
    final root = await writeWriteProject();
    final named = _seen(root, 'feature:signup');
    final arch = _seen(root, 'architecture:signup');
    final file = File('${root.path}/docs/$signupFeature');
    file.writeAsStringSync('${file.readAsStringSync()}More.\n');
    final changed = file.readAsStringSync();
    final archBefore = File('${root.path}/docs/$signupArch').readAsStringSync();
    final (:runner, :out, :err) = writeRunner(root);
    expect(await runner.run(['approve', arch, named, '--yes']), 75);
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      '$signupFeature: doc: changed since the Owner saw them: feature:signup; '
      'show each again and ask for a new ok\n',
    );
    expect(file.readAsStringSync(), changed);
    expect(
      File('${root.path}/docs/$signupArch').readAsStringSync(),
      archBefore,
    );
  });
  test('ms-r10: --yes on a doc that is no draft exits 65 naming it, and approves nothing', () async {
    final root = await writeWriteProject();
    final before = File('${root.path}/docs/$signupFeature').readAsStringSync();
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run([
        'approve',
        _seen(root, 'feature:signup'),
        _seen(root, 'feature:login'),
        '--yes',
      ]),
      65,
    );
    expect(out.toString(), isEmpty);
    expect(err.toString(), 'feature:login is no draft waiting for approval\n');
    expect(File('${root.path}/docs/$signupFeature').readAsStringSync(), before);
  });
  test('ms-r10: --yes on a name no doc carries is doc_not_found, exit 64, and approves nothing', () async {
    final root = await writeWriteProject();
    final before = File('${root.path}/docs/$signupFeature').readAsStringSync();
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run([
        'approve',
        _seen(root, 'feature:signup'),
        'feature:nosuch@000000000000',
        '--yes',
      ]),
      64,
    );
    expect(out.toString(), isEmpty);
    expect(err.toString(), isNotEmpty);
    expect(File('${root.path}/docs/$signupFeature').readAsStringSync(), before);
  });
  test('ms-r10: the help names --yes and what it does', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['approve', '--help']), 0);
    expect(
      out.toString().replaceAll(RegExp(r'\s+'), ' '),
      contains(
        "--yes Approve the named drafts without the terminal prompt; the agent runs it after the Owner's ok.",
      ),
    );
    expect(
      out.toString(),
      contains(
        'Usage: specstone approve [<name> …] [--target <name>] [--dry-run] [--context <n> | --json] | <name>@<hash> … --yes [--target <name>]',
      ),
    );
    expect(
      out.toString().replaceAll(RegExp(r'\s+'), ' '),
      contains(
        '--json With --dry-run, print the drafts as one JSON object in place of the views.',
      ),
    );
  });

  test('dry run needs no terminal and prints no colour', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['approve', '--dry-run']), 0);
    expect(out.toString(), contains('### Draft 1/'));
    expect(out.toString(), contains('```diff'));
    expect(out.toString(), isNot(contains('\x1b[')));
    expect(err.toString(), isEmpty);
  });
  test(
    'dry run shows the no-copy cell for a never-approved doc, with the '
    'hint when it carries approved: on disk and without it otherwise',
    () async {
      String draft(String mark) =>
          '---\n$mark---\n\n# Signup\n\n## Problem\nUsers sign up.\n';
      final root = await writeWriteProject(
        extra: {'docs/$signupFeature': draft('approved: "0123456789ab"\n')},
      );
      expect(git(root, ['init', '-q']).exitCode, 0);
      expect(git(root, ['config', 'core.autocrlf', 'false']).exitCode, 0);
      commitAll(root, 'approved on disk, never committed as approved');
      var (:runner, :out, :err) = writeRunner(root);
      expect(await runner.run(['approve', '--dry-run']), 0);
      expect(
        out.toString(),
        contains('| old     | none: no commit holds an approved copy |\n'),
      );
      expect(
        out.toString(),
        contains(
          'commit an approval before you edit the doc again; '
          'the view compares against committed copies only\n',
        ),
      );

      final bare = await writeWriteProject(
        extra: {'docs/$signupFeature': draft('draft: true\n')},
      );
      expect(git(bare, ['init', '-q']).exitCode, 0);
      expect(git(bare, ['config', 'core.autocrlf', 'false']).exitCode, 0);
      commitAll(bare, 'only ever a draft');
      (:runner, :out, :err) = writeRunner(bare);
      expect(await runner.run(['approve', '--dry-run']), 0);
      expect(
        out.toString(),
        contains('| old     | none: no commit holds an approved copy |\n'),
      );
      expect(out.toString(), isNot(contains('commit an approval')));
    },
  );
  test('dry run with --yes is a usage error', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run([
        'approve',
        '--dry-run',
        '--yes',
        _seen(root, 'feature:signup'),
      ]),
      64,
    );
    expect(err.toString(), contains('--dry-run goes without --yes.'));
  });
  test('a hash with --dry-run is a usage error', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run(['approve', '--dry-run', _seen(root, 'feature:signup')]),
      64,
    );
  });
  group('E09', () {
    for (final (args, message) in [
      (['--json'], '--json goes only with --dry-run.'),
      (
        ['--yes', '--json', 'a@0123456789ab'],
        '--json goes only with --dry-run.',
      ),
      (
        ['--dry-run', '--json', '--context', '0'],
        '--json goes without --context.',
      ),
      (
        ['--dry-run', '--json', '--yes', 'a@0123456789ab'],
        '--dry-run goes without --yes.',
      ),
    ]) {
      test(
        'approve ${args.join(' ')} is a usage error, exit 64, and prints nothing',
        () async {
          final (:runner, :out, :err) = writeRunner(await writeWriteProject());

          expect(await runner.run(['approve', ...args]), 64);

          expect(out.toString(), isEmpty);
          expect(err.toString(), startsWith('$message\n'));
        },
      );
    }
  });
  group('E10', () {
    test('--dry-run --json prints one object holding each draft and the count, the drafts and hashes its view prints', () async {
      final root = await writeWriteProject();
      var (:runner, :out, :err) = writeRunner(root);
      expect(await runner.run(['approve', 'login', '--dry-run']), 0);
      final view = out.toString();

      (:runner, :out, :err) = writeRunner(root);
      expect(await runner.run(['approve', 'login', '--dry-run', '--json']), 0);

      expect(err.toString(), isEmpty);
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      final drafts = (json['drafts']! as List).cast<Map<String, Object?>>();
      expect(json['count'], drafts.length);
      expect(drafts, isNotEmpty);
      expect('### Draft '.allMatches(view), hasLength(drafts.length));
      for (final draft in drafts) {
        expect(draft, contains('name'));
        expect(draft, contains('dropped'));
        expect(draft, contains('new'));
        expect(view, contains('`${draft['hash']}`'));
        expect(view, contains('`docs/${draft['docPath']}`'));
      }
    });
    test(
      'no draft in scope prints an empty list and a count of 0, exit 0',
      () async {
        final (:runner, :out, :err) = writeRunner(await writeWriteProject());

        expect(
          await runner.run([
            'approve',
            'architecture:login',
            '--dry-run',
            '--json',
          ]),
          0,
        );

        expect(jsonDecode(out.toString()), {
          'drafts': <Object>[],
          'count': 0,
          'warnings': <Object>[],
        });
      },
    );
    test("roots awaiting the Owner's record refuse with exit 73 and the JSON error on stderr, and print no JSON", () async {
      final base = await writeTree({
        for (final MapEntry(:key, :value) in writeProject.entries)
          if (key.startsWith('docs/'))
            'ext/${key.substring(5)}': value
          else
            'src/clone/$key': value,
      });
      createRelativeLink('${base.path}/src/clone/docs', '../../ext');
      final (:runner, :out, :err) = writeRunner(
        Directory('${base.path}/src/clone'),
      );

      expect(await runner.run(['approve', '--dry-run', '--json']), 73);

      expect(out.toString(), isEmpty);
      expect(
        (jsonDecode(err.toString()) as Map)['error'],
        containsPair('code', 'output_not_writable'),
      );
    }, skip: Platform.isWindows ? 'a link needs a privilege on Windows' : null);
  });
  test('ms-r10: a @<hash> without --yes on a non-terminal is a usage error, exit 64', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(root);
    final named = _seen(root, 'feature:signup');
    expect(await runner.run(['approve', named]), 64);
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      startsWith('$named: a @<hash> goes only with --yes.\n'),
    );
  });
  test(
    'R70: a doc path holding @ names the doc, so --dry-run reads it',
    () async {
      final root = await writeWriteProject(
        extra: {'docs/prds/a@b.md': '---\ndraft: true\n---\n\n# A\n'},
      );
      final (:runner, :out, :err) = writeRunner(root);
      expect(await runner.run(['approve', 'prds/a@b.md', '--dry-run']), 0);
      expect(err.toString(), isEmpty);
      expect(out.toString(), 'no draft waits for approval\n');
    },
  );
  test(
    'R70: --yes on a doc path holding @ names the doc and asks for the hash',
    () async {
      const name = 'prds/a@0123456789ab.md';
      final root = await writeWriteProject(
        extra: {'docs/$name': '---\ndraft: true\n---\n\n# A\n'},
      );
      final (:runner, :out, :err) = writeRunner(root);
      expect(await runner.run(['approve', name, '--yes']), 64);
      expect(
        err.toString(),
        startsWith(
          '--yes needs each draft as <name>@<hash>, the hash from bases.doc of '
          'specstone get --json; got $name.\n',
        ),
      );
    },
  );
  test('--context rules', () async {
    final root = await writeWriteProject();
    final seen = _seen(root, 'feature:signup');
    var (:runner, :out, :err) = writeRunner(root);
    expect(await runner.run(['approve', '--yes', '--context', '3', seen]), 64);
    expect(err.toString(), contains('--context goes without --yes.'));
    for (final bad in ['-1', 'x']) {
      (:runner, :out, :err) = writeRunner(root);
      expect(await runner.run(['approve', '--dry-run', '--context', bad]), 64);
      expect(
        err.toString(),
        contains('--context takes a whole number from 0.'),
      );
    }
    (:runner, :out, :err) = writeRunner(root);
    expect(await runner.run(['approve', '--dry-run', '--context', '0']), 0);
  });
  test('the walk colours at a terminal unless NO_COLOR', () async {
    final root = await writeWriteProject();
    var (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(
        stdinIsTerminal: true,
        stdoutIsTerminal: true,
        answers: ['n'],
      ),
    );
    expect(await runner.run(['approve', 'signup']), 0);
    expect(out.toString(), contains('\x1b[32m+'));
    (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(
        stdinIsTerminal: true,
        stdoutIsTerminal: true,
        noColor: true,
        answers: ['n'],
      ),
    );
    expect(await runner.run(['approve', 'signup']), 0);
    expect(out.toString(), isNot(contains('\x1b[')));
  });
  test('--yes with a bad --context reports --yes first', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run([
        'approve',
        '--yes',
        '--context',
        'x',
        _seen(root, 'feature:signup'),
      ]),
      64,
    );
    expect(err.toString(), contains('--context goes without --yes.'));
  });
  test('dry run colours at a terminal unless NO_COLOR', () async {
    final root = await writeWriteProject();
    var (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(stdoutIsTerminal: true),
    );
    expect(await runner.run(['approve', '--dry-run']), 0);
    expect(out.toString(), contains('\x1b['));
    (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(stdoutIsTerminal: true, noColor: true),
    );
    expect(await runner.run(['approve', '--dry-run']), 0);
    expect(out.toString(), isNot(contains('\x1b[')));
  });
  test('E17: --dry-run on a layout-only draft shows no change', () async {
    const compact =
        '| Component | Responsibility |\n|---|---|\n| Signup form | Collects the email |\n';
    const padded =
        '| Component   | Responsibility |\n|-------------|----------------|\n| Signup form | Collects the email |\n';
    String arch(String mark, String table) =>
        '---\n$mark---\n\n# Signup architecture\n\n## Components\n\n$table';
    final root = await writeWriteProject(
      extra: {'docs/$signupArch': arch('approved: true\n', compact)},
    );
    expect(git(root, ['init', '-q']).exitCode, 0);
    expect(git(root, ['config', 'core.autocrlf', 'false']).exitCode, 0);
    commitAll(root, 'approved');
    File('${root.path}/docs/$signupArch')
        .writeAsStringSync(arch('draft: true\n', padded));
    commitAll(root, 'padded as a draft');
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run(['approve', '--dry-run', 'architecture:signup']),
      0,
    );
    expect(out.toString(), contains('| changes | none |'));
    expect(out.toString(), contains('no change since the approved copy'));
  });
  test('E23: --dry-run lists the sentence dropped and the one new, and not the one moved', () async {
    String story(String mark, String useCase) =>
        '---\nstatus: planned\n$mark---\n\n# Sign out\n\n## Use Case\n\n'
        '$useCase\n\n## Acceptance Criteria\n\n- **Given** a signed-in user\n';
    final root = await writeWriteProject(
      extra: {
        'docs/$story2': story(
          'approved: true\n',
          'Sign out. Clears the cookie. Ends the session.',
        ),
      },
    );
    expect(git(root, ['init', '-q']).exitCode, 0);
    expect(git(root, ['config', 'core.autocrlf', 'false']).exitCode, 0);
    commitAll(root, 'approved');
    File('${root.path}/docs/$story2')
        .writeAsStringSync(story('draft: true\n', 'Sign out. Warns the user.'));
    File('${root.path}/docs/prds/d01_context.md').writeAsStringSync(
      '# Context\n\n## Features\n'
      'See [signup](features/f02_signup/FEATURE.md). Ends the session.\n',
    );
    commitAll(root, 'edited as a draft');
    final (:runner, :out, :err) = writeRunner(root);

    expect(
      await runner.run(['approve', '--dry-run', 'user_story:login/sign_out']),
      0,
    );

    expect(out.toString(), contains('| dropped | 1 sentence dropped |\n'));
    expect(out.toString(), contains('| new     | 1 sentence new |\n'));
    expect(
      out.toString(),
      endsWith(
        '\n```\n\nDropped sentences:\n- Clears the cookie.\n\n'
        'New sentences:\n- Warns the user.\n',
      ),
    );
    expect(out.toString(), isNot(contains('- Ends the session.')));
  });
  group('--context reaches the view', () {
    Future<Directory> editedDraft() async {
      final root = await writeWriteProject(
        extra: {
          'docs/$signupFeature': '---\napproved: true\n---\n\n# Signup\n\n## Problem\nUsers create an account.\nThey stay signed in.\n',
        },
      );
      expect(git(root, ['init', '-q']).exitCode, 0);
      expect(git(root, ['config', 'core.autocrlf', 'false']).exitCode, 0);
      commitAll(root, 'approved');
      File('${root.path}/docs/$signupFeature').writeAsStringSync(
        '---\ndraft: true\n---\n\n# Signup\n\n## Problem\nUsers sign up.\nThey stay signed in.\n',
      );
      commitAll(root, 'edited as a draft');
      return root;
    }

    const kept = ' They stay signed in.';
    test(
      '--dry-run shows the unchanged line by default, not at --context 0',
      () async {
        final root = await editedDraft();
        var (:runner, :out, :err) = writeRunner(root);
        expect(await runner.run(['approve', '--dry-run', 'feature:signup']), 0);
        expect(out.toString(), contains(kept));
        (:runner, :out, :err) = writeRunner(root);
        expect(
          await runner.run([
            'approve',
            '--dry-run',
            '--context',
            '0',
            'feature:signup',
          ]),
          0,
        );
        expect(out.toString(), contains('+Users sign up.'));
        expect(out.toString(), isNot(contains(kept)));
      },
    );
    test(
      'the walk shows the unchanged line by default, not at --context 0',
      () async {
        final root = await editedDraft();
        for (final (args, shown) in [
          (<String>[], true),
          (['--context', '0'], false),
        ]) {
          final (:runner, :out, :err) = writeRunner(
            root,
            console: FakeConsole(
              stdinIsTerminal: true,
              stdoutIsTerminal: true,
              noColor: true,
              answers: ['n'],
            ),
          );
          expect(await runner.run(['approve', ...args, 'feature:signup']), 0);
          expect(out.toString(), contains('+Users sign up.'));
          expect(out.toString().contains(kept), shown);
        }
      },
    );
  });

  group('what awaits approval, through the built CLI', () {
    late String binary;
    setUpAll(() async {
      binary = await buildSpecstone();
    });

    Future<ProcessResult> run(Directory root, List<String> args) =>
        Process.run(binary, args, workingDirectory: root.path);

    String editedStory(String text) =>
        text.replaceFirst('Sign out.\n', 'Sign out of every device.\n');

    test('an approved story edited in an editor is walked, its view showing the edit', () async {
      final root = await writeWriteProject();
      File('${root.path}/docs/$story2').writeAsStringSync(
        editedStory(File('${root.path}/docs/$story2').readAsStringSync()),
      );
      final shown = await run(root, ['approve', '--dry-run']);
      expect(shown.exitCode, 0, reason: '${shown.stderr}');
      expect(shown.stdout, contains('`docs/$story2`'));
      expect(shown.stdout, contains('+Sign out of every device.'));
    });

    test(
      'a layout change keeps the approval, so the story is not walked',
      () async {
        final root = await writeWriteProject();
        final arch = File('${root.path}/docs/$loginArch');
        arch.writeAsStringSync(
          arch.readAsStringSync().replaceFirst(
            '| Component | Responsibility |\n|---|---|\n| Login form | Collects the email and the password |\n',
            '| Component  | Responsibility                       |\n|------------|--------------------------------------|\n| Login form | Collects the email and the password  |\n',
          ),
        );
        final shown = await run(root, ['approve', '--dry-run']);
        expect(shown.exitCode, 0, reason: '${shown.stderr}');
        expect(shown.stdout, isNot(contains('`docs/$loginArch`')));
      },
    );

    test('a story made in an editor with neither mark is walked, and its approval writes the hash', () async {
      const made = '# Reset password\n\n## Use Case\n\nReset a password.\n';
      final root = await writeWriteProject(extra: {'docs/$story3': made});
      final shown = await run(root, ['approve', '--dry-run']);
      expect(shown.stdout, contains('`docs/$story3`'));
      final hash = RegExp(r'\| hash +\| `([0-9a-f]{12})`').firstMatch(
        (await run(root, [
              'approve',
              '--dry-run',
              'user_story:login/reset_password',
            ])).stdout
            as String,
      );
      expect(hash, isNotNull);
      final approved = await run(root, [
        'approve',
        'user_story:login/reset_password@${hash!.group(1)}',
        '--yes',
      ]);
      expect(approved.exitCode, 0, reason: '${approved.stderr}');
      final text = File('${root.path}/docs/$story3').readAsStringSync();
      expect(text, matches(RegExp(r'^---\napproved: "[0-9a-f]{12}"\n---\n')));
      expect(text, isNot(contains('draft:')));
      final after = await run(root, [
        'approve',
        '--dry-run',
        'user_story:login/reset_password',
      ]);
      expect(after.stdout, isNot(contains('`docs/$story3`')));
    });

    test("--dry-run shows the changes against the project's own committed copy under an exported GIT_INDEX_FILE and GIT_DIR", () async {
      final root = await writeWriteProject(
        extra: {
          'docs/$signupFeature': '---\napproved: true\n---\n\n# Signup\n\n## Problem\nUsers create an account.\nThey stay signed in.\n',
        },
      );
      expect(git(root, ['init', '-q']).exitCode, 0);
      expect(git(root, ['config', 'core.autocrlf', 'false']).exitCode, 0);
      commitAll(root, 'approved');
      File('${root.path}/docs/$signupFeature').writeAsStringSync(
        '---\ndraft: true\n---\n\n# Signup\n\n## Problem\nUsers sign up.\nThey stay signed in.\n',
      );
      commitAll(root, 'edited as a draft');
      final other = await writeTree({'elsewhere.txt': 'another repository\n'});
      expect(git(other, ['init', '-q']).exitCode, 0);
      final junkIndex = File('${other.path}/junk-index')
        ..writeAsStringSync('not an index\n');
      const args = ['approve', '--dry-run', 'feature:signup'];

      final plain = await run(root, args);
      final exported = await Process.run(
        binary,
        args,
        workingDirectory: root.path,
        environment: {
          'GIT_INDEX_FILE': junkIndex.path,
          'GIT_DIR': '${other.path}/.git',
        },
      );

      expect(plain.exitCode, 0, reason: '${plain.stderr}');
      expect(plain.stdout, contains('+Users sign up.'));
      expect(exported.exitCode, 0, reason: '${exported.stderr}');
      expect(exported.stdout, plain.stdout);
    }, skip: hasGit ? null : 'git is not available');
  });

  group('with two code targets', () {
    const draft = '---\ndraft: true\n---\n\n# Login architecture\n';

    Future<Directory> twinDrafts() => writeTwinProject(
      extra: {
        'docs/$flutterArchitecture': draft,
        'docs/$jasprArchitecture': draft,
      },
    );

    test(
      'approve --dry-run --target jaspr --json lists the jaspr draft only',
      () async {
        final (:runner, :out, :err) = writeRunner(await twinDrafts());
        expect(
          await runner.run([
            'approve',
            '--dry-run',
            '--target',
            'jaspr',
            '--json',
          ]),
          0,
          reason: err.toString(),
        );
        final drafts = (jsonDecode(out.toString()) as Map)['drafts']! as List;
        expect(
          [for (final d in drafts) (d as Map)['docPath']],
          [jasprArchitecture],
        );
      },
    );

    test('--yes --target flutter approves the flutter twin and leaves the jaspr twin a draft', () async {
      final root = await twinDrafts();
      final hash = (getDoc(root, flutterArchitecture)['bases']! as Map)['doc'];
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run([
          'approve',
          'architecture:login@$hash',
          '--yes',
          '--target',
          'flutter',
        ]),
        0,
        reason: err.toString(),
      );
      expect(out.toString(), 'approved architecture:login\n');
      expect(
        readDoc(root, flutterArchitecture),
        isNot(contains('draft: true')),
      );
      expect(readDoc(root, jasprArchitecture), contains('draft: true'));
    });

    test(
      'at a terminal, y under --target jaspr approves that twin only',
      () async {
        final root = await twinDrafts();
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
            'approve',
            'architecture:login',
            '--target',
            'jaspr',
          ]),
          0,
          reason: err.toString(),
        );
        expect('approve? [y/n/q] '.allMatches(out.toString()), hasLength(1));
        expect(
          readDoc(root, jasprArchitecture),
          matches(RegExp('approved: "[0-9a-f]{12}"')),
        );
        expect(readDoc(root, flutterArchitecture), contains('draft: true'));
      },
    );

    test('--yes on a name two targets share, with no --target, exits 64 listing both docs', () async {
      final root = await twinDrafts();
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run([
          'approve',
          'architecture:login@000000000000',
          '--yes',
        ]),
        64,
      );
      expect(
        err.toString(),
        'architecture:login names 2 docs: '
        '$flutterArchitecture, $jasprArchitecture\n',
      );
      expect(readDoc(root, flutterArchitecture), contains('draft: true'));
      expect(readDoc(root, jasprArchitecture), contains('draft: true'));
    });

    test('--target with no value exits 64 naming the targets', () async {
      final (:runner, :out, :err) = writeRunner(
        await twinDrafts(),
        console: FakeConsole(stdinIsTerminal: true, stdoutIsTerminal: true),
      );
      expect(await runner.run(['approve', '--dry-run', '--target']), 64);
      expect(
        err.toString(),
        '--target needs a code target name: the code targets are flutter, jaspr\n',
      );
    });

    test(
      '--dry-run without --target shows each target status in the status row',
      () async {
        final root = await writeTwinProject(
          extra: {
            ...edit(loginStory, [('goals:\n', 'draft: true\ngoals:\n')]),
            'docs/specs/flutter/f01_login/IMPLEMENTATION.md': "---\nstatuses:\n  - 'email_login:implemented'\n---\n\n# Login implementation\n",
          },
        );
        final (:runner, :out, :err) = writeRunner(root);
        expect(
          await runner.run([
            'approve',
            '--dry-run',
            'user_story:login/email_login',
          ]),
          0,
          reason: err.toString(),
        );
        expect(
          out.toString(),
          contains('| status  | `flutter implemented · jaspr planned` |'),
        );
      },
    );
  });
}
