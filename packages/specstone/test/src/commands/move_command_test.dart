import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/nested_fixture.dart';
import '../../../../specstone_core/test/helpers/record_fixture.dart';
import '../../../../specstone_core/test/helpers/write_fixture.dart'
    show docFile, readDoc, testHome;
import '../../helpers/built_cli.dart';
import '../../helpers/write_runner.dart';

void main() {
  const addItemFolder = 'prds/features/f02_shop/f01_cart/us01_add_item';
  const movedFolder = 'prds/features/f02_shop/f02_pay/us03_add_item';
  const addItem = 'user_story:shop/cart/add_item';

  test('f01/us04/fr01/e14: move takes a bare name one doc carries', () async {
    final (:runner, :out, :err) = writeRunner(await writeNestedProject());
    expect(
      await runner.run(['move', 'shop/cart/add_item', '--under', 'shop/pay']),
      0,
    );
    expect(err.toString(), isEmpty);
    expect(
      out.toString(),
      startsWith('moved $addItemFolder/ to $movedFolder/\n'),
    );
  });

  test(
    'f02/us07/s1, sf-r3: move prints the moved line and the rewrote lines',
    () async {
      final (:runner, :out, :err) = writeRunner(await writeNestedProject());
      expect(await runner.run(['move', addItem, '--under', 'shop/pay']), 0);
      expect(err.toString(), isEmpty);
      expect(
        out.toString(),
        startsWith('moved $addItemFolder/ to $movedFolder/\n'),
      );
      expect(out.toString(), contains('rewrote $shopApi\n'));
    },
  );

  test('move --json prints moved and rewritten', () async {
    final (:runner, :out, :err) = writeRunner(await writeNestedProject());
    expect(
      await runner.run(['move', addItem, '--under', 'shop/pay', '--json']),
      0,
    );
    expect(err.toString(), isEmpty);
    final answer = jsonDecode(out.toString()) as Map;
    expect(answer['moved'], [
      {'from': '$addItemFolder/', 'to': '$movedFolder/'},
    ]);
    expect(answer['rewritten'], contains(shopApi));
  });

  test('a story moved under its own feature prints nothing, exit 0', () async {
    final (:runner, :out, :err) = writeRunner(await writeNestedProject());
    expect(
      await runner.run([
        'move',
        'user_story:shop/cart/drop_item',
        '--under',
        'shop/cart',
      ]),
      0,
    );
    expect(out.toString(), isEmpty);
    expect(err.toString(), isEmpty);
  });

  test('a feature that holds features is argument_invalid, exit 64', () async {
    final (:runner, :out, :err) = writeRunner(await writeNestedProject());
    expect(await runner.run(['move', addItem, '--under', 'shop']), 64);
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      'shop (feature) holds sub-features, so it takes no story\n',
    );
  });

  test('another doc type is doc_type_not_movable, exit 64', () async {
    final (:runner, :out, :err) = writeRunner(await writeNestedProject());
    expect(
      await runner.run([
        'move',
        'fr:shop/cart/add_item/check_stock',
        '--under',
        'shop/pay',
      ]),
      64,
    );
    expect(out.toString(), isEmpty);
    expect(err.toString(), 'fr docs cannot move; move takes a user_story\n');
  });

  test('no --under is argument_missing, exit 64', () async {
    final (:runner, :out, :err) = writeRunner(await writeNestedProject());
    expect(await runner.run(['move', addItem]), 64);
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      'move needs a feature, such as specstone move '
      'user_story:login/reset_password --under account\n',
    );
  });

  test('an --under nothing carries is doc_not_found, exit 64', () async {
    final (:runner, :out, :err) = writeRunner(await writeNestedProject());
    expect(await runner.run(['move', addItem, '--under', 'nothing']), 64);
    expect(out.toString(), isEmpty);
    expect(err.toString(), 'no feature doc carries the name nothing\n');
  });

  test(
    '--under feature:shop/pay and a path move the story as a bare name does',
    () async {
      for (final under in [
        'feature:shop/pay',
        'prds/features/f02_shop/f02_pay/FEATURE.md',
      ]) {
        final (:runner, :out, :err) = writeRunner(await writeNestedProject());
        expect(
          await runner.run(['move', addItem, '--under', under]),
          0,
          reason: under,
        );
        expect(err.toString(), isEmpty, reason: under);
        expect(
          out.toString(),
          startsWith('moved $addItemFolder/ to $movedFolder/\n'),
          reason: under,
        );
      }
    },
  );

  test('move --help names the three forms of --under', () async {
    final (:runner, :out, :err) = writeRunner(await writeNestedProject());
    expect(await runner.run(['move', '--help']), 0);
    expect(
      out.toString(),
      contains(
        'The feature that takes the stories: <doc type>:<name>, '
        'a bare name, or a path.',
      ),
    );
  });

  test('f02/us07/fr01/e12, P20: an --under with a #section suffix is argument_invalid, exit 64, and moves nothing', () async {
    final root = await writeNestedProject();
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run([
        'move',
        addItem,
        '--under',
        'feature:shop/pay#x',
        '--json',
      ]),
      64,
    );
    expect(out.toString(), isEmpty);
    expect(
      ((jsonDecode(err.toString()) as Map)['error'] as Map)['code'],
      'argument_invalid',
    );
    expect(docFile(root, '$addItemFolder/USER_STORY.md').existsSync(), isTrue);
  });

  test(
    'an --under that names 2 or more features is argument_invalid, exit 64',
    () async {
      final (:runner, :out, :err) = writeRunner(
        await writeNestedProject(
          extra: {'docs/prds/features/f02_shop/f03_pay/FEATURE.md': '# Pay\n'},
        ),
      );
      expect(await runner.run(['move', addItem, '--under', 'shop/pay']), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString().trimRight().split('\n').last,
        'shop/pay names 2 feature docs: $payFeature, '
        'prds/features/f02_shop/f03_pay/FEATURE.md',
      );
    },
  );

  test('no target is argument_missing, exit 64', () async {
    final (:runner, :out, :err) = writeRunner(await writeNestedProject());
    expect(await runner.run(['move', '--under', 'shop/pay']), 64);
    expect(err.toString(), startsWith('move needs a target'));
  });

  test('user_story:document_writing/move_story S4: several stories move in one call, in the order named', () async {
    const dropFolder = 'prds/features/f02_shop/f01_cart/us02_drop_item';
    final root = await writeNestedProject();
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run([
        'move',
        'shop/cart/drop_item',
        addItem,
        '--under',
        'shop/pay',
      ]),
      0,
    );
    expect(err.toString(), isEmpty);
    expect(
      out.toString(),
      startsWith(
        'moved $dropFolder/ to prds/features/f02_shop/f02_pay/us03_drop_item/\n'
        'moved $addItemFolder/ to prds/features/f02_shop/f02_pay/us04_add_item/\n',
      ),
    );
    expect(docFile(root, cartAdd).existsSync(), isFalse);
    expect(docFile(root, cartDrop).existsSync(), isFalse);
  });

  test('user_story:document_writing/move_story S5: one story that cannot move refuses the call, and nothing moves', () async {
    const clash = 'prds/features/f02_shop/f02_pay/us03_drop_item';
    final root = await writeNestedProject(
      extra: {'docs/$clash/USER_STORY.md': '# Drop item\n'},
    );
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run([
        'move',
        addItem,
        'user_story:shop/cart/drop_item',
        '--under',
        'shop/pay',
      ]),
      64,
    );
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      '$clash/USER_STORY.md: a user_story named shop/pay/drop_item exists\n',
    );
    expect(docFile(root, cartAdd).existsSync(), isTrue);
    expect(docFile(root, cartDrop).existsSync(), isTrue);
    expect(docFile(root, '$movedFolder/USER_STORY.md').existsSync(), isFalse);
  });

  test('E12: move --help names the several-story form', () async {
    final (:runner, :out, :err) = writeRunner(await writeNestedProject());
    expect(await runner.run(['move', '--help']), 0);
    expect(
      out.toString(),
      contains(
        'specstone move <doc address> … --under <doc address> '
        '[--dry-run] [--json]',
      ),
    );
  });

  test(
    'E09: no target outside a project is argument_missing, exit 64',
    () async {
      final outside = Directory.systemTemp.createTempSync('specstone_move_');
      addTearDown(() => outside.deleteSync(recursive: true));
      final (:runner, :out, :err) = writeRunner(outside);
      expect(await runner.run(['move', '--under', 'shop/pay']), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        'move needs a target, such as specstone move '
        'user_story:login/reset_password --under account\n',
      );
    },
  );

  test('E11: move writes a rewritten typed doc laid out', () async {
    final root = await writeNestedProject();
    final file = docFile(root, shopApi);
    file.writeAsStringSync('${file.readAsStringSync()}\n\n\n');
    final (:runner, :out, :err) = writeRunner(root);
    expect(await runner.run(['move', addItem, '--under', 'shop/pay']), 0);
    expect(err.toString(), isEmpty);
    expect(readDoc(root, shopApi), isNot(contains('\n\n\n')));
  });

  test(
    'E04: move rewrites an fr traced_from entry and confirmed label',
    () async {
      final root = await writeNestedProject(
        extra: {
          'docs/$cartAddFr': '---\ntraced_from: [S1, shop/pay/card#S1]\nverify_method: test\nconfirmed:\n  - shop/pay/card#S1 0123456789ab\n---\n\n# Check stock\n\n## Statement\nThe system shall check.\n',
        },
      );
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run([
          'move',
          'user_story:shop/pay/card',
          '--under',
          'shop/cart',
        ]),
        0,
      );
      final text = readDoc(root, cartAddFr);
      expect(text, contains('traced_from: [S1, shop/cart/card#S1]\n'));
      expect(text, contains('  - shop/cart/card#S1 0123456789ab\n'));
      expect(out.toString(), contains('rewrote $cartAddFr\n'));
    },
  );

  test('move keeps a code file as it is and prints its mention after the '
      'rewrote lines', () async {
    const code =
        '// Adds `user_story:shop/cart/add_item#acceptance_criteria`.\n';
    final root = await writeNestedProject(extra: {'app/lib/cart.dart': code});
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run(['move', 'shop/cart/add_item', '--under', 'shop/pay']),
      0,
    );
    expect(err.toString(), isEmpty);
    expect(out.toString(), isNot(contains('rewrote app/lib/cart.dart')));
    expect(
      out.toString(),
      endsWith(
        'mentions app/lib/cart.dart:1 '
        'user_story:shop/cart/add_item#acceptance_criteria\n',
      ),
    );
    expect(File('${root.path}/app/lib/cart.dart').readAsStringSync(), code);
  });

  group('with two code targets', () {
    const cartFlutter = 'specs/flutter/f02_shop/f01_cart/IMPLEMENTATION.md';
    const cartJaspr = 'specs/jaspr/f02_shop/f01_cart/IMPLEMENTATION.md';
    const payFlutter = 'specs/flutter/f02_shop/f02_pay/IMPLEMENTATION.md';

    Future<Directory> shopTwins() => writeNestedProject(
      extra: {
        '.specstone/config.yaml': twinConfig(),
        '.specstone/templates/implementation.yaml': recordLayer,
        'docs/$cartFlutter': recordText(
          statuses: ['add_item:implemented', 'drop_item:planned'],
        ),
        'docs/$cartJaspr': recordText(
          statuses: ['add_item:planned', 'drop_item:planned'],
        ),
      },
    );

    test('E19, E20: move carries the entries of each target, rewriting the old '
        'records and listing the record it creates', () async {
      final root = await shopTwins();
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run(['move', addItem, '--under', 'shop/pay', '--json']),
        0,
        reason: err.toString(),
      );
      final answer = jsonDecode(out.toString()) as Map;
      expect(answer['rewritten'], containsAll([cartFlutter, cartJaspr]));
      expect(answer['rewritten'], contains(payFlutter));
      expect(readDoc(root, cartFlutter), isNot(contains('add_item')));
      expect(readDoc(root, payFlutter), contains("'add_item:implemented'"));
      expect(readDoc(root, payFlutter), contains('draft: true'));
    });

    test('move takes no --target, since a story is shared', () async {
      final (:runner, :out, :err) = writeRunner(await shopTwins());
      expect(
        await runner.run([
          'move',
          addItem,
          '--under',
          'shop/pay',
          '--target',
          'flutter',
        ]),
        64,
      );
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        contains('Could not find an option named "--target"'),
      );
    });
  });

  group('--dry-run', () {
    const code =
        '// Adds `user_story:shop/cart/add_item#acceptance_criteria`.\n';

    test('prints the moves, rewrites, and mentions, then says nothing moved, '
        'and moves nothing', () async {
      final root = await writeNestedProject(extra: {'app/lib/cart.dart': code});
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run(['move', addItem, '--under', 'shop/pay', '--dry-run']),
        0,
      );
      expect(err.toString(), isEmpty);
      expect(
        out.toString(),
        startsWith('moves $addItemFolder/ to $movedFolder/\n'),
      );
      expect(out.toString(), contains('rewrites $shopApi\n'));
      expect(
        out.toString(),
        endsWith(
          'mentions app/lib/cart.dart:1 '
          'user_story:shop/cart/add_item#acceptance_criteria\n'
          'dry run: nothing moved\n',
        ),
      );
      expect(out.toString(), isNot(contains('moved $addItemFolder')));
      expect(out.toString(), isNot(contains('plan ')));
      expect(
        Directory('${root.path}/docs/$addItemFolder').existsSync(),
        isTrue,
      );
      expect(Directory('${root.path}/docs/$movedFolder').existsSync(), isFalse);
      expect(Directory('${root.path}/.specstone/trash').existsSync(), isFalse);
    });

    test('--json prints moved, rewritten, mentions, and dryRun true', () async {
      final root = await writeNestedProject(extra: {'app/lib/cart.dart': code});
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run([
          'move',
          addItem,
          '--under',
          'shop/pay',
          '--dry-run',
          '--json',
        ]),
        0,
      );
      final answer = jsonDecode(out.toString()) as Map;
      expect(answer.keys, containsAll(['moved', 'rewritten', 'mentions']));
      expect(answer['dryRun'], isTrue);
      expect(answer['moved'], [
        {'from': '$addItemFolder/', 'to': '$movedFolder/'},
      ]);
      expect(answer['mentions'], [
        {
          'path': 'app/lib/cart.dart',
          'line': 1,
          'mention': 'user_story:shop/cart/add_item#acceptance_criteria',
        },
      ]);
    });

    test('refuses a feature that holds features with the status and message '
        'the move gives', () async {
      final (:runner, :out, :err) = writeRunner(await writeNestedProject());
      expect(
        await runner.run(['move', addItem, '--under', 'shop', '--dry-run']),
        64,
      );
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        'shop (feature) holds sub-features, so it takes no story\n',
      );
    });

    group('through the built CLI', () {
      late String binary;
      setUpAll(() async {
        binary = await buildSpecstone();
      });

      test('exits 0 when git cannot start', () async {
        final root = await writeNestedProject(
          extra: {'app/lib/cart.dart': code},
        );
        final emptyPath = Directory.systemTemp.createTempSync(
          'specstone_path_',
        );
        addTearDown(() => emptyPath.deleteSync(recursive: true));
        final home = testHome().path;
        final result = await Process.run(
          binary,
          ['move', addItem, '--under', 'shop/pay', '--dry-run'],
          workingDirectory: root.path,
          environment: {
            'PATH': emptyPath.path,
            'HOME': home,
            'USERPROFILE': home,
          },
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(
          result.stdout,
          startsWith('moves $addItemFolder/ to $movedFolder/\n'),
        );
        expect(
          result.stdout,
          endsWith(
            'mentions app/lib/cart.dart:1 '
            'user_story:shop/cart/add_item#acceptance_criteria\n'
            'dry run: nothing moved\n',
          ),
        );
      });
    });
  });
}
