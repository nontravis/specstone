// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/write_fixture.dart';
import '../../helpers/write_runner.dart';

void main() {
  test('f02/us03/s7, f02/us03/fr01/e04: approve without a terminal exits 77 and shows nothing', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['approve']), 77);
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      "approve runs only at an interactive terminal, or with --yes after the Owner's ok in Claude Code\n",
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
  test('ms-r10: --yes approves the named drafts with no terminal and no prompt, one line each', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run([
        'approve',
        'feature:signup',
        'fr:login/email_login/lock_after_failures',
        '--yes',
      ]),
      0,
    );
    expect(err.toString(), isEmpty);
    expect(
      out.toString(),
      'approved fr:login/email_login/lock_after_failures\n'
      'approved feature:signup\n'
      'approved architecture:signup\n',
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
  test('ms-r10: --yes on a name with no draft exits 65 naming it, and approves nothing', () async {
    final root = await writeWriteProject();
    final before = File('${root.path}/docs/$signupFeature').readAsStringSync();
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run([
        'approve',
        'feature:signup',
        'architecture:login',
        '--yes',
      ]),
      65,
    );
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      'no draft waits for approval under architecture:login\n',
    );
    expect(File('${root.path}/docs/$signupFeature').readAsStringSync(), before);
  });
  test('ms-r10: --yes on a name no doc carries is doc_not_found, exit 64, and approves nothing', () async {
    final root = await writeWriteProject();
    final before = File('${root.path}/docs/$signupFeature').readAsStringSync();
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run([
        'approve',
        'feature:signup',
        'feature:nosuch',
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
        '--yes Approve the named drafts without the terminal prompt; the Claude Code plugin asks the Owner first.',
      ),
    );
    expect(
      out.toString(),
      contains('Usage: specstone approve [<name> …] [--yes]'),
    );
  });
}
