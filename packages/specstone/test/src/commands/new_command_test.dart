import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/write_fixture.dart';
import '../../helpers/write_runner.dart';

void main() {
  const newStory = 'prds/features/f01_login/us04_recover_account/USER_STORY.md';
  test('f02/us02/s1: new prints the naming line, exit 0', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(stdinIsTerminal: true),
    );
    expect(
      await runner.run([
        'new',
        'user_story',
        '--parent',
        'login',
        '--slug',
        'recover_account',
      ]),
      0,
    );
    expect(err.toString(), isEmpty);
    expect(
      out.toString(),
      '==> login/recover_account (user_story) · $newStory <==\n',
    );
    final text = File('${root.path}/docs/$newStory').readAsStringSync();
    expect(text, startsWith('---\ndraft: true\n---\n\n# recover_account\n'));
    expect(text, contains('## Use Case'));
  });
  test('f02/us02/s2: piped stdin is the doc text', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(
        input: '# Recover account\n\n## Use Case\nRecover an account.\n',
      ),
    );
    expect(
      await runner.run([
        'new',
        'user_story',
        '--parent',
        'login',
        '--slug',
        'recover_account',
      ]),
      0,
    );
    expect(err.toString(), isEmpty);
    expect(
      out.toString(),
      '==> login/recover_account (user_story) · $newStory <==\n',
    );
    final text = File('${root.path}/docs/$newStory').readAsStringSync();
    expect(text, contains('Recover an account.'));
    expect(text, contains('draft: true'));
    expect(text, isNot(contains('<Role>')));
  });
  test('f02/us02/s7: a parent no doc carries exits 64', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(stdinIsTerminal: true),
    );
    expect(
      await runner.run([
        'new',
        'user_story',
        '--parent',
        'nobody',
        '--slug',
        'recover_account',
      ]),
      64,
    );
    expect(out.toString(), isEmpty);
    expect(err.toString(), isNotEmpty);
  });
  test(
    'f02/us02/fr01/e10: no --parent --json carries the sidecar message',
    () async {
      final root = await writeWriteProject();
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(stdinIsTerminal: true),
      );
      expect(
        await runner.run([
          'new',
          'user_story',
          '--slug',
          'reset_password',
          '--json',
        ]),
        64,
      );
      expect(out.toString(), isEmpty);
      expect(jsonDecode(err.toString()), {
        'error': {
          'code': 'argument_missing',
          'message': 'user_story needs --parent, the name of a feature',
        },
      });
    },
  );
  test('f02/us02/fr01/e10: no doc type is argument_missing', () async {
    final (:runner, :out, :err) = writeRunner(
      await writeWriteProject(),
      console: FakeConsole(stdinIsTerminal: true),
    );
    expect(await runner.run(['new']), 64);
    expect(err.toString(), startsWith('new needs a doc type'));
  });
}
