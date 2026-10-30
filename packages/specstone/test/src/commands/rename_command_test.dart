import 'dart:convert';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/check_fixture.dart'
    show writeCheckProject;
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
  test(
    'f02/us06/fr01/e10: two positionals are a usage error, exit 64',
    () async {
      final (:runner, :out, :err) = writeRunner(await writeWriteProject());
      expect(await runner.run(['rename', 'a', 'b']), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        contains(
          'Expected one target, got 2.\n\n'
          'Usage: specstone rename <type>:<name> --to <slug> [--json]\n',
        ),
      );
    },
  );
  test(
    'f02/us06/fr01/e07: rename with no --to is argument_missing, exit 64',
    () async {
      final (:runner, :out, :err) = writeRunner(await writeWriteProject());
      expect(
        await runner.run(['rename', 'user_story:login/reset_password']),
        64,
      );
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        'rename needs a slug, such as specstone rename user_story:login/reset_password --to recover_account\n',
      );
    },
  );
  test('f02/us06/fr03: rename --json lists the rewritten journey', () async {
    const journey = 'prds/journeys/sign_in/JOURNEY.md';
    final root = await writeCheckProject(
      extra: {
        'docs/$journey':
            '# Sign in\n\n## Goal\nGet in.\n\n## Flow\n\n## Steps\n'
            '### 1. Sign in\nstep: login/email_login S1\n',
      },
    );
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run([
        'rename',
        'user_story:login/email_login',
        '--to',
        'password_login',
        '--json',
      ]),
      0,
    );
    expect(err.toString(), isEmpty);
    final rewritten = (jsonDecode(out.toString()) as Map)['rewritten'] as List;
    expect(rewritten, contains(journey));
  });
}
