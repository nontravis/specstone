// Each test name states one behavior on one line.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/document_writing/move_plan.dart';
import 'package:specstone_core/src/document_writing/move_plan_engine.dart'
    show sourceHashOf;
import 'package:specstone_core/src/document_writing/move_plan_judge.dart';
import 'package:specstone_core/src/document_writing/plan_skeleton.dart';
import 'package:test/test.dart';

import '../../helpers/nested_fixture.dart';
import '../../helpers/write_fixture.dart';

const _shopApiText =
    '# Shop API\n\n## FR trace\n| FR | Operation |\n|----|-----------|\n'
    '| cart/add_item/check_stock | `addItem` |\n\n'
    '## Operations\n### `addItem`\nAdds an item.\n\n'
    '### `dropItem`\nDrops an item.\n';

const _shopDomainText =
    '# Shop domain\n\n## Entities\n| Entity | Kind | Identity | Owns | Notes |\n'
    '|--------|------|----------|------|-------|\n'
    '| Order | Aggregate root | id | lines | — |\n\n'
    '## Invariants\n- **INV-1** An order holds a line.\n'
    '- **INV-2** An order has an owner.\n';

String _hashOf(Directory root, String docPath) =>
    sourceHashOf(docFile(root, docPath).readAsBytesSync());

Future<Directory> _project() => writeNestedProject(
  extra: {'docs/$shopDomain': _shopDomainText, 'docs/$shopApi': _shopApiText},
);

String _skeleton(Directory root, List<String> addresses) =>
    writeIn(root, (session) => planSkeletonOf(session, addresses));

void main() {
  test('skeleton lists a source line and keep lines in doc order', () async {
    final root = await _project();
    expect(
      _skeleton(root, ['rulebook:shop']),
      'source rulebook:shop ${_hashOf(root, shopDomain)}\n'
      'rulebook:shop#entities/Order keep\n'
      'rulebook:shop#INV-1 keep\n'
      'rulebook:shop#INV-2 keep\n',
    );
    expect(
      _skeleton(root, ['api:shop', 'user_story:shop/cart/add_item']),
      'source api:shop ${_hashOf(root, shopApi)}\n'
      'api:shop#fr_trace/cart/add_item/check_stock keep\n'
      'api:shop#operations/additem keep\n'
      'api:shop#operations/dropitem keep\n'
      'source user_story:shop/cart/add_item ${_hashOf(root, cartAdd)}\n'
      'user_story:shop/cart/add_item#S1 keep\n'
      'fr:shop/cart/add_item/check_stock keep\n',
    );
  });

  test(
    'feature skeleton lists its stories and sub-features as keep lines',
    () async {
      final root = await _project();
      expect(
        _skeleton(root, ['feature:shop/cart']),
        'source feature:shop/cart ${_hashOf(root, cartFeature)}\n'
        'user_story:shop/cart/add_item keep\n'
        'user_story:shop/cart/drop_item keep\n',
      );
      expect(
        _skeleton(root, ['feature:shop']),
        'source feature:shop ${_hashOf(root, shopFeature)}\n'
        'feature:shop/cart keep\n'
        'feature:shop/pay keep\n',
      );
    },
  );

  test('skeleton parses back as a plan that changes nothing', () async {
    final root = await _project();
    writeIn(root, (session) {
      final text = planSkeletonOf(session, [
        'rulebook:shop',
        'api:shop',
        'user_story:shop/cart/add_item',
        'feature:shop',
      ]);
      final plan = parseMovePlan(text, path: 'plan.txt');
      expect(plan.lines.whereType<SourceLine>(), hasLength(4));
      final work = judgeMovePlan(session, plan);
      expect(work.creates, isEmpty);
      expect(work.groups, isEmpty);
      expect(work.landings, isEmpty);
      expect(work.keyed, isEmpty);
      expect(work.renumberings, isEmpty);
      return null;
    });
  });

  test(
    'skeleton notes a row whose key holds a space in a comment line',
    () async {
      final root = await writeNestedProject(
        extra: {
          'docs/$shopDomain':
              '# Shop domain\n\n## Entities\n| Entity | Kind |\n|---|---|\n'
              '| Order line | Entity |\n| Cart | Entity |\n',
        },
      );
      final text = _skeleton(root, ['rulebook:shop']);
      expect(
        text,
        'source rulebook:shop ${_hashOf(root, shopDomain)}\n'
        '# rulebook:shop#entities/Order line names no plan line\n'
        'rulebook:shop#entities/Cart keep\n',
      );
      expect(parseMovePlan(text, path: 'plan.txt').lines, hasLength(2));
    },
  );

  test('skeleton leaves a nested item to its parent keep line', () async {
    final root = await writeNestedProject(
      extra: {
        'docs/$shopDomain':
            '# Shop domain\n\n## Invariants\n- **INV-1** An order holds a line.\n'
            '  - **INV-2** A line has a price.\n'
            '- **INV-3** An order has an owner.\n',
      },
    );
    expect(
      _skeleton(root, ['rulebook:shop']),
      'source rulebook:shop ${_hashOf(root, shopDomain)}\n'
      'rulebook:shop#INV-1 keep\n'
      'rulebook:shop#INV-3 keep\n',
    );
  });

  test('skeleton prints one keep line for rows sharing a key', () async {
    final root = await writeNestedProject(
      extra: {
        'docs/$shopDomain':
            '# Shop domain\n\n## Entities\n| Entity | Kind |\n|---|---|\n'
            '| Cart | Entity |\n| Cart | Value |\n',
      },
    );
    expect(
      _skeleton(root, ['rulebook:shop']),
      'source rulebook:shop ${_hashOf(root, shopDomain)}\n'
      'rulebook:shop#entities/Cart keep\n',
    );
  });
}
