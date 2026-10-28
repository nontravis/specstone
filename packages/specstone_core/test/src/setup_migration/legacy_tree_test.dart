import 'package:specstone_core/src/setup_migration/legacy_tree.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:test/test.dart';

import '../../helpers/git_repo.dart';
import '../../helpers/legacy_fixture.dart';

/// The fixture's paths relative to its `docs/` folder.
List<String> _docPaths(Map<String, String> tree) => [
  for (final key in tree.keys) key.substring('docs/'.length),
];

LegacyFeature _featureAt(LegacyFeatures scan, String folder) =>
    scan.features.singleWhere((f) => f.folder == folder);

void main() {
  group('readSpecMap', () {
    test('f06/us01/fr03: readSpecMap reads the acme rows', () {
      final rows = readSpecMap(acmeLegacy['docs/specs/INDEX.md']!);

      expect(rows, hasLength(2));
      expect(rows[0].codePath, 'api/auth/');
      expect(rows[0].specPath, 'specs/api/auth/');
      expect(rows[0].featureId, 'f01_login');
      expect(rows[1].codePath, 'shared/');
      expect(rows[1].specPath, 'specs/shared/');
      expect(rows[1].featureId, '—');
    });

    test('f06/us01/fr03: readSpecMap finds columns by header name', () {
      const text = '''
## Spec map

| feature_id | Spec path | cross-cutting | Code path | Notes |
|------------|-----------|---------------|-----------|-------|
| f01_login | specs/api/auth/ | — | api/auth/ | auth |
''';

      final rows = readSpecMap(text);

      expect(rows, hasLength(1));
      expect(rows.single.codePath, 'api/auth/');
      expect(rows.single.specPath, 'specs/api/auth/');
      expect(rows.single.featureId, 'f01_login');
    });

    test('f06/us01/fr03: readSpecMap gives [] for a missing column', () {
      const text = '''
## Spec map

| Code path | feature_id |
|-----------|------------|
| `api/auth/` | `f01_login` |
''';

      expect(readSpecMap(text), isEmpty);
    });

    test('f06/us01/fr03: readSpecMap gives [] for a missing section', () {
      expect(readSpecMap('# Spec index\n\n## Global SoT files\n'), isEmpty);
    });

    test('f06/us01/fr03: readSpecMap stops at the next heading', () {
      const text = '''
## Spec map

| Code path | Spec path | feature_id |
|---|---|---|
| a/ | specs/a/ | f01_a |

## Other

| Code path | Spec path | feature_id |
|---|---|---|
| b/ | specs/b/ | f02_b |
''';

      expect(readSpecMap(text).map((r) => r.codePath), ['a/']);
    });
  });

  group('scanLegacyFeatures', () {
    test('f06/us01/fr03/e03: a folder whose child holds FEATURE.md is a '
        'container', () {
      final scan = scanLegacyFeatures(_docPaths(containerLegacy));

      expect(scan.containers, [
        'prds/features/components/co01_utilities/FEATURE.md',
      ]);
      expect(scan.features.map((f) => f.folder), [
        'prds/features/components/co01_utilities/co01_01_slot/',
        'prds/features/components/co07_navigation/',
      ]);
      expect(scan.grouped, isTrue);
      expect(
        _featureAt(
          scan,
          'prds/features/components/co01_utilities/co01_01_slot/',
        ).featurePath,
        'utilities/f01_slot',
      );
      expect(
        _featureAt(
          scan,
          'prds/features/components/co07_navigation/',
        ).featurePath,
        'components/f07_navigation',
      );
    });

    test('f06/us01/fr03/e02: a flat feature keeps its folder name', () {
      final scan = scanLegacyFeatures(_docPaths(acmeLegacy));

      final feature = scan.features.single;
      expect(feature.folder, 'prds/features/f01_login/');
      expect(feature.featurePath, 'f01_login');
      expect(feature.group, isNull);
      expect(scan.grouped, isFalse);
      expect(scan.containers, isEmpty);
    });

    test('f06/us01/fr03/e05, f06/us01/s5: folders above a group drop out of '
        'the path', () {
      final scan = scanLegacyFeatures(_docPaths(groupedLegacy));

      final stripe = _featureAt(
        scan,
        'prds/features/brick_module/tool_module/tm01_stripe/',
      );
      expect(stripe.group, 'prds/features/brick_module/tool_module/');
      expect(stripe.featurePath, 'tool_module/f01_stripe');
      expect(
        _featureAt(scan, 'prds/features/ai_module/ai05_chat/').featurePath,
        'ai_module/f05_chat',
      );
      expect(scan.grouped, isTrue);
    });

    test('f06/us01/fr03/e07: a tree with flat and grouped features is grouped '
        'and its flat features stay', () {
      final scan = scanLegacyFeatures(_docPaths(mixedLegacy));

      expect(scan.grouped, isTrue);
      final flat = _featureAt(scan, 'prds/features/f01_login/');
      expect(flat.group, isNull);
      expect(flat.featurePath, isNull);
      expect(
        _featureAt(scan, 'prds/features/ai_module/ai05_chat/').featurePath,
        'ai_module/f05_chat',
      );
    });

    test('f06/us01/fr03/e02: a flat name with no prefix stays in place', () {
      final scan = scanLegacyFeatures(['prds/features/notes/FEATURE.md']);

      expect(scan.features.single.featurePath, isNull);
      expect(scan.grouped, isFalse);
    });
  });

  group('names', () {
    test('f06/us01/fr03/e04: the group slug drops its prefix and the feature '
        'takes f and its last number', () {
      expect(groupSlugOf('co01_utilities'), 'utilities');
      expect(groupSlugOf('ai_module'), 'ai_module');

      expect(
        featurePathOf('co01_01_slot', groupSlug: 'utilities'),
        'utilities/f01_slot',
      );
      expect(
        featurePathOf('ai05_chat', groupSlug: 'ai_module'),
        'ai_module/f05_chat',
      );
      expect(featurePathOf('f01_login'), 'f01_login');
      expect(featurePathOf('co01_02_03_deep'), 'f03_deep');
      expect(featurePathOf('notes'), isNull);
      expect(featurePathOf('notes', groupSlug: 'g'), isNull);
    });
  });

  group('refuseDuplicateGroups', () {
    test('f06/us01/fr03/e09, f06/us01/s14: two groups with one slug refuse '
        'group_slug_duplicate naming both', () {
      final scan = scanLegacyFeatures(_docPaths(duplicateGroupLegacy));

      late MigrateFault fault;
      try {
        refuseDuplicateGroups(scan);
        fail('expected a MigrateFault');
      } on MigrateFault catch (e) {
        fault = e;
      }

      expect(fault.code, MigrateFaultCode.groupSlugDuplicate);
      expect(fault.exitStatus, 65);
      expect(
        fault.toText(),
        'prds/features/components/co01_utilities: two group folders give '
        'the group utilities; rename one, then run specstone migrate '
        'again; also prds/features/core/cr02_utilities',
      );
    });

    test('f06/us01/fr03/e09: further duplicate slugs chain under more', () {
      final scan = scanLegacyFeatures([
        'prds/features/a/aa01_x/z01_a/FEATURE.md',
        'prds/features/b/bb02_x/z01_b/FEATURE.md',
        'prds/features/c/cc01_y/z01_c/FEATURE.md',
        'prds/features/d/dd02_y/z01_d/FEATURE.md',
      ]);

      try {
        refuseDuplicateGroups(scan);
        fail('expected a MigrateFault');
      } on MigrateFault catch (fault) {
        expect(fault.more, hasLength(1));
        expect(fault.toText().split('\n').map((l) => l.split(':').first), [
          'prds/features/a/aa01_x',
          'prds/features/c/cc01_y',
        ]);
      }
    });

    test('f06/us01/fr03/e09: distinct group slugs pass', () {
      refuseDuplicateGroups(scanLegacyFeatures(_docPaths(groupedLegacy)));
      refuseDuplicateGroups(scanLegacyFeatures(_docPaths(mixedLegacy)));
      refuseDuplicateGroups(scanLegacyFeatures(_docPaths(containerLegacy)));
    });
  });

  group('gitFixture', () {
    test('f06/us01/fr03: gitFixture commits the tree as one commit', () async {
      final root = await gitFixture(acmeLegacy);

      expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
      expect(
        (git(root, ['rev-list', '--count', 'HEAD']).stdout as String).trim(),
        '1',
      );
    }, skip: hasGit ? null : 'git is not available');
  });
}
