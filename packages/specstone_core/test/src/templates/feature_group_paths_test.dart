import 'package:specstone_core/src/templates/feature_group_paths.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

MergedDocType _type(
  String id, {
  String? path,
  String? pathFrom,
  String? file,
}) => MergedDocType(
  id: id,
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
}
