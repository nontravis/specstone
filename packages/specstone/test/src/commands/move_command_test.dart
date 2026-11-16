import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/nested_fixture.dart';
import '../../../../specstone_core/test/helpers/record_fixture.dart';
import '../../../../specstone_core/test/helpers/shipped_pins.dart';
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
      await runner.run(['move', 'architecture:shop', '--under', 'shop/pay']),
      64,
    );
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      'architecture docs cannot move; move takes a user_story, an fr, an nf, '
      'or a feature\n',
    );
  });

  test('neither --under nor --top is argument_missing, exit 64', () async {
    final (:runner, :out, :err) = writeRunner(await writeNestedProject());
    expect(await runner.run(['move', addItem]), 64);
    expect(out.toString(), isEmpty);
    expect(err.toString(), 'move needs --under <doc address> or --top\n');
  });

  test('--under with --top exits 64 with argument_conflict', () async {
    final root = await writeNestedProject();
    final (:runner, :out, :err) = writeRunner(root);
    expect(
      await runner.run([
        'move',
        addItem,
        '--under',
        'shop/pay',
        '--top',
        '--json',
      ]),
      64,
    );
    expect(out.toString(), isEmpty);
    expect(
      ((jsonDecode(err.toString()) as Map)['error'] as Map)['code'],
      'argument_conflict',
    );
    expect(docFile(root, '$addItemFolder/USER_STORY.md').existsSync(), isTrue);
  });

  test('--top beside a story target exits 64 and moves nothing', () async {
    final root = await writeNestedProject();
    final (:runner, :out, :err) = writeRunner(root);
    expect(await runner.run(['move', addItem, '--top']), 64);
    expect(out.toString(), isEmpty);
    expect(err.toString(), 'move takes --top only with feature targets\n');
    expect(docFile(root, '$addItemFolder/USER_STORY.md').existsSync(), isTrue);
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

  test('move --help names --top and every target form', () async {
    final (:runner, :out, :err) = writeRunner(await writeNestedProject());
    expect(await runner.run(['move', '--help']), 0);
    expect(
      out.toString(),
      allOf(
        contains('(--under <doc address> | --top)'),
        contains(
          'Move stories and features under a feature, FRs and nfs under a '
          'story, features among the top features, items '
          '(<doc address>#<item ID>) into another doc, or scenarios '
          '(<story address>#S<N>) into another story, and rewrite every '
          'reference to them.',
        ),
        contains('--top'),
      ),
    );
  });

  test('move --help names the three forms of --under', () async {
    final (:runner, :out, :err) = writeRunner(await writeNestedProject());
    expect(await runner.run(['move', '--help']), 0);
    expect(
      out.toString(),
      contains('<doc type>:<name>, a bare name, or a path.'),
    );
  });

  test('move --help names story, FR, and item targets and --target', () async {
    final (:runner, :out, :err) = writeRunner(await writeNestedProject());
    expect(await runner.run(['move', '--help']), 0);
    expect(
      out.toString(),
      allOf(
        contains('<doc address>#<item ID>'),
        contains('[--target <name>]'),
        contains('the doc that takes item targets'),
        contains("Keep names to one code target's docs and the shared docs."),
      ),
    );
  });

  test(
    'move --help names both target types and the parent each takes',
    () async {
      final (:runner, :out, :err) = writeRunner(await writeNestedProject());
      expect(await runner.run(['move', '--help']), 0);
      expect(
        out.toString(),
        allOf(
          contains(
            'Move stories and features under a feature, FRs and nfs under a '
            'story, features among the top features, items '
            '(<doc address>#<item ID>) into another doc, or scenarios '
            '(<story address>#S<N>) into another story, and rewrite every '
            'reference to them.',
          ),
          contains(
            'The feature that takes user_story or feature targets, the story '
            'that takes fr, nf, or scenario targets, or the doc that takes '
            'item targets: ',
          ),
        ),
      );
    },
  );

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
        'specstone move <doc address> … (--under <doc address> | --top) '
        '[--dry-run] [--target <name>] [--json]',
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

  test('move sets a link text equal to the old Name to the '
      'new Name and keeps an item link text', () async {
    final root = await writeNestedProject(
      extra: {
        'docs/notes/links.md':
            '# Links\n\n'
            '[user_story:shop/cart/add_item](../$addItemFolder/USER_STORY.md#acceptance_criteria)\n'
            '[AC-1](../$addItemFolder/USER_STORY.md#acceptance_criteria)\n',
      },
    );
    final (:runner, :out, :err) = writeRunner(root);
    expect(await runner.run(['move', addItem, '--under', 'shop/pay']), 0);
    expect(
      readDoc(root, 'notes/links.md'),
      '# Links\n\n'
      '[user_story:shop/pay/add_item](../$movedFolder/USER_STORY.md#acceptance_criteria)\n'
      '[AC-1](../$movedFolder/USER_STORY.md#acceptance_criteria)\n',
    );
    expect(out.toString(), contains('rewrote notes/links.md\n'));
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
      expect(readDoc(root, payFlutter), contains('add_item:implemented'));
      expect(readDoc(root, payFlutter), contains('draft: true'));
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
  group('fr targets', () {
    const checkStock = 'fr:shop/cart/add_item/check_stock';
    const checkStockFile = '$addItemFolder/fr01_check_stock.md';
    const refundFolder = 'prds/features/f02_shop/f02_pay/us02_refund';
    const movedFile = '$refundFolder/fr02_check_stock.md';
    final extra = {'docs/$refundFolder/fr01_issue_refund.md': '# Issue\n'};

    test(
      'an fr move prints a moved line per file, then its rewritten docs',
      () async {
        final (:runner, :out, :err) = writeRunner(
          await writeNestedProject(extra: extra),
        );
        expect(
          await runner.run(['move', checkStock, '--under', 'shop/pay/refund']),
          0,
        );
        expect(err.toString(), isEmpty);
        expect(
          out.toString(),
          startsWith('moved $checkStockFile to $movedFile\n'),
        );
        expect(out.toString(), contains('rewrote $shopApi\n'));
        expect(
          out.toString().indexOf('rewrote '),
          greaterThan(out.toString().lastIndexOf('moved ')),
        );
      },
    );

    test(
      'an fr move under --json prints moved, rewritten, and mentions',
      () async {
        final (:runner, :out, :err) = writeRunner(
          await writeNestedProject(
            extra: {
              ...extra,
              'app/lib/shop.dart':
                  '/// Checks `shop/cart/add_item/check_stock`.\n',
            },
          ),
        );
        expect(
          await runner.run([
            'move',
            checkStock,
            '--under',
            'shop/pay/refund',
            '--json',
          ]),
          0,
        );
        expect(err.toString(), isEmpty);
        final answer = jsonDecode(out.toString()) as Map;
        expect(answer['moved'], [
          {'from': checkStockFile, 'to': movedFile},
        ]);
        expect(answer['rewritten'], contains(shopApi));
        expect(answer['mentions'], [
          {
            'path': 'app/lib/shop.dart',
            'line': 1,
            'mention': 'shop/cart/add_item/check_stock',
          },
        ]);
      },
    );

    test(
      'a mixed call exits 64 with the message on stderr and nothing moves',
      () async {
        final root = await writeNestedProject(extra: extra);
        final (:runner, :out, :err) = writeRunner(root);
        expect(
          await runner.run([
            'move',
            addItem,
            checkStock,
            '--under',
            'shop/pay/refund',
          ]),
          64,
        );
        expect(out.toString(), isEmpty);
        expect(
          err.toString(),
          'move takes one doc type per call, not user_story and fr\n',
        );
        expect(
          docFile(root, '$addItemFolder/USER_STORY.md').existsSync(),
          isTrue,
        );
        expect(docFile(root, checkStockFile).existsSync(), isTrue);
      },
    );
  });

  group('nf targets', () {
    const cartFolder = 'prds/features/f02_shop/f01_cart';
    const loadFastFile = '$addItemFolder/nf01_load_fast.md';
    const keepLightFile = '$cartFolder/us02_drop_item/nf01_keep_light.md';
    const movedFile = '$cartFolder/us02_drop_item/nf02_load_fast.md';
    late String binary;

    setUpAll(() async {
      binary = await buildSpecstone();
    });

    test(
      'an nf moves under a sibling story and the reply names the file paths',
      () async {
        final root = await writeNestedProject(
          extra: {
            'docs/$loadFastFile': '# Load fast\n',
            'docs/$keepLightFile': '# Keep light\n',
          },
        );
        final result = await Process.run(
          binary,
          [
            'move',
            'nf:shop/cart/add_item/load_fast',
            '--under',
            'shop/cart/drop_item',
          ],
          workingDirectory: root.path,
          environment: {
            'HOME': testHome().path,
            'USERPROFILE': testHome().path,
          },
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(result.stderr, isEmpty);
        expect(
          result.stdout,
          startsWith('moved $loadFastFile to $movedFile\n'),
        );
        expect(docFile(root, movedFile).existsSync(), isTrue);
        expect(docFile(root, loadFastFile).existsSync(), isFalse);
        expect(docFile(root, keepLightFile).existsSync(), isTrue);
      },
    );
  });

  group('feature targets', () {
    const cartFolder = 'prds/features/f02_shop/f01_cart';
    const other = 'prds/features/f03_other';
    late String binary;

    setUpAll(() async {
      binary = await buildSpecstone();
    });

    test('a feature moves under another feature and the reply matches the '
        'feature-target response example', () async {
      final root = await writeNestedProject(
        without: {'docs/$cartDomain', 'docs/$shopApi'},
        extra: {
          'docs/$other/FEATURE.md': '# Other\n',
          'docs/$other/f01_ship/FEATURE.md': '# Ship\n',
          'docs/$other/f02_track/FEATURE.md': '# Track\n',
        },
      );
      docFile(root, shopFeature).writeAsStringSync(
        '\nSee [Cart](f01_cart/FEATURE.md).\n',
        mode: FileMode.append,
      );
      final result = await Process.run(
        binary,
        ['move', 'feature:shop/cart', '--under', 'other'],
        workingDirectory: root.path,
        environment: {'HOME': testHome().path, 'USERPROFILE': testHome().path},
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stderr, isEmpty);
      expect(
        result.stdout,
        'moved $cartFolder/ to $other/f03_cart/\n'
        'rewrote $shopFeature\n',
      );
      expect(
        readDoc(root, shopFeature),
        contains('[Cart](../f03_other/f03_cart/FEATURE.md)'),
      );
      expect(docFile(root, '$other/f03_cart/FEATURE.md').existsSync(), isTrue);
    });
  });

  test('move takes a suffix parent', () async {
    final root = await writeNestedProject();
    final (:runner, :out, :err) = writeRunner(root);
    expect(await runner.run(['move', addItem, '--under', 'pay']), 0);
    expect(err.toString(), isEmpty);
    expect(
      out.toString(),
      startsWith('moved $addItemFolder/ to $movedFolder/\n'),
    );
    expect(docFile(root, '$movedFolder/USER_STORY.md').existsSync(), isTrue);
  });

  group('item targets through the built binary', () {
    late String binary;

    setUpAll(() async {
      binary = await buildSpecstone();
    });

    Future<ProcessResult> move(Directory root, List<String> args) =>
        Process.run(
          binary,
          ['move', ...args],
          workingDirectory: root.path,
          environment: {
            'HOME': testHome().path,
            'USERPROFILE': testHome().path,
          },
        );

    String domain(int count) {
      final rules = [
        for (var n = 1; n <= count; n++) '- **INV-$n** Rule $n holds.',
      ];
      return '# Domain\n\n## Invariants\n\n${rules.join('\n')}\n';
    }

    test('an item move prints moved, renumbered, and rewrote lines', () async {
      final root = await writeNestedProject(
        extra: {'docs/$shopDomain': domain(3), 'docs/$cartDomain': domain(12)},
      );
      final result = await move(root, [
        'domain:shop#INV-3',
        '--under',
        'domain:shop/cart',
      ]);
      expect(result.exitCode, 0);
      expect(result.stderr, isEmpty);
      expect(
        result.stdout,
        'moved $shopDomain#INV-3 to $cartDomain#INV-13\n'
        'renumbered $cartDomain INV-3 to INV-13\n'
        'rewrote $shopDomain\n'
        'rewrote $cartDomain\n',
      );
      expect(readDoc(root, cartDomain), contains('- **INV-13** Rule 3 holds.'));
      expect(readDoc(root, shopDomain), isNot(contains('INV-3')));
    });

    test(
      'an item move with --dry-run prints moves and writes nothing',
      () async {
        final root = await writeNestedProject(
          extra: {
            'docs/$shopDomain': domain(3),
            'docs/$cartDomain': domain(12),
          },
        );
        final shop = readDoc(root, shopDomain);
        final cart = readDoc(root, cartDomain);
        final result = await move(root, [
          'domain:shop#INV-3',
          '--under',
          'domain:shop/cart',
          '--dry-run',
        ]);
        expect(result.exitCode, 0);
        expect(
          result.stdout,
          'moves $shopDomain#INV-3 to $cartDomain#INV-13\n'
          'renumbers $cartDomain INV-3 to INV-13\n'
          'rewrites $shopDomain\n'
          'rewrites $cartDomain\n'
          'dry run: nothing moved\n',
        );
        expect(readDoc(root, shopDomain), shop);
        expect(readDoc(root, cartDomain), cart);
      },
    );

    test(
      "a scenario move prints the scenario-target response example's lines",
      () async {
        String scenario(int n) =>
            '### Scenario $n — [edge] Case $n\n\n'
            '- **Given** a cart in case $n\n- **When** the shopper acts\n'
            '- **Then** the shopper sees case $n';
        String story(String title, int count) =>
            '---\ngoals:\n  - PG-01\n---\n\n# $title\n\n## Use Case\n\n'
            '- **As a** Agent who shops\n- **I want to** act\n'
            '- **so that** I finish an order\n\n## Acceptance Criteria\n\n'
            '${[for (var n = 1; n <= count; n++) scenario(n)].join('\n\n')}\n';
        final root = await writeNestedProject(
          extra: {
            'docs/$cartAdd': story('Agent adds an item', 3),
            'docs/$cartDrop': story('Agent drops an item', 2),
            'docs/$cartAddFr':
                '---\ntraced_from:\n  - S1\n  - S2\nverify_method: test\n'
                '---\n\n# Check stock\n\n'
                '## Statement\nThe system shall check.\n',
          },
        );
        final result = await move(root, [
          '$addItem#S2',
          '--under',
          'user_story:shop/cart/drop_item',
        ]);
        expect(result.exitCode, 0);
        expect(result.stderr, isEmpty);
        expect(
          result.stdout,
          'moved $cartAdd#S2 to $cartDrop#S3\n'
          'renumbered $cartDrop S2 to S3\n'
          'rewrote $cartAdd\n'
          'rewrote $cartAddFr\n'
          'rewrote $cartDrop\n',
        );
        expect(
          readDoc(root, cartAddFr),
          contains('traced_from:\n  - S1\n  - shop/cart/drop_item#S3\n'),
        );
        expect(
          readDoc(root, cartDrop),
          contains('### Scenario 3 — [edge] Case 2\n'),
        );
        expect(readDoc(root, cartAdd), isNot(contains('Case 2')));
      },
    );

    test('a story move given --target is argument_invalid, exit 64', () async {
      final root = await writeNestedProject();
      final result = await move(root, [
        addItem,
        '--under',
        'shop/pay',
        '--target',
        'server',
      ]);
      expect(result.exitCode, 64);
      expect(result.stdout, isEmpty);
      expect(result.stderr, 'move takes --target only with item targets\n');
      expect(
        docFile(root, '$addItemFolder/USER_STORY.md').existsSync(),
        isTrue,
      );
    });

    test('an item move with --target resolves inside that target', () async {
      final root = await writeNestedProject(
        without: {
          'docs/$shopDomain',
          'docs/$cartDomain',
          'docs/$shopArchitecture',
          'docs/$shopApi',
        },
        extra: {
          '.specstone/config.yaml':
              '${shippedPinsConfig()}targets:\n'
              '  app:\n    code_root: app_lib\n'
              '  server:\n    code_root: server_lib\n',
          'app_lib/.keep': '',
          'server_lib/.keep': '',
          for (final target in ['app', 'server']) ...{
            'docs/specs/$target/f02_shop/DOMAIN.md': domain(3),
            'docs/specs/$target/f02_shop/f01_cart/DOMAIN.md': domain(1),
          },
        },
      );
      final named = await move(root, [
        'domain:shop#INV-99',
        '--under',
        'domain:shop/cart',
        '--target',
        'server',
      ]);
      expect(named.exitCode, 64);
      expect(named.stderr, 'specs/server/f02_shop/DOMAIN.md holds no INV-99\n');
      final bare = await move(root, [
        'domain:shop#INV-3',
        '--under',
        'domain:shop/cart',
      ]);
      expect(bare.exitCode, 64);
      expect(
        bare.stderr,
        allOf(
          contains('specs/app/f02_shop/DOMAIN.md'),
          contains('specs/server/f02_shop/DOMAIN.md'),
        ),
      );
    });
  });
}
