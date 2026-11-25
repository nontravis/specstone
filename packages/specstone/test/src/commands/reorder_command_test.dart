import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/check_fixture.dart'
    show fingerprintFor;
import '../../../../specstone_core/test/helpers/fixed_numbers_fixture.dart';
import '../../../../specstone_core/test/helpers/nested_fixture.dart';
import '../../../../specstone_core/test/helpers/per_fr_row_fixture.dart';
import '../../../../specstone_core/test/helpers/record_fixture.dart';
import '../../../../specstone_core/test/helpers/write_fixture.dart';
import '../../helpers/write_runner.dart';

/// Returns every file and folder under `docs/` of [root], by its bytes.
Map<String, List<int>> _docsBytes(Directory root) => {
  for (final MapEntry(:key, :value) in treeBytes(root).entries)
    if (key.startsWith('docs/')) key: value,
};

void main() {
  test('reorder takes a bare name one doc carries', () async {
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
  });

  test('re-stamps a matched per-FR row after a reorder link rewrite', () async {
    final root = await writePerFrProject();
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run([
        'reorder',
        'user_story:shop/cart/drop_item',
        '--to',
        '1',
      ]),
      0,
    );
    expect(err.toString(), isEmpty);
    final reordered = perFrDropEdge.replaceAll(
      'us02_drop_item',
      'us01_drop_item',
    );
    expect(
      readDoc(root, cartRecord),
      endsWith('${perFrRow(fingerprintFor(perFrContractOf(reordered)))}\n'),
    );
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
      'warnings': <Object>[],
    });
  });
  test(
    'a fixed-number doc type is doc_type_not_movable, nothing moves',
    () async {
      final root = await writeWriteProject(extra: decisionFiles());
      final before = _docsBytes(root);
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run(['reorder', 'decision:use_wal', '--to', '1']),
        64,
      );
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        'decision docs keep their number, so reorder cannot move them\n',
      );
      expect(_docsBytes(root), before);
    },
  );
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
  test('reorder with no target is argument_missing', () async {
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
        '[--dry-run [--out [<path>]]] [--target <name>] [--json]\n',
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
  test('reorder writes a rewritten typed doc laid out', () async {
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

  test('reorder lays out the docs it rewrites and adds no missing section to '
      'them', () async {
    final root = await writeWriteProject();
    List<String> headersOf(String docPath) => RegExp(
      r'^## .*$',
      multiLine: true,
    ).allMatches(readDoc(root, docPath)).map((match) => match[0]!).toList();
    final frBefore = headersOf(fr12);
    expect(frBefore, ['## Statement']);
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
    const reordered =
        'prds/features/f01_login/us02_email_login/fr02_lock_after_failures.md';
    expect(out.toString(), contains('rewrote $reordered\n'));
    expect(headersOf(reordered), frBefore);
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

    test('reorder --target takes a feature with its spec folder in every '
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

    test('each login spec folder becomes f02 in every target', () async {
      final root = await writeWriteProject(
        extra: {
          '.specstone/config.yaml': twinConfig(),
          '.specstone/templates/implementation.yaml': recordLayer,
          for (final target in ['flutter', 'jaspr']) ...{
            'docs/specs/$target/f01_login/IMPLEMENTATION.md': recordText(
              statuses: ['ghost:planned'],
            ),
            'docs/specs/$target/f02_signup/IMPLEMENTATION.md': recordText(
              statuses: ['ghost:planned'],
            ),
          },
        },
      );
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
            'moved specs/flutter/f01_login/ to specs/flutter/f02_login/\n',
          ),
          contains('moved specs/jaspr/f01_login/ to specs/jaspr/f02_login/\n'),
          contains(
            'moved specs/flutter/f02_signup/ to specs/flutter/f01_signup/\n',
          ),
          contains(
            'moved specs/jaspr/f02_signup/ to specs/jaspr/f01_signup/\n',
          ),
        ),
      );
      for (final target in ['flutter', 'jaspr']) {
        expect(
          hasDoc(root, 'specs/$target/f02_login/IMPLEMENTATION.md'),
          isTrue,
        );
        expect(
          hasDoc(root, 'specs/$target/f01_login/IMPLEMENTATION.md'),
          isFalse,
        );
      }
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
  group('a reorder target named by the end of its name', () {
    test('reorder takes a unique suffix as it takes the full name', () async {
      final full = writeRunner(await writeNestedProject());
      expect(
        await full.runner.run(['reorder', 'feature:shop/pay', '--to', '1']),
        0,
      );
      final short = writeRunner(await writeNestedProject());
      expect(
        await short.runner.run(['reorder', 'feature:pay', '--to', '1']),
        0,
      );
      expect(short.out.toString(), full.out.toString());
    });
    test('reorder refuses a suffix of no identity, naming it', () async {
      final (:runner, :out, :err) = writeRunner(await writeNestedProject());
      expect(await runner.run(['reorder', 'feature:ay', '--to', '1']), 64);
      expect(out.toString(), isEmpty);
      expect(err.toString(), 'no feature doc carries the name ay\n');
    });
  });

  group('a reorder refusal prints its code with --json, exit 64', () {
    Future<Map<String, Object?>> errorOf(
      Directory root,
      List<String> args,
    ) async {
      final (:runner, :out, :err) = writeRunner(root);
      expect(await runner.run([...args, '--json']), 64);
      expect(out.toString(), isEmpty);
      return (jsonDecode(err.toString()) as Map<String, Object?>)['error']!
          as Map<String, Object?>;
    }

    test('a --to that is no whole number is argument_invalid', () async {
      final root = await writeWriteProject();
      final before = _docsBytes(root);
      expect(
        await errorOf(root, [
          'reorder',
          'user_story:login/reset_password',
          '--to',
          'abc',
        ]),
        {
          'code': 'argument_invalid',
          'message': '--to takes a whole number, got abc',
        },
      );
      expect(_docsBytes(root), before);
    });

    test('a name no doc carries is doc_not_found', () async {
      final root = await writeWriteProject();
      expect(await errorOf(root, ['reorder', 'nosuch', '--to', '1']), {
        'code': 'doc_not_found',
        'message': 'no doc carries the name nosuch',
      });
    });

    test('a name 2 docs carry is argument_invalid listing them', () async {
      final root = await writeWriteProject();
      expect(await errorOf(root, ['reorder', 'login', '--to', '1']), {
        'code': 'argument_invalid',
        'message': 'login names 2 docs: feature:login, architecture:login',
      });
    });

    test('a path to an untyped doc is untyped_target', () async {
      final root = await writeWriteProject(
        extra: {'docs/specs/f01_login/api_notes.md': '# Notes\n'},
      );
      final before = _docsBytes(root);
      expect(
        await errorOf(root, [
          'reorder',
          'specs/f01_login/api_notes.md',
          '--to',
          '1',
        ]),
        {
          'code': 'untyped_target',
          'message': 'specs/f01_login/api_notes.md has no doc type; migrate it to one before a write',
        },
      );
      expect(_docsBytes(root), before);
    });
  });

  test('a --to equal to the place a doc holds moves nothing, exit 0', () async {
    final root = await writeWriteProject();
    final before = _docsBytes(root);
    final (:runner, :out, :err) = writeRunner(root);

    expect(
      await runner.run([
        'reorder',
        'user_story:login/reset_password',
        '--to',
        '3',
      ]),
      0,
    );

    expect(err.toString(), isEmpty);
    expect(_docsBytes(root), before);
  });

  group('--out', () {
    for (final json in [false, true]) {
      test('reorder --dry-run${json ? ' --json' : ''} --out saves the dry run '
          'reply and changes no doc', () async {
        final root = await writeWriteProject();
        final before = _docsBytes(root);
        final call = [
          'reorder',
          'user_story:login/reset_password',
          '--to',
          '1',
          '--dry-run',
          if (json) '--json',
        ];
        final (runner: plain, out: printed, err: _) = writeRunner(root);
        expect(await plain.run(call), 0);

        final (:runner, :out, :err) = writeRunner(root);
        expect(await runner.run([...call, '--out', 'dry.txt']), 0);

        expect(err.toString(), isEmpty);
        expect(
          File('${root.path}/dry.txt').readAsStringSync(),
          printed.toString(),
        );
        if (json) {
          expect(jsonDecode(out.toString()), containsPair('lines', isA<int>()));
        } else {
          expect(
            out.toString(),
            matches(RegExp(r'^==> reorder: \d+ lines, \d+ tokens · ')),
          );
        }
        expect(_docsBytes(root), before);
      });
    }

    test(
      'reorder --out with no --dry-run is argument_invalid and changes no doc',
      () async {
        final root = await writeWriteProject();
        final before = _docsBytes(root);
        final (:runner, :out, :err) = writeRunner(root);

        expect(
          await runner.run([
            'reorder',
            'user_story:login/reset_password',
            '--to',
            '1',
            '--out',
            'gone.txt',
          ]),
          64,
        );

        expect(out.toString(), isEmpty);
        expect(err.toString(), '--out goes with --dry-run\n');
        expect(File('${root.path}/gone.txt').existsSync(), isFalse);
        expect(_docsBytes(root), before);
      },
    );
  });
}
