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

  test('move takes a bare name one doc carries', () async {
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

  test('move prints the moved line and the rewrote lines', () async {
    final (:runner, :out, :err) = writeRunner(await writeNestedProject());
    expect(await runner.run(['move', addItem, '--under', 'shop/pay']), 0);
    expect(err.toString(), isEmpty);
    expect(
      out.toString(),
      startsWith('moved $addItemFolder/ to $movedFolder/\n'),
    );
    expect(out.toString(), contains('rewrote $shopApi\n'));
  });

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

  test('an --under with a #section suffix is argument_invalid, exit 64, and '
      'moves nothing', () async {
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

  test('no target is argument_missing, exit 64', () async {
    final (:runner, :out, :err) = writeRunner(await writeNestedProject());
    expect(await runner.run(['move', '--under', 'shop/pay']), 64);
    expect(err.toString(), startsWith('move needs a target'));
  });

  test(
    'one story that cannot move refuses the call, and nothing moves',
    () async {
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
    },
  );

  test('move --help names the several-story form', () async {
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

  test('no target outside a project is argument_missing, exit 64', () async {
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
  });

  test('move writes a rewritten typed doc laid out', () async {
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

  group('longer code spans', () {
    const note = 'docs/notes/ideas.md';
    const span = 'shop/cart/add_item E05';
    const text = '# Ideas\n\nA span `$span`.\n';
    late String binary;
    setUpAll(() async {
      binary = await buildSpecstone();
    });

    test('a story move prints the mentions line of a longer span after its '
        'rewrote lines', () async {
      final root = await writeNestedProject(extra: {note: text});
      final result = await Process.run(binary, [
        'move',
        addItem,
        '--under',
        'shop/pay',
      ], workingDirectory: root.path);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final lines = (result.stdout as String).split('\n');
      expect(lines.last, isEmpty);
      expect(lines[lines.length - 2], 'mentions $note:3 $span');
      expect(
        lines.lastIndexWhere((l) => l.startsWith('rewrote ')),
        lessThan(lines.indexWhere((l) => l.startsWith('mentions '))),
      );
      expect(File('${root.path}/$note').readAsStringSync(), text);
    });

    test("a dry run prints the longer span's mentions line before its "
        'closing line', () async {
      final root = await writeNestedProject(extra: {note: text});
      final result = await Process.run(binary, [
        'move',
        addItem,
        '--under',
        'shop/pay',
        '--dry-run',
      ], workingDirectory: root.path);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        result.stdout,
        endsWith('mentions $note:3 $span\ndry run: nothing moved\n'),
      );
      expect(File('${root.path}/$note').readAsStringSync(), text);
    });
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

    test('move carries the entries of each target, rewriting the old '
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

    test('a story move carries the matrix rows of its FRs to the record it '
        'creates', () async {
      const row = '- add_item/check_stock E01: `refuses an item out of stock`';
      const kept = '- drop_item/drop_line E01: `drops a line`';
      const matrix = '\n## Verification matrix\n\n';
      final cart = recordText(
        statuses: ['add_item:implemented', 'drop_item:planned'],
      );
      final root = await writeNestedProject(
        extra: {
          '.specstone/config.yaml': twinConfig(),
          '.specstone/templates/implementation.yaml': recordLayer,
          'docs/$cartFlutter': '$cart$matrix$row\n$kept\n',
        },
      );
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run(['move', addItem, '--under', 'shop/pay']),
        0,
        reason: err.toString(),
      );
      expect(readDoc(root, payFlutter), endsWith('$matrix$row\n'));
      expect(readDoc(root, cartFlutter), endsWith('$matrix$kept\n'));
    });
  });

  group('--dry-run', () {
    const code =
        '// Adds `user_story:shop/cart/add_item#acceptance_criteria`.\n';

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

    test('an fr move carries the matrix rows of the FR to the record of the '
        'feature it lands in', () async {
      const cartRecord = 'specs/f02_shop/f01_cart/IMPLEMENTATION.md';
      const payRecord = 'specs/f02_shop/f02_pay/IMPLEMENTATION.md';
      const matrix = '\n## Verification matrix\n\n';
      final root = await writeNestedProject(
        extra: {
          ...extra,
          '.specstone/config.yaml': oneTargetConfig(),
          '.specstone/templates/implementation.yaml': recordLayer,
          'docs/$cartRecord':
              '${recordText(statuses: ['add_item/check_stock:implemented'])}'
              '$matrix- add_item/check_stock E01: `refuses an item out of '
              'stock` 5d1e0c4b7a92\n',
        },
      );
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run(['move', checkStock, '--under', 'shop/pay/refund']),
        0,
        reason: err.toString(),
      );
      expect(
        readDoc(root, payRecord),
        endsWith(
          '$matrix- refund/check_stock E01: `refuses an item out of stock` '
          '5d1e0c4b7a92\n',
        ),
      );
      expect(readDoc(root, cartRecord), isNot(contains('check_stock')));
    });

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
