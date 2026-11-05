import 'dart:convert';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/nested_fixture.dart';
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
  test(
    'f02/us05/fr02/e10: reorder lists a doc changed by a path mention only',
    () async {
      final root = await writeWriteProject(
        extra: {
          'docs/prds/NOTES.md': '# Notes\n\nSee `features/f01_login/us03_reset_password/USER_STORY.md:4`.\n',
        },
      );
      final (:runner, :out, :err) = writeRunner(root);

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
      expect(out.toString(), contains('rewrote prds/NOTES.md\n'));
      expect(
        readDoc(root, 'prds/NOTES.md'),
        '# Notes\n\nSee `features/f01_login/us01_reset_password/USER_STORY.md:4`.\n',
      );
    },
  );
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
  test(
    'f02/us05/fr01/e10: two positionals are a usage error, exit 64',
    () async {
      final (:runner, :out, :err) = writeRunner(await writeWriteProject());
      expect(await runner.run(['reorder', 'a', 'b']), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        contains(
          'Expected one target, got 2.\n\n'
          'Usage: specstone reorder (<type>:<name> | <path>) --to <n> '
          '[--json]\n',
        ),
      );
    },
  );
  test(
    'f02/us05/fr01/e07: reorder with no --to is argument_missing, exit 64',
    () async {
      final (:runner, :out, :err) = writeRunner(await writeWriteProject());
      expect(
        await runner.run(['reorder', 'user_story:login/reset_password']),
        64,
      );
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        'reorder needs a place, such as specstone reorder user_story:login/reset_password --to 1\n',
      );
    },
  );
  test(
    'f02/us05/fr01/e11: reorder renumbers a sub-feature inside its top feature',
    () async {
      final (:runner, :out, :err) = writeRunner(await writeNestedProject());
      expect(await runner.run(['reorder', 'feature:shop/pay', '--to', '1']), 0);
      expect(err.toString(), isEmpty);
      expect(
        out.toString(),
        startsWith(
          'moved prds/features/f02_shop/f02_pay/ to prds/features/f02_shop/f01_pay/\n'
          'moved prds/features/f02_shop/f01_cart/ to prds/features/f02_shop/f02_cart/\n',
        ),
      );
    },
  );

  test(
    'f02/us05/fr02/e13: reorder writes a rewritten typed doc laid out',
    () async {
      final root = await writeWriteProject(
        extra: {
          'docs/$fr12': '---\ndraft: true\ntraced_from: US-01\nverify_method: test\n---\n\n# Lock after failures\n\n## Statement\n\n\n\nThe system shall lock the account. See [reset](../us03_reset_password/USER_STORY.md#use-case).\n\n\n',
        },
      );
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run([
          'reorder',
          'user_story:login/reset_password',
          '--to',
          '1',
        ]),
        0,
      );
      final text = readDoc(
        root,
        'prds/features/f01_login/us02_email_login/fr02_lock_after_failures.md',
      );
      expect(text, contains('us01_reset_password/USER_STORY.md#use-case'));
      expect(text, isNot(contains('\n\n\n')));
      expect(text, contains('draft: true\n'));
    },
  );
}
