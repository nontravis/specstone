import 'dart:convert';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/write_fixture.dart';
import '../../helpers/write_runner.dart';

void main() {
  test('f02/us05/s1: reorder prints moved and rewrote lines', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(
      await runner.run([
        'reorder',
        'user_story:login/reset_password',
        '--to',
        '1',
      ]),
      0,
    );
    expect(err.toString(), isEmpty);
    expect(
      out.toString(),
      startsWith(
        'moved prds/features/f01_login/us03_reset_password/ to prds/features/f01_login/us01_reset_password/\n',
      ),
    );
    expect(
      out.toString(),
      contains(
        'rewrote prds/features/f01_login/us02_email_login/fr02_lock_after_failures.md\n',
      ),
    );
  });
  test('f02/us05/s5: a place outside the list prints the sidecar error line, exit 64', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(
      await runner.run([
        'reorder',
        'user_story:login/reset_password',
        '--to',
        '5',
      ]),
      64,
    );
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      'user_story:login/reset_password cannot move to place 5: the places run from 1 to 3\n',
    );
  });
  test('f02/us05/s6: persona --json is doc_type_not_movable', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(
      await runner.run(['reorder', 'persona:buyer', '--to', '1', '--json']),
      64,
    );
    expect(out.toString(), isEmpty);
    expect(jsonDecode(err.toString()), {
      'error': {
        'code': 'doc_type_not_movable',
        'message': 'persona docs carry no number, so reorder cannot move them',
      },
    });
  });
  test('f02/us05/fr01/e10: reorder takes no --base', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(
      await runner.run([
        'reorder',
        'user_story:login/reset_password',
        '--to',
        '1',
        '--base',
        'x',
      ]),
      64,
    );
  });
  test('f02/us05/fr01/e10: no target is argument_missing', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['reorder', '--to', '1']), 64);
    expect(err.toString(), startsWith('reorder needs a target'));
  });
}
