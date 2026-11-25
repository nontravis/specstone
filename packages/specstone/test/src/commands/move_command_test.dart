import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/check_fixture.dart'
    show fingerprintFor;
import '../../../../specstone_core/test/helpers/nested_fixture.dart';
import '../../../../specstone_core/test/helpers/record_fixture.dart';
import '../../../../specstone_core/test/helpers/shipped_pins.dart';
import '../../../../specstone_core/test/helpers/write_fixture.dart'
    show docFile, readDoc, testHome, treeBytes;
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
        '[--dry-run [--out [<path>]]] [--target <name>] [--json]',
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

  test('move lays out a doc it rewrites that lacks required sections and '
      'adds none of them', () async {
    const lacking = 'prds/features/f02_shop/f02_pay/us01_card/fr01_note.md';
    final root = await writeNestedProject(
      extra: {
        'docs/$lacking':
            '---\ndraft: true\ntraced_from: S1\nverify_method: test\n---\n\n'
            '# Note\n\n## Statement\n\n\n\n'
            'The system shall add an item. See '
            '[add](../../f01_cart/us01_add_item/USER_STORY.md).\n\n\n',
      },
    );
    List<String> headersOf(String docPath) => RegExp(
      r'^## .*$',
      multiLine: true,
    ).allMatches(readDoc(root, docPath)).map((match) => match[0]!).toList();
    expect(headersOf(lacking), ['## Statement']);
    final (:runner, :out, :err) = writeRunner(root);
    expect(await runner.run(['move', addItem, '--under', 'shop/pay']), 0);
    expect(out.toString(), contains('rewrote $lacking\n'));
    expect(readDoc(root, lacking), isNot(contains('\n\n\n')));
    expect(headersOf(lacking), ['## Statement']);
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
      final result = await runSpecstone(binary, [
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
      final result = await runSpecstone(binary, [
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

    test(
      'move --plan-file takes --target and refuses no doc line for it',
      () async {
        final root = await shopTwins();
        final plan = File('${root.path}/plan.txt')
          ..writeAsStringSync('$addItem -> feature:shop/pay\n');
        final (:runner, :out, :err) = writeRunner(root);
        expect(
          await runner.run([
            'move',
            '--plan-file',
            plan.path,
            '--target',
            'flutter',
          ]),
          0,
          reason: err.toString(),
        );
        expect(out.toString(), startsWith('moved $addItemFolder/ to '));
        expect(readDoc(root, payFlutter), contains('add_item:implemented'));
      },
    );

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
        final result = await runSpecstone(
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
  group('--dry-run --out', () {
    Map<String, List<int>> docBytes(Directory root) => {
      for (final MapEntry(:key, :value) in treeBytes(root).entries)
        if (key.startsWith('docs/')) key: value,
    };

    for (final json in [false, true]) {
      test('move --dry-run${json ? ' --json' : ''} --out saves the dry run '
          'reply and moves no doc', () async {
        final root = await writeNestedProject();
        final before = docBytes(root);
        final call = [
          'move',
          addItem,
          '--under',
          'shop/pay',
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
            matches(RegExp(r'^==> move: \d+ lines, \d+ tokens · ')),
          );
        }
        expect(docBytes(root), before);
      });
    }

    test('--plan-file --dry-run --out saves the dry run reply', () async {
      final root = await writeNestedProject();
      File('${root.path}/plan.txt')
          .writeAsStringSync('$addItem -> feature:shop/pay\n');
      final call = ['move', '--plan-file', 'plan.txt', '--dry-run'];
      final (runner: plain, out: printed, err: _) = writeRunner(root);
      expect(await plain.run(call), 0);

      final (:runner, :out, :err) = writeRunner(root);
      expect(await runner.run([...call, '--out', 'dry.txt']), 0);

      expect(err.toString(), isEmpty);
      expect(
        File('${root.path}/dry.txt').readAsStringSync(),
        printed.toString(),
      );
    });

    test(
      '--plan-out --dry-run --out is argument_conflict and writes no file',
      () async {
        final root = await writeNestedProject();
        final (:runner, :out, :err) = writeRunner(root);

        expect(
          await runner.run([
            'move',
            '--plan-out',
            addItem,
            '--dry-run',
            '--out',
            'dry.txt',
          ]),
          64,
        );

        expect(out.toString(), isEmpty);
        expect(
          err.toString(),
          'move --plan-out takes no --plan-file, --under, --top, or '
          '--dry-run\n',
        );
        expect(File('${root.path}/dry.txt').existsSync(), isFalse);
      },
    );

    test(
      'a plan file that cannot be read exits 64 and writes no file',
      () async {
        final root = await writeNestedProject();
        final (:runner, :out, :err) = writeRunner(root);

        expect(
          await runner.run([
            'move',
            '--plan-file',
            'missing.txt',
            '--dry-run',
            '--out',
            'dry.txt',
          ]),
          64,
        );

        expect(out.toString(), isEmpty);
        expect(err.toString(), 'missing.txt: cannot read the plan file\n');
        expect(File('${root.path}/dry.txt').existsSync(), isFalse);
      },
    );
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
        final result = await runSpecstone(
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
      final result = await runSpecstone(
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
        runSpecstone(
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
        'rulebook:shop#INV-3',
        '--under',
        'rulebook:shop/cart',
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
      expect(readDoc(root, shopDomain), isNot(contains('**INV-3**')));
      expect(readDoc(root, shopDomain), contains('retired_ids:\n  - INV-3\n'));
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
          'rulebook:shop#INV-3',
          '--under',
          'rulebook:shop/cart',
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
          'renumbered $cartAdd S3 to S2\n'
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
        expect(
          readDoc(root, cartAdd),
          contains('### Scenario 2 — [edge] Case 3\n'),
        );
      },
    );

    test('moves an edge case under fr with the record unchanged', () async {
      const dropFr =
          'prds/features/f02_shop/f01_cart/us01_add_item/fr02_drop_stock.md';
      String edgeCase(int n) => '$n. E0$n — Case $n → refused.';
      String contractOf(List<int> edgeCases) =>
          '## Statement\n\n$checkStockStatement\n\n## Edge cases\n\n'
          '${edgeCases.map(edgeCase).join('\n')}\n';
      String fr(List<int> edgeCases) =>
          '---\ntraced_from:\n  - S1\nverify_method: test\n---\n\n'
          '# Requirement\n\n${contractOf(edgeCases)}\n'
          '## Rationale\n\nStock is finite.\n\n'
          '## Verification\n\nTest: a case is refused.\n';
      String row(String item, List<int> edgeCases) =>
          '- add_item/$item: `refuses a case` '
          '${fingerprintFor(contractOf(edgeCases))}';
      final rows = '${row('check_stock', [1, 2])}\n${row('drop_stock', [1])}\n';
      final root = await writeNestedProject(
        extra: {
          '.specstone/config.yaml':
              '${shippedPinsConfig()}verification_coverage: fr\n',
          ...nestedRecords(),
          'docs/$cartAddFr': fr([1, 2]),
          'docs/$dropFr': fr([1]),
          cartRecord:
              '${nestedRecords()[cartRecord]}\n## Verification matrix\n\n$rows',
        },
      );
      final record = readDoc(root, cartRecord);
      final result = await move(root, [
        'fr:shop/cart/add_item/check_stock#E01',
        '--under',
        'fr:shop/cart/add_item/drop_stock',
      ]);
      expect(result.exitCode, 0);
      expect(result.stderr, isEmpty);
      expect(
        result.stdout,
        'moved $cartAddFr#E01 to $dropFr#E02\n'
        'renumbered $dropFr E01 to E02\n'
        'renumbered $cartAddFr E02 to E01\n'
        'rewrote $cartAddFr\n'
        'rewrote $dropFr\n',
      );
      expect(readDoc(root, cartRecord), record);
    });

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
        'rulebook:shop#INV-99',
        '--under',
        'rulebook:shop/cart',
        '--target',
        'server',
      ]);
      expect(named.exitCode, 64);
      expect(named.stderr, 'specs/server/f02_shop/DOMAIN.md holds no INV-99\n');
      final bare = await move(root, [
        'rulebook:shop#INV-3',
        '--under',
        'rulebook:shop/cart',
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

  group('move refusals and no-ops', () {
    const cartFolder = 'prds/features/f02_shop/f01_cart';
    const payFolder = 'prds/features/f02_shop/f02_pay';
    const dropFolder = '$cartFolder/us02_drop_item';
    const refundFolder = '$payFolder/us02_refund';
    const checkStock = 'fr:shop/cart/add_item/check_stock';
    const dropLine = 'fr:shop/cart/drop_item/drop_line';
    const dropLineFile = '$dropFolder/fr01_drop_line.md';
    const dropItem = 'user_story:shop/cart/drop_item';
    const refundHoldsCheckStock = {
      'docs/$refundFolder/fr01_check_stock.md': '# Check stock\n',
    };
    Future<Map<String, Object?>> refusal(
      Directory root,
      List<String> args,
    ) async {
      final (:runner, :out, :err) = writeRunner(root);
      expect(await runner.run(['move', ...args, '--json']), 64);
      expect(out.toString(), isEmpty);
      return (jsonDecode(err.toString()) as Map)['error']
          as Map<String, Object?>;
    }

    Future<void> changesNothing(Directory root, List<String> args) async {
      final (:runner, :out, :err) = writeRunner(root);
      expect(await runner.run(['move', ...args, '--json']), 0);
      expect(err.toString(), isEmpty);
      expect(
        jsonDecode(out.toString()),
        allOf(
          containsPair('moved', isEmpty),
          containsPair('rewritten', isEmpty),
          containsPair('mentions', isEmpty),
        ),
      );
    }

    bool exists(Directory root, String path) =>
        docFile(root, path).existsSync();

    test(
      'a feature already under its parent exits 0 and changes nothing',
      () async {
        final root = await writeNestedProject();
        await changesNothing(root, ['feature:shop/cart', '--under', 'shop']);
        expect(exists(root, cartFeature), isTrue);
      },
    );

    test(
      'an item already in the target doc exits 0 and changes nothing',
      () async {
        final root = await writeNestedProject();
        final before = readDoc(root, shopDomain);
        await changesNothing(root, [
          'rulebook:shop#INV-1',
          '--under',
          'rulebook:shop',
        ]);
        expect(readDoc(root, shopDomain), before);
      },
    );

    test(
      'a story already under its feature exits 0 and changes nothing',
      () async {
        final root = await writeNestedProject();
        await changesNothing(root, [dropItem, '--under', 'shop/cart']);
        expect(exists(root, cartDrop), isTrue);
      },
    );

    test(
      'a story landing on a taken path is refused with exit 64 and stays',
      () async {
        final root = await writeNestedProject(
          extra: {'docs/$payFolder/us03_add_item/note.md': '# Note\n'},
        );
        expect(await refusal(root, [addItem, '--under', 'shop/pay']), {
          'code': 'doc_exists',
          'message': 'a user_story named shop/pay/add_item exists',
          'file': '$payFolder/us03_add_item/',
        });
        expect(exists(root, cartAdd), isTrue);
      },
    );

    test('a story under a feature that holds sub-features exits 64', () async {
      final root = await writeNestedProject();
      expect(await refusal(root, [addItem, '--under', 'shop']), {
        'code': 'argument_invalid',
        'message': 'shop (feature) holds sub-features, so it takes no story',
      });
      expect(exists(root, cartAdd), isTrue);
    });

    test('a story move under a name no feature doc carries exits 64', () async {
      final root = await writeNestedProject();
      for (final under in ['nothing', 'architecture:shop']) {
        final error = await refusal(root, [addItem, '--under', under]);
        expect(error['code'], 'doc_not_found', reason: under);
      }
      expect(exists(root, cartAdd), isTrue);
    });

    test('a story move under a name two feature docs carry exits 64', () async {
      final root = await writeNestedProject(
        extra: {
          'docs/prds/features/f03_account/FEATURE.md': '# Account\n',
          'docs/prds/features/f04_account/FEATURE.md': '# Account\n',
        },
      );
      expect(await refusal(root, [addItem, '--under', 'account']), {
        'code': 'argument_invalid',
        'message':
            'account names 2 feature docs: '
            'prds/features/f03_account/FEATURE.md, '
            'prds/features/f04_account/FEATURE.md',
      });
      expect(exists(root, cartAdd), isTrue);
    });

    test('a story target no doc carries exits 64 and moves nothing', () async {
      final root = await writeNestedProject();
      expect(
        await refusal(root, [
          'user_story:shop/cart/nothing',
          '--under',
          'shop/pay',
        ]),
        {
          'code': 'doc_not_found',
          'message': 'no user_story doc carries the name shop/cart/nothing',
        },
      );
      expect(exists(root, cartAdd), isTrue);
    });

    test(
      'one unknown or other-type target refuses the whole story move',
      () async {
        final root = await writeNestedProject();
        final unknown = await refusal(root, [
          addItem,
          'user_story:shop/cart/nothing',
          '--under',
          'shop/pay',
        ]);
        expect(unknown['code'], 'doc_not_found');
        final otherType = await refusal(root, [
          addItem,
          checkStock,
          '--under',
          'shop/pay',
        ]);
        expect(otherType, {
          'code': 'argument_invalid',
          'message': 'move takes one doc type per call, not user_story and fr',
        });
        expect(exists(root, cartAdd), isTrue);
        expect(exists(root, cartAddFr), isTrue);
      },
    );

    test(
      'two story targets carrying one slug exit 64 naming the first',
      () async {
        final root = await writeNestedProject(
          extra: {
            'docs/prds/features/f03_other/FEATURE.md': '# Other\n',
            'docs/$payFolder/us03_add_item/USER_STORY.md': '# Add item\n',
          },
        );
        expect(
          await refusal(root, [
            'shop/cart/add_item',
            'shop/pay/add_item',
            '--under',
            'other',
          ]),
          {
            'code': 'doc_exists',
            'message': 'a user_story named shop/cart/add_item exists',
            'file': cartAdd,
          },
        );
        expect(exists(root, cartAdd), isTrue);
        expect(exists(root, '$payFolder/us03_add_item/USER_STORY.md'), isTrue);
      },
    );

    test(
      'a refused story move gives the same exit and error under --dry-run',
      () async {
        final root = await writeNestedProject(
          extra: {'docs/$payFolder/us03_drop_item/USER_STORY.md': '# Drop\n'},
        );
        final args = [addItem, dropItem, '--under', 'shop/pay'];
        final applied = await refusal(root, args);
        final dry = await refusal(root, [...args, '--dry-run']);
        expect(dry, applied);
        expect(dry['code'], 'doc_exists');
        expect(exists(root, cartAdd), isTrue);
      },
    );

    test('--top with a scenario target exits 64 and moves nothing', () async {
      final root = await writeNestedProject();
      expect(await refusal(root, ['$addItem#S1', '--top']), {
        'code': 'argument_invalid',
        'message': 'move takes --top only with feature targets',
      });
      expect(exists(root, cartAdd), isTrue);
    });

    test('--under counts only parent-type docs of a story move, but every '
        'typed doc of an item move', () async {
      final root = await writeNestedProject();
      final item = await refusal(root, [
        'rulebook:shop#INV-1',
        '--under',
        'shop/cart',
      ]);
      expect(item, {
        'code': 'argument_invalid',
        'message':
            'shop/cart names 2 docs: feature:shop/cart, rulebook:shop/cart',
      });
      final (:runner, :out, :err) = writeRunner(root);
      expect(
        await runner.run([
          'move',
          'user_story:shop/pay/card',
          '--under',
          'shop/cart',
        ]),
        0,
        reason: err.toString(),
      );
      expect(out.toString(), startsWith('moved $payFolder/us01_card/ to '));
    });

    group('fr targets', () {
      const toRefund = ['--under', 'shop/pay/refund'];

      test(
        'an fr move under a name no user_story doc carries exits 64',
        () async {
          final root = await writeNestedProject();
          for (final under in ['nothing', 'shop/pay']) {
            final error = await refusal(root, [checkStock, '--under', under]);
            expect(error['code'], 'doc_not_found', reason: under);
          }
          expect(exists(root, cartAddFr), isTrue);
        },
      );

      test(
        'an fr move under a name two user_story docs carry exits 64',
        () async {
          final root = await writeNestedProject(
            extra: {'docs/$payFolder/us05_refund/USER_STORY.md': '# Refund\n'},
          );
          expect(await refusal(root, [checkStock, '--under', 'pay/refund']), {
            'code': 'argument_invalid',
            'message':
                'pay/refund names 2 user_story docs: '
                '$refundFolder/USER_STORY.md, '
                '$payFolder/us05_refund/USER_STORY.md',
          });
          expect(exists(root, cartAddFr), isTrue);
        },
      );

      test(
        'an fr beside an architecture doc or an nf is refused with exit 64',
        () async {
          final root = await writeNestedProject(
            extra: {
              'docs/$cartFolder/us01_add_item/nf01_load_fast.md': '# L\n',
            },
          );
          expect(
            await refusal(root, [checkStock, 'architecture:shop', ...toRefund]),
            containsPair('code', 'doc_type_not_movable'),
          );
          expect(
            await refusal(root, [
              checkStock,
              'nf:shop/cart/add_item/load_fast',
              ...toRefund,
            ]),
            {
              'code': 'argument_invalid',
              'message': 'move takes one doc type per call, not fr and nf',
            },
          );
          expect(exists(root, cartAddFr), isTrue);
        },
      );

      test(
        'an fr whose slug the target story holds is doc_exists, exit 64',
        () async {
          final root = await writeNestedProject(extra: refundHoldsCheckStock);
          expect(await refusal(root, [checkStock, ...toRefund]), {
            'code': 'doc_exists',
            'message': 'a fr named shop/pay/refund/check_stock exists',
            'file': '$refundFolder/fr01_check_stock.md',
          });
          expect(exists(root, cartAddFr), isTrue);
        },
      );

      test(
        'two fr targets sharing one slug exit 64 and both files stay',
        () async {
          final root = await writeNestedProject(
            extra: {'docs/$dropFolder/fr01_check_stock.md': '# Check stock\n'},
          );
          expect(
            await refusal(root, [
              checkStock,
              'fr:shop/cart/drop_item/check_stock',
              ...toRefund,
            ]),
            {
              'code': 'doc_exists',
              'message': 'a fr named shop/cart/add_item/check_stock exists',
              'file': cartAddFr,
            },
          );
          expect(exists(root, cartAddFr), isTrue);
          expect(exists(root, '$dropFolder/fr01_check_stock.md'), isTrue);
        },
      );

      test('an fr landing on a taken path is doc_exists, exit 64', () async {
        const landing = '$refundFolder/fr02_check_stock.md';
        final root = await writeNestedProject(
          extra: {
            'docs/$refundFolder/fr01_issue_refund.md': '# Issue\n',
            'docs/$landing/keep.md': '# Keep\n',
          },
        );
        final error = await refusal(root, [checkStock, ...toRefund]);
        expect(error['code'], 'doc_exists');
        expect(error['file'], landing);
        expect(exists(root, cartAddFr), isTrue);
      });

      test(
        'an fr already under the story exits 0 and changes nothing',
        () async {
          final root = await writeNestedProject();
          await changesNothing(root, [
            checkStock,
            '--under',
            'shop/cart/add_item',
          ]);
          expect(exists(root, cartAddFr), isTrue);
        },
      );

      test(
        'an unknown or slug-clashing fr target refuses the whole call',
        () async {
          final root = await writeNestedProject(
            extra: {
              'docs/$dropLineFile': '# Drop line\n',
              ...refundHoldsCheckStock,
            },
          );
          final unknown = await refusal(root, [
            dropLine,
            'fr:shop/cart/add_item/nothing',
            ...toRefund,
          ]);
          expect(unknown['code'], 'doc_not_found');
          final clash = await refusal(root, [
            dropLine,
            checkStock,
            ...toRefund,
          ]);
          expect(clash['code'], 'doc_exists');
          expect(exists(root, dropLineFile), isTrue);
          expect(exists(root, cartAddFr), isTrue);
        },
      );

      test(
        'an fr move with both parent flags, neither, or --top exits 64',
        () async {
          final root = await writeNestedProject();
          expect(await refusal(root, [checkStock, ...toRefund, '--top']), {
            'code': 'argument_conflict',
            'message': 'move takes --under or --top, not both',
          });
          expect(await refusal(root, [checkStock]), {
            'code': 'argument_missing',
            'message': 'move needs --under <doc address> or --top',
          });
          expect(await refusal(root, [checkStock, '--top']), {
            'code': 'argument_invalid',
            'message': 'move takes --top only with feature targets',
          });
          expect(exists(root, cartAddFr), isTrue);
        },
      );

      test('an fr target no doc carries exits 64 and moves nothing', () async {
        final root = await writeNestedProject();
        expect(
          await refusal(root, ['fr:shop/cart/add_item/nothing', ...toRefund]),
          {
            'code': 'doc_not_found',
            'message': 'no fr doc carries the name shop/cart/add_item/nothing',
          },
        );
        expect(exists(root, cartAddFr), isTrue);
      });

      test(
        'a refused fr move gives the same exit and error under --dry-run',
        () async {
          final root = await writeNestedProject(extra: refundHoldsCheckStock);
          final applied = await refusal(root, [checkStock, ...toRefund]);
          final dry = await refusal(root, [
            checkStock,
            ...toRefund,
            '--dry-run',
          ]);
          expect(dry, applied);
          expect(dry['code'], 'doc_exists');
          expect(exists(root, cartAddFr), isTrue);
        },
      );
    });
  });

  group('--plan-file through the built binary', () {
    late String binary;

    setUpAll(() async {
      binary = await buildSpecstone();
    });

    Future<ProcessResult> move(Directory root, List<String> args) =>
        runSpecstone(
          binary,
          ['move', ...args],
          workingDirectory: root.path,
          environment: {
            'HOME': testHome().path,
            'USERPROFILE': testHome().path,
          },
        );

    File planIn(Directory root) =>
        File('${root.path}/plan.txt')
          ..writeAsStringSync('$addItem -> feature:shop/pay\n');

    test('move --plan-file applies a plan file', () async {
      final root = await writeNestedProject();
      final plan = planIn(root);
      final result = await move(root, ['--plan-file', plan.path]);
      expect(result.stderr, isEmpty);
      expect(result.exitCode, 0);
      expect(
        result.stdout,
        startsWith('moved $addItemFolder/ to $movedFolder/\n'),
      );
      expect(docFile(root, '$movedFolder/USER_STORY.md').existsSync(), isTrue);
    });

    test('move --plan-file beside a target is argument_conflict', () async {
      final root = await writeNestedProject();
      final plan = planIn(root);
      for (final beside in [
        [addItem],
        ['--under', 'shop/pay'],
        ['--top'],
      ]) {
        final result = await move(root, ['--plan-file', plan.path, ...beside]);
        expect(result.exitCode, 64, reason: '$beside');
        expect(result.stdout, isEmpty);
        expect(result.stderr, 'move takes --plan-file or targets, not both\n');
      }
      expect(
        docFile(root, '$addItemFolder/USER_STORY.md').existsSync(),
        isTrue,
      );
    });

    test('a bad plan line names the plan path as typed and its line', () async {
      final root = await writeNestedProject();
      File('${root.path}/plan.txt').writeAsStringSync('nonsense\n');
      final result = await move(root, ['--plan-file', 'plan.txt']);
      expect(result.exitCode, 64);
      expect(result.stdout, isEmpty);
      expect(result.stderr, startsWith('plan.txt:1: '));
    });

    for (final (name, bytes) in [
      ('missing', null),
      ('not UTF-8', [0xff, 0xfe, 0x00]),
    ]) {
      test(
        'a plan file $name is argument_invalid naming its path as typed',
        () async {
          final root = await writeNestedProject();
          if (bytes != null) {
            File('${root.path}/plan.txt').writeAsBytesSync(bytes);
          }
          final result = await move(root, ['--plan-file', 'plan.txt']);
          expect(result.exitCode, 64);
          expect(result.stdout, isEmpty);
          expect(result.stderr, 'plan.txt: cannot read the plan file\n');
        },
      );
    }

    test('move --plan-file takes no target and needs none', () async {
      final root = await writeNestedProject();
      final plan = planIn(root);
      final result = await move(root, [
        '--plan-file',
        plan.path,
        '--dry-run',
        '--json',
      ]);
      expect(result.stderr, isEmpty);
      expect(result.exitCode, 0);
      final answer = jsonDecode(result.stdout as String) as Map;
      expect(answer['dryRun'], isTrue);
      expect(answer, contains('warnings'));
      expect(answer['created'], isEmpty);
      expect(answer['moved'], [
        {'from': '$addItemFolder/', 'to': '$movedFolder/'},
      ]);
      expect(
        docFile(root, '$addItemFolder/USER_STORY.md').existsSync(),
        isTrue,
      );
    });
  });

  group('--plan-out through the built binary', () {
    late String binary;

    setUpAll(() async {
      binary = await buildSpecstone();
    });

    Future<ProcessResult> move(Directory root, List<String> args) =>
        runSpecstone(
          binary,
          ['move', ...args],
          workingDirectory: root.path,
          environment: {
            'HOME': testHome().path,
            'USERPROFILE': testHome().path,
          },
        );

    test('move --plan-out beside --plan-file is argument_conflict', () async {
      final root = await writeNestedProject();
      File('${root.path}/plan.txt').writeAsStringSync('$addItem keep\n');
      for (final beside in [
        ['--plan-file', 'plan.txt'],
        ['--under', 'shop/pay'],
        ['--top'],
        ['--dry-run'],
      ]) {
        final result = await move(root, ['--plan-out', addItem, ...beside]);
        expect(result.exitCode, 64, reason: '$beside');
        expect(result.stdout, isEmpty);
        expect(
          result.stderr,
          'move --plan-out takes no --plan-file, --under, --top, or '
          '--dry-run\n',
        );
      }
    });

    test('move --plan-out --out saves the skeleton', () async {
      final root = await writeNestedProject();
      final printed = await move(root, ['--plan-out', addItem]);
      expect(printed.stderr, isEmpty);
      expect(printed.exitCode, 0);
      expect(printed.stdout, startsWith('source $addItem '));
      expect(printed.stdout, contains('$addItem#S1 keep\n'));

      final saved = await move(root, [
        '--plan-out',
        addItem,
        '--out',
        'plan.txt',
      ]);
      expect(saved.stderr, isEmpty);
      expect(saved.exitCode, 0);
      expect(File('${root.path}/plan.txt').readAsStringSync(), printed.stdout);
      expect(
        saved.stdout,
        matches(RegExp(r'^==> move: \d+ lines, \d+ tokens · ')),
      );

      final bare = await move(root, ['--plan-out', addItem, '--out']);
      expect(bare.exitCode, 0);
      final file = File(
        '${root.path}/.specstone/reports/'
        'move-plan-out.user_story-shop-cart-add_item.txt',
      );
      expect(file.readAsStringSync(), printed.stdout);
    });

    test('a saved skeleton applies as a plan that changes nothing', () async {
      final root = await writeNestedProject();
      final printed = await move(root, ['--plan-out', 'feature:shop/cart']);
      File('${root.path}/plan.txt').writeAsStringSync(printed.stdout as String);
      final applied = await move(root, ['--plan-file', 'plan.txt', '--json']);
      expect(applied.stderr, isEmpty);
      expect(applied.exitCode, 0);
      final answer = jsonDecode(applied.stdout as String) as Map;
      expect(answer['moved'], isEmpty);
    });

    test(
      'move --plan-out refuses a name no doc carries and one of 2 docs',
      () async {
        final root = await writeNestedProject();
        final none = await move(root, ['--plan-out', 'nothing_here']);
        expect(none.exitCode, 64);
        expect(none.stdout, isEmpty);
        expect(none.stderr, 'no doc carries the name nothing_here\n');
        final many = await move(root, ['--plan-out', 'shop']);
        expect(many.exitCode, 64);
        expect(many.stdout, isEmpty);
        expect(many.stderr, contains('shop names '));
      },
    );

    test('move --plan-out --json prints the plan in a JSON object', () async {
      final root = await writeNestedProject();
      final printed = await move(root, ['--plan-out', addItem]);
      final result = await move(root, ['--plan-out', addItem, '--json']);
      expect(result.stderr, isEmpty);
      expect(result.exitCode, 0);
      expect(jsonDecode(result.stdout as String), {
        'plan': printed.stdout,
        'warnings': <Object?>[],
      });
    });

    test(
      'move --out without --plan-out or --dry-run is argument_invalid',
      () async {
        final root = await writeNestedProject();
        final result = await move(root, [
          addItem,
          '--under',
          'shop/pay',
          '--out',
          'plan.txt',
        ]);
        expect(result.exitCode, 64);
        expect(result.stdout, isEmpty);
        expect(result.stderr, '--out goes with --plan-out or --dry-run\n');
        expect(File('${root.path}/plan.txt').existsSync(), isFalse);
      },
    );
  });
}
