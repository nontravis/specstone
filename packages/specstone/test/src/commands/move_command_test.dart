import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/nested_fixture.dart';
import '../../../../specstone_core/test/helpers/record_fixture.dart';
import '../../../../specstone_core/test/helpers/write_fixture.dart'
    show docFile, readDoc, testHome, treeBytes;
import '../../helpers/built_cli.dart';
import '../../helpers/write_runner.dart';

void main() {
  const addItemFolder = 'prds/features/f02_shop/f01_cart/us01_add_item';
  const movedFolder = 'prds/features/f02_shop/f02_pay/us03_add_item';
  const addItem = 'user_story:shop/cart/add_item';

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
    const refundFolder = 'prds/features/f02_shop/f02_pay/us02_refund';
    for (final (extra, target, under, from, to, mentions) in [
      (
        <String, String>{},
        addItem,
        'shop/pay',
        '$addItemFolder/',
        '$movedFolder/',
        null,
      ),
      (
        {
          'docs/$refundFolder/fr01_issue_refund.md': '# Issue\n',
          'app/lib/shop.dart': '/// Checks `shop/cart/add_item/check_stock`.\n',
        },
        'fr:shop/cart/add_item/check_stock',
        'shop/pay/refund',
        '$addItemFolder/fr01_check_stock.md',
        '$refundFolder/fr02_check_stock.md',
        [
          {
            'path': 'app/lib/shop.dart',
            'line': 1,
            'mention': 'shop/cart/add_item/check_stock',
          },
        ],
      ),
    ]) {
      final (:runner, :out, :err) = writeRunner(
        await writeNestedProject(extra: extra),
      );
      expect(
        await runner.run(['move', target, '--under', under, '--json']),
        0,
        reason: target,
      );
      expect(err.toString(), isEmpty, reason: target);
      final answer = jsonDecode(out.toString()) as Map;
      expect(answer['moved'], [
        {'from': from, 'to': to},
      ], reason: target);
      expect(answer['rewritten'], contains(shopApi), reason: target);
      if (mentions != null) expect(answer['mentions'], mentions);
    }
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
      allOf([
        contains('(--under <doc address> | --top)'),
        contains(
          'Move stories and features under a feature, FRs and nfs under a '
          'story, features among the top features, items '
          '(<doc address>#<item ID>) into another doc, or scenarios '
          '(<story address>#S<N>) into another story, and rewrite every '
          'reference to them.',
        ),
        contains('--top'),
        contains('<doc type>:<name>, a bare name, or a path.'),
        contains('<doc address>#<item ID>'),
        contains('[--target <name>]'),
        contains('the doc that takes item targets'),
        contains("Keep names to one code target's docs and the shared docs."),
        contains(
          'The feature that takes user_story or feature targets, the story '
          'that takes fr, nf, or scenario targets, or the doc that takes '
          'item targets: ',
        ),
        contains(
          'specstone move <doc address> … (--under <doc address> | --top) '
          '[--dry-run [--out [<path>]]] [--target <name>] [--json]',
        ),
      ]),
    );
  });

  test('no target is argument_missing, exit 64', () async {
    final (:runner, :out, :err) = writeRunner(await writeNestedProject());
    expect(await runner.run(['move', '--under', 'shop/pay']), 64);
    expect(err.toString(), startsWith('move needs a target'));

    final outside = Directory.systemTemp.createTempSync('specstone_move_');
    addTearDown(() => outside.deleteSync(recursive: true));
    final bare = writeRunner(outside);
    expect(await bare.runner.run(['move', '--under', 'shop/pay']), 64);
    expect(bare.out.toString(), isEmpty);
    expect(
      bare.err.toString(),
      'move needs a target, such as specstone move '
      'user_story:login/reset_password --under account\n',
    );
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
        File('${root.path}/plan.txt')
            .writeAsStringSync('$addItem -> feature:shop/pay\n');
        final before = docBytes(root);
        for (final call in [
          ['move', addItem, '--under', 'shop/pay', '--dry-run'],
          ['move', '--plan-file', 'plan.txt', '--dry-run'],
        ]) {
          final withJson = [...call, if (json) '--json'];
          final (runner: plain, out: printed, err: _) = writeRunner(root);
          expect(await plain.run(withJson), 0);

          final (:runner, :out, :err) = writeRunner(root);
          expect(await runner.run([...withJson, '--out', 'dry.txt']), 0);

          expect(err.toString(), isEmpty);
          expect(
            File('${root.path}/dry.txt').readAsStringSync(),
            printed.toString(),
          );
          if (json) {
            expect(
              jsonDecode(out.toString()),
              containsPair('lines', isA<int>()),
            );
          } else {
            expect(
              out.toString(),
              matches(RegExp(r'^==> move: \d+ lines, \d+ tokens · ')),
            );
          }
          expect(docBytes(root), before);
        }
      });
    }
  });
  group('move refusals and no-ops', () {
    const payFolder = 'prds/features/f02_shop/f02_pay';
    const refundFolder = '$payFolder/us02_refund';
    const checkStock = 'fr:shop/cart/add_item/check_stock';
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

    bool exists(Directory root, String path) =>
        docFile(root, path).existsSync();

    test(
      'a refused story move gives the same exit and error under --dry-run',
      () async {
        for (final (extra, args, kept) in [
          (
            {'docs/$payFolder/us03_drop_item/USER_STORY.md': '# Drop\n'},
            [addItem, dropItem, '--under', 'shop/pay'],
            cartAdd,
          ),
          (
            refundHoldsCheckStock,
            [checkStock, '--under', 'shop/pay/refund'],
            cartAddFr,
          ),
        ]) {
          final root = await writeNestedProject(extra: extra);
          final applied = await refusal(root, args);
          final dry = await refusal(root, [...args, '--dry-run']);
          expect(dry, applied, reason: '$args');
          expect(dry['code'], 'doc_exists', reason: '$args');
          expect(exists(root, kept), isTrue, reason: '$args');
        }
      },
    );
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

    for (final (name, bytes, flags) in [
      ('missing', null, <String>[]),
      ('not UTF-8', [0xff, 0xfe, 0x00], <String>[]),
      (
        'missing under --dry-run --out',
        null,
        ['--dry-run', '--out', 'dry.txt'],
      ),
    ]) {
      test(
        'a plan file $name is argument_invalid naming its path as typed',
        () async {
          final root = await writeNestedProject();
          if (bytes != null) {
            File('${root.path}/plan.txt').writeAsBytesSync(bytes);
          }
          final result = await move(root, [
            '--plan-file',
            'plan.txt',
            ...flags,
          ]);
          expect(result.exitCode, 64);
          expect(result.stdout, isEmpty);
          expect(result.stderr, 'plan.txt: cannot read the plan file\n');
          expect(File('${root.path}/dry.txt').existsSync(), isFalse);
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
        ['--dry-run', '--out', 'dry.txt'],
      ]) {
        final result = await move(root, ['--plan-out', addItem, ...beside]);
        expect(result.exitCode, 64, reason: '$beside');
        expect(result.stdout, isEmpty);
        expect(
          result.stderr,
          'move --plan-out takes no --plan-file, --under, --top, or '
          '--dry-run\n',
        );
        expect(File('${root.path}/dry.txt').existsSync(), isFalse);
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
