import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/nested_fixture.dart';
import '../../../../specstone_core/test/helpers/record_fixture.dart';
import '../../../../specstone_core/test/helpers/write_fixture.dart';
import '../../helpers/write_runner.dart';

void main() {
  test(
    'f01/us04/fr01/e14: reorder takes a bare name one doc carries',
    () async {
      final (:runner, :out, :err) = writeRunner(await writeWriteProject());
      expect(
        await runner.run(['reorder', 'login/reset_password', '--to', '1']),
        0,
      );
      expect(err.toString(), isEmpty);
      expect(
        out.toString(),
        startsWith(
          'moved prds/features/f01_login/us03_reset_password/ to prds/features/f01_login/us01_reset_password/\n',
        ),
      );
    },
  );

  test('reorder prints moved and rewrote lines', () async {
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
  test('reorder prints a path mention in a code file as a mentions line '
      'and keeps the file', () async {
    const code =
        '// docs/prds/features/f01_login/us03_reset_password/USER_STORY.md:4\n'
        '// `login/reset_password`\n';
    final root = await writeWriteProject(
      extra: {
        'docs/specs/TECH_STACK.md':
            '---\ncode:\n  - app/lib/\n---\n\n# Tech stack\n\n## Stack\n\n'
            '| Slot | Choice |\n|---|---|\n| Language | Dart |\n\n'
            '## Naming\n\n- snake_case file names\n',
        'app/lib/doc.dart': code,
      },
    );
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run([
        'reorder',
        'user_story:login/reset_password',
        '--to',
        '1',
        '--json',
      ]),
      0,
    );
    expect((jsonDecode(out.toString()) as Map)['mentions'], [
      {
        'path': 'app/lib/doc.dart',
        'line': 1,
        'mention':
            'docs/prds/features/f01_login/us03_reset_password/USER_STORY.md',
      },
    ]);
    expect(File('${root.path}/app/lib/doc.dart').readAsStringSync(), code);
  });

  test('reorder lists a doc changed by a path mention only', () async {
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
  });
  test(
    'a place outside the list prints the sidecar error line, exit 64',
    () async {
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
    },
  );
  test('persona --json is doc_type_not_movable', () async {
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
  test('reorder takes no --base', () async {
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
  test('no target is argument_missing', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['reorder', '--to', '1']), 64);
    expect(err.toString(), startsWith('reorder needs a target'));
  });
  test('two positionals are a usage error, exit 64', () async {
    final (:runner, :out, :err) = writeRunner(await writeWriteProject());
    expect(await runner.run(['reorder', 'a', 'b']), 64);
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      contains(
        'Expected one target, got 2.\n\n'
        'Usage: specstone reorder <doc address> --to <n> '
        '[--dry-run] [--target <name>] [--json]\n',
      ),
    );
  });
  test('reorder with no --to is argument_missing, exit 64', () async {
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
  });
  test('reorder renumbers a sub-feature inside its top feature', () async {
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
  });

  test('E13: reorder writes a rewritten typed doc laid out', () async {
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
  });

  group('with two code targets', () {
    Future<Directory> twins() => writeWriteProject(
      extra: {
        '.specstone/config.yaml': twinConfig(),
        '.specstone/templates/implementation.yaml': recordLayer,
        'docs/specs/flutter/f02_signup/IMPLEMENTATION.md': recordText(
          statuses: ['ghost:planned'],
        ),
        'docs/specs/jaspr/f02_signup/IMPLEMENTATION.md': recordText(
          statuses: ['ghost:planned'],
        ),
      },
    );

    test('E12: reorder --target takes a feature with its spec folder in every '
        'target', () async {
      final root = await twins();
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run([
          'reorder',
          'feature:signup',
          '--to',
          '1',
          '--target',
          'flutter',
        ]),
        0,
        reason: err.toString(),
      );
      expect(
        out.toString(),
        allOf(
          contains(
            'moved specs/flutter/f02_signup/ to specs/flutter/f01_signup/\n',
          ),
          contains(
            'moved specs/jaspr/f02_signup/ to specs/jaspr/f01_signup/\n',
          ),
        ),
      );
      expect(hasDoc(root, 'specs/jaspr/f01_signup/IMPLEMENTATION.md'), isTrue);
    });

    test('a --target the project lacks exits 64', () async {
      final (:runner, :out, :err) = writeRunner(await twins());
      expect(
        await runner.run([
          'reorder',
          'feature:signup',
          '--to',
          '1',
          '--target',
          'dart',
        ]),
        64,
      );
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        '--target dart: the code targets are flutter, jaspr\n',
      );
    });
  });

  group('--dry-run', () {
    const f = 'prds/features/f01_login';

    test('prints the moves and rewrites, then says nothing moved, and moves '
        'nothing', () async {
      final root = await writeWriteProject();
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run([
          'reorder',
          'user_story:login/reset_password',
          '--to',
          '1',
          '--dry-run',
        ]),
        0,
      );
      expect(err.toString(), isEmpty);
      expect(
        out.toString(),
        startsWith(
          'moves $f/us03_reset_password/ to $f/us01_reset_password/\n',
        ),
      );
      expect(
        out.toString(),
        contains('rewrites $f/us02_email_login/fr02_lock_after_failures.md\n'),
      );
      expect(out.toString(), endsWith('dry run: nothing moved\n'));
      expect(out.toString(), isNot(contains('rewrote')));
      expect(out.toString(), isNot(contains('plan ')));
      expect(docFile(root, story3).existsSync(), isTrue);
      expect(Directory('${root.path}/.specstone/trash').existsSync(), isFalse);
    });

    test('lists a path mention in a code file and keeps the file', () async {
      const code =
          '// docs/prds/features/f01_login/us03_reset_password/USER_STORY.md:4\n';
      final root = await writeWriteProject(
        extra: {
          'docs/specs/TECH_STACK.md':
              '---\ncode:\n  - app/lib/\n---\n\n# Tech stack\n\n## Stack\n\n'
              '| Slot | Choice |\n|---|---|\n| Language | Dart |\n\n'
              '## Naming\n\n- snake_case file names\n',
          'app/lib/doc.dart': code,
        },
      );
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run([
          'reorder',
          'user_story:login/reset_password',
          '--to',
          '1',
          '--dry-run',
        ]),
        0,
      );
      expect(
        out.toString(),
        endsWith(
          'mentions app/lib/doc.dart:1 '
          'docs/prds/features/f01_login/us03_reset_password/USER_STORY.md\n'
          'dry run: nothing moved\n',
        ),
      );
      expect(File('${root.path}/app/lib/doc.dart').readAsStringSync(), code);
    });

    test('--json prints moved, rewritten, mentions, and dryRun true', () async {
      final (:runner, :out, :err) = writeRunner(await writeWriteProject());
      expect(
        await runner.run([
          'reorder',
          'user_story:login/reset_password',
          '--to',
          '1',
          '--dry-run',
          '--json',
        ]),
        0,
      );
      final answer = jsonDecode(out.toString()) as Map;
      expect(answer.keys, containsAll(['moved', 'rewritten', 'mentions']));
      expect(answer['dryRun'], isTrue);
    });

    test('refuses a place out of range with the status and message the reorder '
        'gives', () async {
      final (:runner, :out, :err) = writeRunner(await writeWriteProject());
      final apply = await runner.run([
        'reorder',
        'user_story:login/reset_password',
        '--to',
        '9',
      ]);
      final applyErr = err.toString();
      final (runner: dryRunner, out: dryOut, err: dryErr) = writeRunner(
        await writeWriteProject(),
      );
      expect(
        await dryRunner.run([
          'reorder',
          'user_story:login/reset_password',
          '--to',
          '9',
          '--dry-run',
        ]),
        apply,
      );
      expect(apply, 64);
      expect(dryOut.toString(), isEmpty);
      expect(dryErr.toString(), applyErr);
    });
  });
}
