import 'dart:convert';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/nested_fixture.dart';
import '../../../../specstone_core/test/helpers/write_fixture.dart'
    show docFile, readDoc;
import '../../helpers/write_runner.dart';

void main() {
  const addItemFolder = 'prds/features/f02_shop/f01_cart/us01_add_item';
  const movedFolder = 'prds/features/f02_shop/f02_pay/us03_add_item';
  const addItem = 'user_story:shop/cart/add_item';

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

  test('f02/us07/fr01: move --json prints moved and rewritten', () async {
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

  test('f02/us07/fr01/e04: a story moved under its own feature prints nothing, exit 0', () async {
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

  test('f02/us07/fr01/e05: a feature that holds features is argument_invalid, exit 64', () async {
    final (:runner, :out, :err) = writeRunner(await writeNestedProject());
    expect(await runner.run(['move', addItem, '--under', 'shop']), 64);
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      'shop (feature) holds sub-features, so it takes no story\n',
    );
  });

  test(
    'f02/us07/fr01/e06: another doc type is doc_type_not_movable, exit 64',
    () async {
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
    },
  );

  test('f02/us07/fr01/e07: no --under is argument_missing, exit 64', () async {
    final (:runner, :out, :err) = writeRunner(await writeNestedProject());
    expect(await runner.run(['move', addItem]), 64);
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      'move needs a feature, such as specstone move '
      'user_story:login/reset_password --under account\n',
    );
  });

  test(
    'f02/us07/fr01/e08: an --under nothing carries is doc_not_found, exit 64',
    () async {
      final (:runner, :out, :err) = writeRunner(await writeNestedProject());
      expect(await runner.run(['move', addItem, '--under', 'nothing']), 64);
      expect(out.toString(), isEmpty);
      expect(err.toString(), 'no feature doc carries the name nothing\n');
    },
  );

  test('f02/us07/fr01/e09: no target is argument_missing, exit 64', () async {
    final (:runner, :out, :err) = writeRunner(await writeNestedProject());
    expect(await runner.run(['move', '--under', 'shop/pay']), 64);
    expect(err.toString(), startsWith('move needs a target'));
  });

  test(
    'f02/us07/fr01/e09: two positionals print the usage line, exit 64',
    () async {
      final (:runner, :out, :err) = writeRunner(await writeNestedProject());
      expect(await runner.run(['move', 'a', 'b', '--under', 'x']), 64);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        contains(
          'Expected one target, got 2.\n\n'
          'Usage: specstone move <doc address> --under <doc address> '
          '[--json]\n',
        ),
      );
    },
  );

  test('document_writing/move_story/move_story_folder E11: move writes a rewritten typed doc laid out', () async {
    final root = await writeNestedProject();
    final file = docFile(root, shopApi);
    file.writeAsStringSync('${file.readAsStringSync()}\n\n\n');
    final (:runner, :out, :err) = writeRunner(root);
    expect(await runner.run(['move', addItem, '--under', 'shop/pay']), 0);
    expect(err.toString(), isEmpty);
    expect(readDoc(root, shopApi), isNot(contains('\n\n\n')));
  });
}
