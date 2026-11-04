// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/document_writing/new_doc.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/nested_fixture.dart';
import '../../helpers/write_fixture.dart';

/// The folder of the sub-feature `shop/cart/a/b/c`, depth 4 below `shop`.
const _deepFolder = 'prds/features/f02_shop/f01_cart/f01_a/f01_b/f01_c';

/// The `FEATURE.md` of that sub-feature, one level past `max_depth: 3`.
const _deepFeature = '$_deepFolder/FEATURE.md';

/// The story under it.
const _deepStory = '$_deepFolder/us01_x/USER_STORY.md';

/// Returns the JSON of each finding of [kind].
List<Map<String, Object>> _jsonOf(CheckReport report, FindingKind kind) => [
  for (final f in report.findings)
    if (kind == f.kind) f.toJson(),
];

/// Returns the paths of the findings under [folder].
List<String> _under(CheckReport report, String folder) => [
  for (final f in report.findings)
    if (f.path.startsWith(folder)) '${f.path}: ${f.kind.wire}',
];

/// Returns a DocPath that opens with `prefix`, ends with `suffix`, and holds a
/// run of `a` between them, so `docs/<DocPath>` has `total` characters.
String _paddedPath(String prefix, String suffix, int total) {
  final fill = total - 'docs/'.length - prefix.length - suffix.length;
  return '$prefix${'a' * fill}$suffix';
}

void main() {
  group('feature_mixed_children', () {
    test('f04/us01/fr10/e01, sf-r1: a story left in shop gives feature_mixed_children on shop with docTypes feature and user_story', () async {
      final report = checkOf(
        await writeNestedProject(
          extra: {
            'docs/prds/features/f02_shop/us01_extra/USER_STORY.md':
                nestedFiles()['docs/$cartDrop']!,
          },
        ),
      );
      expect(_jsonOf(report, FindingKind.featureMixedChildren), [
        {
          'kind': 'feature_mixed_children',
          'docPath': shopFeature,
          'name': 'shop',
          'line': 1,
          'message': 'holds both feature and user_story children',
          'docTypes': ['feature', 'user_story'],
        },
      ]);
    });

    test('f04/us01/fr10/e01: a third chain type among the children is listed with commas, ids in code point order', () async {
      final report = checkOf(
        await writeNestedProject(
          extra: {
            '.specstone/templates/epic.yaml':
                'id: epic\ndescription: An epic.\nparent: feature\n'
                'path: prds/features/f{nn}_{slug}/ep{nn}_{slug}/EPIC.md\n',
            '.specstone/templates/task.yaml':
                'id: task\ndescription: A task.\nparent: epic\n'
                'path: prds/features/f{nn}_{slug}/ep{nn}_{slug}/t{nn}_{slug}.md\n',
            'docs/prds/features/f02_shop/us01_extra/USER_STORY.md':
                nestedFiles()['docs/$cartDrop']!,
            'docs/prds/features/f02_shop/ep01_big/EPIC.md': '# Big\n',
            'docs/prds/features/f02_shop/ep01_big/t01_one.md': '# One\n',
          },
        ),
      );
      final found = _jsonOf(report, FindingKind.featureMixedChildren).single;
      expect(found['message'], 'holds epic, feature, and user_story children');
      expect(found['docTypes'], ['epic', 'feature', 'user_story']);
    });

    test('f04/us01/fr10/e01, sf-r10: new feature --parent under a feature that holds stories makes check report feature_mixed_children on it', () async {
      final root = await writeNestedProject();
      writeIn(
        root,
        (s) => answerNew(
          s,
          docTypeId: 'feature',
          parent: 'shop/cart',
          slug: 'gift',
        ),
      );
      expect(spots(checkOf(root), FindingKind.featureMixedChildren), [
        '$cartFeature:1: feature_mixed_children',
      ]);
    });

    test('f04/us01/fr10/e02, f04/us01/fr11/e01: the nested project gives none of the four nesting kinds', () async {
      final report = checkOf(await writeNestedProject());
      expect([
        for (final kind in [
          FindingKind.featureMixedChildren,
          FindingKind.subFeatureTooSmall,
          FindingKind.nestingOverLimit,
          FindingKind.pathOverLimit,
        ])
          ...spots(report, kind),
      ], isEmpty);
    });
  });

  group('sub_feature_too_small', () {
    test('f04/us01/fr10/e02, sf-c4: pay with one story gives sub_feature_too_small, minimum 2, actual 1', () async {
      final report = checkOf(
        await writeNestedProject(without: {'docs/$payRefund'}),
      );
      expect(_jsonOf(report, FindingKind.subFeatureTooSmall), [
        {
          'kind': 'sub_feature_too_small',
          'docPath': payFeature,
          'name': 'shop/pay',
          'line': 1,
          'message': 'holds 1 children; a nested feature holds at least 2',
          'minimum': 2,
          'actual': 1,
        },
      ]);
    });

    test(
      'f04/us01/fr10/e02, sf-c4: pay with a story and a sub-feature gives none',
      () async {
        final report = checkOf(
          await writeNestedProject(
            without: {'docs/$payRefund'},
            extra: {
              'docs/prds/features/f02_shop/f02_pay/f01_x/FEATURE.md':
                  nestedFiles()['docs/$payFeature']!,
            },
          ),
        );
        expect(
          spots(report, FindingKind.subFeatureTooSmall),
          isNot(contains('$payFeature:1: sub_feature_too_small')),
        );
      },
    );

    test(
      'f04/us01/fr10/e02, sf-c4: shop, a top feature, never gives it',
      () async {
        final report = checkOf(
          await writeNestedProject(
            without: {'docs/$payFeature', 'docs/$payCard', 'docs/$payRefund'},
          ),
        );
        expect(spots(report, FindingKind.subFeatureTooSmall), isEmpty);
      },
    );
  });

  group('nesting_over_limit', () {
    final deepFiles = {
      'docs/$_deepFeature': nestedFiles()['docs/$cartFeature']!,
    };
    final withStory = {
      ...deepFiles,
      'docs/$_deepStory': nestedFiles()['docs/$cartDrop']!,
    };

    test('f04/us01/fr10/e03, sf-r5: a FEATURE.md at depth 4 gives nesting_over_limit, limit 3, actual 4, and its story gives no finding of any kind', () async {
      final report = checkOf(await writeNestedProject(extra: withStory));
      expect(_jsonOf(report, FindingKind.nestingOverLimit), [
        {
          'kind': 'nesting_over_limit',
          'docPath': _deepFeature,
          'line': 1,
          'message': 'nests 4 levels below a top feature; the limit is 3',
          'limit': 3,
          'actual': 4,
        },
      ]);
      expect(spots(report, FindingKind.untypedDoc), isEmpty);
      expect(_under(report, _deepFolder), [
        '$_deepFeature: nesting_over_limit',
      ]);
    });

    test('f04/us01/fr10/e03, sf-r5: the same doc with no story under it gives one finding', () async {
      final report = checkOf(await writeNestedProject(extra: deepFiles));
      expect(_under(report, _deepFolder), [
        '$_deepFeature: nesting_over_limit',
      ]);
    });

    test('f04/us01/fr10/e03: a link finding and a note in the folder of an over-deep FEATURE.md report nothing', () async {
      final report = checkOf(
        await writeNestedProject(
          extra: {
            ...deepFiles,
            'docs/$_deepFolder/NOTES.md':
                '# Notes\n\nSee [x](../../nowhere.md).\n',
          },
        ),
      );
      expect(_under(report, _deepFolder), [
        '$_deepFeature: nesting_over_limit',
      ]);
    });

    test('f04/us01/fr10/e05: of two over-limit FEATURE.md files, one in the folder of the other, the outer one reports', () async {
      final report = checkOf(
        await writeNestedProject(
          extra: {
            ...deepFiles,
            'docs/$_deepFolder/f01_d/FEATURE.md':
                nestedFiles()['docs/$cartFeature']!,
          },
        ),
      );
      expect(spots(report, FindingKind.nestingOverLimit), [
        '$_deepFeature:1: nesting_over_limit',
      ]);
      expect(_under(report, '$_deepFolder/f01_d'), isEmpty);
    });

    test('f04/us01/fr10/e04: a project layer that writes max_depth 0 makes a nested FEATURE.md nesting_over_limit, limit 0, actual 1, never untyped_doc', () async {
      final report = checkOf(
        await writeNestedProject(
          extra: {'.specstone/templates/feature.yaml': 'max_depth: 0\n'},
        ),
      );
      expect(_jsonOf(report, FindingKind.nestingOverLimit), [
        for (final path in [cartFeature, payFeature])
          {
            'kind': 'nesting_over_limit',
            'docPath': path,
            'line': 1,
            'message': 'nests 1 levels below a top feature; the limit is 0',
            'limit': 0,
            'actual': 1,
          },
      ]);
      expect(
        spots(
          report,
          FindingKind.untypedDoc,
        ).where((s) => s.startsWith('prds/')),
        isEmpty,
      );
    });
  });

  group('path_over_limit', () {
    const folder = 'prds/features/f02_shop/f01_cart/us01_add_item/';
    final frBody = nestedFiles()['docs/$cartAddFr']!;

    test('f04/us01/fr11/e01, sf-r9: a doc whose docs/<DocPath> is 201 characters gives path_over_limit, limit 200, actual 201', () async {
      final path = _paddedPath('${folder}fr02_', '.md', 201);
      final report = checkOf(
        await writeNestedProject(extra: {'docs/$path': frBody}),
      );
      expect(_jsonOf(report, FindingKind.pathOverLimit), [
        {
          'kind': 'path_over_limit',
          'docPath': path,
          'name':
              'shop/cart/add_item/${path.split('fr02_').last.replaceAll('.md', '')}',
          'line': 1,
          'message': 'the path from the project root has 201 characters; the limit is 200',
          'limit': 200,
          'actual': 201,
        },
      ]);
    });

    test(
      'f04/us01/fr11/e01, sf-r9: a doc at 200 characters gives none',
      () async {
        final path = _paddedPath('${folder}fr02_', '.md', 200);
        final report = checkOf(
          await writeNestedProject(extra: {'docs/$path': frBody}),
        );
        expect(spots(report, FindingKind.pathOverLimit), isEmpty);
      },
    );

    test(
      'f04/us01/fr11/e01, sf-r9: an untyped doc that long gives one',
      () async {
        final path = _paddedPath('${folder}NOTES_', '.md', 201);
        final report = checkOf(
          await writeNestedProject(extra: {'docs/$path': '# Notes\n'}),
        );
        expect(spots(report, FindingKind.pathOverLimit), [
          '$path:1: path_over_limit',
        ]);
      },
    );
  });
}
