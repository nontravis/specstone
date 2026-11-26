import 'package:specstone_core/src/templates/feature_group_paths.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

MergedDocType _type(
  String id, {
  String? path,
  String? pathFrom,
  String? file,
  String? parent,
}) => MergedDocType(
  id: id,
  parent: parent,
  path: path,
  pathFrom: pathFrom,
  file: file,
  fields: const [],
  sections: const [],
  lint: const MergedLint(),
  files: const [],
);

void main() {
  group('featureGroupPatterns', () {
    test('one group level gives one pattern beside the group folder', () {
      expect(
        featureGroupPatterns(
          'prds/features/{slug}/f{nn}_{slug}/FEATURE.md',
          'FEATURES.md',
        ),
        ['prds/features/{slug}/FEATURES.md'],
      );
    });

    test('two group levels give one pattern per level, shallowest first', () {
      expect(
        featureGroupPatterns(
          'prds/features/{slug}/{slug}/f{nn}_{slug}/FEATURE.md',
          'AREA.md',
        ),
        ['prds/features/{slug}/AREA.md', 'prds/features/{slug}/{slug}/AREA.md'],
      );
    });

    test('an ungrouped feature path gives no pattern', () {
      expect(
        featureGroupPatterns(
          'prds/features/f{nn}_{slug}/FEATURE.md',
          'FEATURES.md',
        ),
        isEmpty,
      );
    });

    test('a {slug} segment after the own segment gives no pattern', () {
      expect(
        featureGroupPatterns(
          'prds/features/f{nn}_{slug}/{slug}/FEATURE.md',
          'FEATURES.md',
        ),
        isEmpty,
      );
    });

    test('a repeat of the own segment after it adds no pattern', () {
      expect(
        featureGroupPatterns(
          'prds/features/{slug}/f{nn}_{slug}/f{nn}_{slug}/FEATURE.md',
          'FEATURES.md',
        ),
        ['prds/features/{slug}/FEATURES.md'],
      );
    });
  });

  group('withFeatureGroupPaths', () {
    final feature = _type(
      'feature',
      path: 'prds/features/{slug}/f{nn}_{slug}/FEATURE.md',
    );

    test('a path_from type takes the derived patterns of the feature type', () {
      final derived = withFeatureGroupPaths([
        feature,
        _type('area_index', pathFrom: 'feature_groups', file: 'AREA.md'),
      ]);

      expect(derived.last.paths, ['prds/features/{slug}/AREA.md']);
      expect(derived.first.paths, [
        'prds/features/{slug}/f{nn}_{slug}/FEATURE.md',
      ]);
    });

    test('a path_from type holds no pattern in an ungrouped set', () {
      final derived = withFeatureGroupPaths([
        _type('feature', path: 'prds/features/f{nn}_{slug}/FEATURE.md'),
        _type('area_index', pathFrom: 'feature_groups', file: 'AREA.md'),
      ]);

      expect(derived.last.derivedPaths, isEmpty);
      expect(derived.last.paths, isEmpty);
    });

    test('a set with no path_from type comes back as the same objects', () {
      final types = [feature, _type('note', path: 'notes/{slug}.md')];

      expect(withFeatureGroupPaths(types), same(types));
    });
  });

  group('withGroupLevels', () {
    MergedDocType feature(String path) => _type('feature', path: path);
    const groupedFeature = 'prds/features/{slug}/f{nn}_{slug}/FEATURE.md';

    MergedDocType child(String id, String path, {String parent = 'feature'}) =>
        _type(id, path: path, parent: parent);

    test('an ungrouped feature path leaves every child type as the same '
        'object', () {
      final input = [
        feature('prds/features/f{nn}_{slug}/FEATURE.md'),
        child('api', 'specs/f{nn}_{slug}/API.md'),
      ];

      final result = withGroupLevels(input);

      expect(identical(result[1], input[1]), isTrue);
    });

    test('a one-level feature path puts one group folder before each child '
        'feature folder', () {
      final result = withGroupLevels([
        feature(groupedFeature),
        child(
          'user_story',
          'prds/features/f{nn}_{slug}/us{nn}_{slug}/USER_STORY.md',
        ),
        child('api', 'specs/f{nn}_{slug}/API.md'),
        child(
          'implementation',
          '.specstone/records/f{nn}_{slug}/IMPLEMENTATION.md',
        ),
      ]);

      expect(result.map((t) => t.path), [
        groupedFeature,
        'prds/features/{slug}/f{nn}_{slug}/us{nn}_{slug}/USER_STORY.md',
        'specs/{slug}/f{nn}_{slug}/API.md',
        '.specstone/records/{slug}/f{nn}_{slug}/IMPLEMENTATION.md',
      ]);
    });

    test('a type reaching feature through its parent chain is grouped', () {
      final result = withGroupLevels([
        feature(groupedFeature),
        child(
          'user_story',
          'prds/features/f{nn}_{slug}/us{nn}_{slug}/USER_STORY.md',
        ),
        child(
          'fr',
          'prds/features/f{nn}_{slug}/us{nn}_{slug}/fr{nn}_{slug}.md',
          parent: 'user_story',
        ),
        child('campaign', 'specs/f{nn}_{slug}/CAMPAIGN.md'),
        child(
          'campaign_results',
          'specs/f{nn}_{slug}/results/RESULTS.md',
          parent: 'campaign',
        ),
      ]);

      expect(
        result[2].path,
        'prds/features/{slug}/f{nn}_{slug}/us{nn}_{slug}/fr{nn}_{slug}.md',
      );
      expect(result[4].path, 'specs/{slug}/f{nn}_{slug}/results/RESULTS.md');
    });

    test('a two-level feature path inserts two group folders once', () {
      final result = withGroupLevels([
        feature('prds/features/{slug}/{slug}/f{nn}_{slug}/FEATURE.md'),
        child('api', 'specs/f{nn}_{slug}/API.md'),
      ]);

      expect(result[1].path, 'specs/{slug}/{slug}/f{nn}_{slug}/API.md');
      expect(withGroupLevels(result)[1].path, result[1].path);
    });

    test('a set with no feature type comes back as the same list', () {
      final types = [child('api', 'specs/f{nn}_{slug}/API.md')];

      expect(withGroupLevels(types), same(types));
    });

    test('a child path holding one group folder is left untouched', () {
      final input = [
        feature(groupedFeature),
        child('api', 'specs/{slug}/f{nn}_{slug}/API.md'),
      ];

      expect(identical(withGroupLevels(input)[1], input[1]), isTrue);
    });

    test('a child path with two group folders is left for the check', () {
      final input = [
        feature(groupedFeature),
        child('api', 'specs/{slug}/{slug}/f{nn}_{slug}/API.md'),
      ];

      expect(identical(withGroupLevels(input)[1], input[1]), isTrue);
    });

    test('the feature type, a type off the chain, and a path with no feature '
        'folder keep their paths', () {
      final input = [
        feature(groupedFeature),
        _type('glossary', path: 'prds/GLOSSARY.md'),
        child('skill', 'specs/skills/{slug}.md'),
      ];

      final result = withGroupLevels(input);

      for (var i = 0; i < input.length; i++) {
        expect(identical(result[i], input[i]), isTrue);
      }
    });
  });

  test('childGroupLevelCount counts the slug folders right before the first '
      'feature folder', () {
    expect(childGroupLevelCount('specs/f{nn}_{slug}/API.md'), 0);
    expect(childGroupLevelCount('specs/{slug}/f{nn}_{slug}/API.md'), 1);
    expect(childGroupLevelCount('specs/skills/{slug}.md'), isNull);
  });
}
