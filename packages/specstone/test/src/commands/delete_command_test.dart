import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/write_fixture.dart';
import '../../helpers/write_runner.dart';

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
      'fr:login/email_login/validate_credentials holds approved docs; '
      'only the Owner deletes them, at an interactive terminal',
    );
    expect(File('${root.path}/docs/$fr11').existsSync(), isTrue);
  });
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
  test(
    'f02/us04/fr01/e10: two positionals are a usage error, exit 64',
    () async {
      final (:runner, :out, :err) = writeRunner(await writeWriteProject());
      expect(await runner.run(['delete', 'a', 'b']), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        contains(
          'Expected one target, got 2.\n\n'
          'Usage: specstone delete <type>:<name> [--json]\n',
        ),
      );
    },
  );
}
