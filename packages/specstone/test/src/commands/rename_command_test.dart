import 'dart:convert';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/write_fixture.dart';
import '../../helpers/write_runner.dart';

void main() {
  test('f02/us06/s1: rename prints moved and rewrote lines', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(
      await runner.run([
        'rename',
        'user_story:login/reset_password',
        '--to',
        'recover_account',
      ]),
      0,
    );
    expect(err.toString(), isEmpty);
    expect(
      out.toString(),
      startsWith(
        'moved prds/features/f01_login/us03_reset_password/ to prds/features/f01_login/us03_recover_account/\n',
      ),
    );
    expect(
      out.toString(),
      contains(
        'rewrote prds/features/f01_login/us01_email_login/fr02_lock_after_failures.md\n',
      ),
    );
  });
  test('f02/us06/s5: a taken slug --json is doc_exists with file', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(
      await runner.run([
        'rename',
        'user_story:login/reset_password',
        '--to',
        'sign_out',
        '--json',
      ]),
      64,
    );
    expect(out.toString(), isEmpty);
    final error = (jsonDecode(err.toString()) as Map)['error'] as Map;
    expect(error['code'], 'doc_exists');
    expect(error['file'], story2);
  });
  test('f02/us06/fr01/e10: rename takes no --base', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(
      await runner.run([
        'rename',
        'user_story:login/reset_password',
        '--to',
        'x',
        '--base',
        'x',
      ]),
      64,
    );
  });
  test('f02/us06/fr01/e10: no target is argument_missing', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['rename', '--to', 'x']), 64);
    expect(err.toString(), startsWith('rename needs a target'));
  });
}
