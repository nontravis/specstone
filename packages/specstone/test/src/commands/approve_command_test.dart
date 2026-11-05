// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/git_repo.dart';
import '../../../../specstone_core/test/helpers/write_fixture.dart';
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
  test('f02/us03/s7: a terminal on stdin alone is still refused', () async {
    final (:runner, :out, :err) = writeRunner(
      await writeWriteProject(),
      console: FakeConsole(stdinIsTerminal: true),
    );
    expect(await runner.run(['approve']), 77);
    expect(out.toString(), isEmpty);
  });
  test('f02/us03/s1: at a terminal, y approves the draft', () async {
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
    expect(text, contains('approved: true'));
    expect(text, isNot(contains('draft: true')));
  });
  test('f02/us03/fr01: approve takes no --json', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['approve', '--json']), 64);
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
    expect(text, contains('approved: true'));
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
        '--yes needs each draft as <type>:<name>@<hash>, the hash row of '
        'specstone approve --dry-run (bases.doc of specstone get --json); '
        'got architecture:signup.\n',
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
        'Usage: specstone approve [<name> …] [--dry-run] [--context <n>] | <type>:<name>@<hash> … --yes',
      ),
    );
  });

  test(
    'f02/us03/fr05/e01: dry run needs no terminal and prints no colour',
    () async {
      final (:runner, :out, :err) = writeRunner(await writeWriteProject());
      expect(await runner.run(['approve', '--dry-run']), 0);
      expect(out.toString(), contains('### Draft 1/'));
      expect(out.toString(), contains('```diff'));
      expect(out.toString(), isNot(contains('\x1b[')));
      expect(err.toString(), isEmpty);
    },
  );
  test('f02/us03/fr05/e02: dry run with --yes is a usage error', () async {
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
  test('f02/us03/fr05/e03: a hash with --dry-run is a usage error', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run(['approve', '--dry-run', _seen(root, 'feature:signup')]),
      64,
    );
  });
  test('f02/us03/fr05/e07: --context rules', () async {
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
  test(
    'f02/us03/fr02/e16: the walk colours at a terminal unless NO_COLOR',
    () async {
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
    },
  );
  test(
    'f02/us03/fr05/e07: --yes with a bad --context reports --yes first',
    () async {
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
    },
  );
  test(
    'f02/us03/fr05/e01: dry run colours at a terminal unless NO_COLOR',
    () async {
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
    },
  );
  test('show_changes_since_approval E17: --dry-run on a layout-only draft shows no change', () async {
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
    test('f02/us03/fr05/e07: --dry-run shows the unchanged line by default, not at --context 0', () async {
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
    });
    test('f02/us03/fr02/e07: the walk shows the unchanged line by default, not at --context 0', () async {
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
    });
  });
}
