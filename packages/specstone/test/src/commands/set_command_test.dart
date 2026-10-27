import 'dart:convert';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/write_fixture.dart';
import '../../helpers/write_runner.dart';

void main() {
  test(
    'f02/us01/s1: set prints the naming line with the new base, exit 0',
    () async {
      final root = await writeWriteProject();
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(input: 'Sign in with a passkey.\n'),
      );
      expect(
        await runner.run([
          'set',
          'user_story:login/email_login#use_case',
          '--base',
          '9042269552ff',
        ]),
        0,
      );
      expect(err.toString(), isEmpty);
      final line = RegExp(
        r'^==> login/email_login \(user_story\) · '
        '$story1'
        r' · base ([0-9a-f]{12}) <==\n$',
      ).firstMatch(out.toString());
      expect(line, isNotNull);
      final written = writeRunner(root);
      expect(
        await written.runner.run([
          'get',
          'user_story:login/email_login#use_case',
        ]),
        0,
      );
      expect(written.out.toString(), contains('base ${line!.group(1)}'));
      expect(written.out.toString(), contains('Sign in with a passkey.'));
    },
  );
  test('f02/us01/s8, f02/us01/fr02/e06: a stale base prints the fault on stderr and only the current section on stdout, exit 75', () async {
    final root = await writeWriteProject();
    final (:runner, :out, :err) = writeRunner(
      root,
      console: FakeConsole(input: 'x\n'),
    );
    expect(
      await runner.run([
        'set',
        'user_story:login/email_login#use_case',
        '--base',
        '000000000000',
      ]),
      75,
    );
    expect(
      err.toString(),
      '$story1: use_case: the section changed since base 000000000000\n',
    );
    expect(
      out.toString(),
      '==> login/email_login (user_story) · $story1 · base 9042269552ff <==\n'
      '## Use Case\nSign in with an email.\n',
    );
  });
  test(
    'f02/us01/fr02: --json keeps stdout empty and puts current in the envelope',
    () async {
      final root = await writeWriteProject();
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(input: 'x\n'),
      );
      expect(
        await runner.run([
          'set',
          'user_story:login/email_login#use_case',
          '--base',
          '000000000000',
          '--json',
        ]),
        75,
      );
      expect(out.toString(), isEmpty);
      expect(((jsonDecode(err.toString()) as Map)['error'] as Map)['current'], {
        'text': '## Use Case\nSign in with an email.\n',
        'base': '9042269552ff',
      });
    },
  );
  test(
    'f02/us01/s9: --field draft --json is field_not_writable with file and key',
    () async {
      final root = await writeWriteProject();
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(input: 'false\n'),
      );
      expect(
        await runner.run([
          'set',
          'user_story:login/email_login',
          '--field',
          'draft',
          '--base',
          '000000000000',
          '--json',
        ]),
        64,
      );
      expect(out.toString(), isEmpty);
      expect(jsonDecode(err.toString()), {
        'error': {
          'code': 'field_not_writable',
          'message': 'draft is written only by specstone approve',
          'file': story1,
          'key': 'draft',
        },
      });
    },
  );
  test('f02/us01/fr01/e12: no --base is argument_missing', () async {
    final (:runner, :out, :err) = writeRunner(
      await writeWriteProject(),
      console: FakeConsole(input: 'x\n'),
    );
    expect(
      await runner.run(['set', 'user_story:login/email_login#use_case']),
      64,
    );
    expect(out.toString(), isEmpty);
    expect(err.toString(), startsWith('set needs --base'));
  });
  test('f02/us01/s12: an untyped doc is untyped_target, exit 64', () async {
    final (:runner, :out, :err) = writeRunner(
      await writeWriteProject(),
      console: FakeConsole(input: 'x\n'),
    );
    expect(
      await runner.run([
        'set',
        'd01_context#use_case',
        '--base',
        '000000000000',
      ]),
      64,
    );
    expect(out.toString(), isEmpty);
    expect(err.toString(), isNotEmpty);
  });
  test('f02/us01/fr01/e12: no target is argument_missing', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['set', '--base', '000000000000']), 64);
    expect(err.toString(), startsWith('set needs a target'));
  });
}
