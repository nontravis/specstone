import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:test/test.dart';

MergedDocType docType(
  String id,
  String path, {
  String? parent,
  int? maxDepth,
}) => MergedDocType(
  id: id,
  path: path,
  parent: parent,
  maxDepth: maxDepth,
  fields: const [],
  sections: const [],
  lint: const MergedLint(),
  files: const [],
);

MergedDocType feature({int? maxDepth}) => docType(
  'feature',
  'prds/features/f{nn}_{slug}/FEATURE.md',
  maxDepth: maxDepth,
);

final MergedDocType story = docType(
  'user_story',
  'prds/features/f{nn}_{slug}/us{nn}_{slug}/USER_STORY.md',
  parent: 'feature',
);
final MergedDocType fr = docType(
  'fr',
  'prds/features/f{nn}_{slug}/us{nn}_{slug}/fr{nn}_{slug}.md',
  parent: 'user_story',
);
final MergedDocType domain = docType(
  'domain',
  'specs/f{nn}_{slug}/DOMAIN.md',
  parent: 'feature',
);
final MergedDocType topic = docType('topic', 'specs/topics/{slug}.md');

void main() {
  group('MergedSet nested paths', () {
    test('tpl-s03/inv28, sf-r6: a feature at max_depth 2 nests its story, '
        'fr, and domain', () {
      final set = MergedSet(
        docTypes: [feature(maxDepth: 2), story, fr, domain, topic],
      );

      expect(set.lookup('feature')!.paths, [
        'prds/features/f{nn}_{slug}/FEATURE.md',
        'prds/features/f{nn}_{slug}/f{nn}_{slug}/FEATURE.md',
        'prds/features/f{nn}_{slug}/f{nn}_{slug}/f{nn}_{slug}/FEATURE.md',
      ]);
      expect(
        set.lookup('fr')!.paths[1],
        'prds/features/f{nn}_{slug}/f{nn}_{slug}/us{nn}_{slug}/'
        'fr{nn}_{slug}.md',
      );
      expect(
        set.lookup('domain')!.paths[2],
        'specs/f{nn}_{slug}/f{nn}_{slug}/f{nn}_{slug}/DOMAIN.md',
      );
      expect(set.lookup('topic')!.paths, ['specs/topics/{slug}.md']);
      expect(set.nestingType!.id, 'feature');
    });

    test("sf-r6: stratum_ui's group paths nest after f{nn}_{slug}", () {
      final stratum = docType(
        'feature',
        'prds/features/{slug}/f{nn}_{slug}/FEATURE.md',
        maxDepth: 1,
      );
      final stratumDomain = docType(
        'domain',
        'specs/{slug}/f{nn}_{slug}/DOMAIN.md',
        parent: 'feature',
      );
      final set = MergedSet(docTypes: [stratum, stratumDomain]);

      expect(
        set.lookup('feature')!.paths[1],
        'prds/features/{slug}/f{nn}_{slug}/f{nn}_{slug}/FEATURE.md',
      );
      expect(
        set.lookup('domain')!.paths[1],
        'specs/{slug}/f{nn}_{slug}/f{nn}_{slug}/DOMAIN.md',
      );
    });

    test('tpl-s03/inv28: max_depth 0 keeps one pattern and still names the '
        'nesting type', () {
      final set = MergedSet(docTypes: [feature(maxDepth: 0), story]);

      expect(set.lookup('feature')!.paths, [
        'prds/features/f{nn}_{slug}/FEATURE.md',
      ]);
      expect(set.nestingType!.id, 'feature');
    });

    test('tpl-s03/inv28: no max_depth names no nesting type', () {
      expect(MergedSet(docTypes: [feature(), story]).nestingType, isNull);
    });

    test('tpl-s03/inv28: a child of feature at specs/notes/{slug}.md keeps '
        'one pattern', () {
      final notes = docType(
        'notes',
        'specs/notes/{slug}.md',
        parent: 'feature',
      );
      final set = MergedSet(docTypes: [feature(maxDepth: 2), notes]);

      expect(set.lookup('notes')!.paths, ['specs/notes/{slug}.md']);
    });

    test('a doc type with no path has no patterns', () {
      const pathless = MergedDocType(
        id: 'pathless',
        fields: [],
        sections: [],
        lint: MergedLint(),
        files: [],
      );

      expect(pathless.paths, isEmpty);
    });

    test('a parent cycle does not hang the nesting walk', () {
      final a = docType('a', 'x/{slug}/A.md', parent: 'b');
      final b = docType('b', 'x/{slug}/B.md', parent: 'a');
      final set = MergedSet(docTypes: [feature(maxDepth: 1), a, b]);

      expect(set.lookup('a')!.paths, ['x/{slug}/A.md']);
    });
  });
}
