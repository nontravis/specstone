import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:test/test.dart';

import '../../helpers/fixture_doc_types.dart';

const _zeta = '''
id: zeta
description: A second doc type on the same paths.
path: prds/features/f{nn}_rendering/FEATURE.md
''';

MergedDocType _docType(String id, String path, {bool perTarget = false}) =>
    MergedDocType(
      id: id,
      path: path,
      isPerTarget: perTarget,
      fields: const [],
      sections: const [],
      lint: const MergedLint(),
      files: const [],
    );

void main() {
  group('DocTypeMatcher.match', () {
    test('f05/us01/fr02, doc_model/s03/inv3: a doc path with one matching '
        'doc type is that doc type', () async {
      final matcher = DocTypeMatcher(await fixtureDocTypes());

      final match = matcher.match('prds/features/f05_rendering/FEATURE.md');

      expect(match, isA<MatchedDocType>());
      expect((match as MatchedDocType).docType.id, 'feature');
    });

    test('f05/us01/fr02/e02, doc_model/s03/inv3: a doc path no doc type '
        'matches is NoDocType', () async {
      final matcher = DocTypeMatcher(await fixtureDocTypes());

      expect(
        matcher.match('prds/features/f05_rendering/notes.md'),
        isA<NoDocType>(),
      );
    });

    test('f05/us01/fr02/e03, doc_model/s03/inv3: a doc path two doc types '
        'match is ambiguous, ids in code point order', () async {
      final matcher = DocTypeMatcher(
        await fixtureDocTypes(extra: {'zeta.yaml': _zeta}),
      );

      final match = matcher.match('prds/features/f05_rendering/FEATURE.md');

      expect(match, isA<AmbiguousDocType>());
      expect((match as AmbiguousDocType).docTypeIds, ['feature', 'zeta']);
    });

    test('a doc type with no path never matches', () {
      // The resolver requires a path (INV-12), so build the set directly.
      final matcher = DocTypeMatcher(
        MergedSet(
          docTypes: [
            const MergedDocType(
              id: 'pathless',
              fields: [],
              sections: [],
              lint: MergedLint(),
              files: [],
            ),
          ],
        ),
      );

      expect(matcher.match('pathless'), isA<NoDocType>());
      expect(matcher.match(''), isA<NoDocType>());
      expect(matcher.entryNumber(['pathless']), isNull);
    });
  });

  group('DocTypeMatcher per-target patterns', () {
    MergedSet setOf(List<MergedDocType> docTypes) =>
        MergedSet(docTypes: [for (final docType in docTypes) docType]);

    test(
      'doc_model/s03/rule-20, template_packs/add_doc_type INV-30: with two '
      'targets a per-target doc type matches one twin per target and names it',
      () {
        final matcher = DocTypeMatcher(
          setOf([
            _docType(
              'architecture',
              'specs/f{nn}_{slug}/ARCHITECTURE.md',
              perTarget: true,
            ),
          ]),
          targetNames: const ['flutter', 'jaspr'],
        );

        final flutter = matcher.match(
          'specs/flutter/f01_login/ARCHITECTURE.md',
        );
        expect((flutter as MatchedDocType).docType.id, 'architecture');
        expect(flutter.target, 'flutter');

        final jaspr = matcher.match('specs/jaspr/f01_login/ARCHITECTURE.md');
        expect((jaspr as MatchedDocType).docType.id, 'architecture');
        expect(jaspr.target, 'jaspr');
      },
    );

    test(
      'doc_model/s03/rule-20: with two targets the one-target pattern matches '
      'nothing, and an unlisted target folder matches nothing',
      () {
        final matcher = DocTypeMatcher(
          setOf([
            _docType(
              'architecture',
              'specs/f{nn}_{slug}/ARCHITECTURE.md',
              perTarget: true,
            ),
          ]),
          targetNames: const ['flutter', 'jaspr'],
        );

        expect(
          matcher.match('specs/f01_login/ARCHITECTURE.md'),
          isA<NoDocType>(),
        );
        expect(
          matcher.match('specs/tauri/f01_login/ARCHITECTURE.md'),
          isA<NoDocType>(),
        );
      },
    );

    test('doc_model/s03/rule-20: a shared doc type keeps its own pattern and '
        'matches with no target', () {
      final matcher = DocTypeMatcher(
        setOf([
          _docType('feature', 'prds/features/f{nn}_{slug}/FEATURE.md'),
          _docType(
            'architecture',
            'specs/f{nn}_{slug}/ARCHITECTURE.md',
            perTarget: true,
          ),
        ]),
        targetNames: const ['flutter', 'jaspr'],
      );

      final shared = matcher.match('prds/features/f01_login/FEATURE.md');
      expect((shared as MatchedDocType).docType.id, 'feature');
      expect(shared.target, isNull);
    });

    test(
      'doc_model/s03/rule-20: with one target a per-target doc type keeps its '
      'own pattern',
      () {
        final matcher = DocTypeMatcher(
          setOf([
            _docType(
              'architecture',
              'specs/f{nn}_{slug}/ARCHITECTURE.md',
              perTarget: true,
            ),
          ]),
          targetNames: const ['flutter'],
        );

        final match = matcher.match('specs/f01_login/ARCHITECTURE.md');
        expect((match as MatchedDocType).docType.id, 'architecture');
        expect(
          matcher.match('specs/flutter/f01_login/ARCHITECTURE.md'),
          isA<NoDocType>(),
        );
      },
    );

    test('doc_model/s03/rule-20: a per-target doc type with no target names '
        'keeps its own pattern', () {
      final matcher = DocTypeMatcher(
        setOf([
          _docType(
            'architecture',
            'specs/f{nn}_{slug}/ARCHITECTURE.md',
            perTarget: true,
          ),
        ]),
      );

      final match = matcher.match('specs/f01_login/ARCHITECTURE.md');
      expect((match as MatchedDocType).docType.id, 'architecture');
    });
  });

  group('DocTypeMatcher.entryNumber', () {
    test(
      'returns the first number any doc type reads from the segments',
      () async {
        final matcher = DocTypeMatcher(await fixtureDocTypes());

        expect(matcher.entryNumber(['prds', 'features', 'f05_rendering']), 5);
        expect(matcher.entryNumber(['prds', 'd01_context.md']), 1);
        expect(
          matcher.entryNumber([
            'prds',
            'features',
            'f05_rendering',
            'FEATURE.md',
          ]),
          isNull,
        );
        expect(matcher.entryNumber(['prds', 'zeta.md']), isNull);
      },
    );

    test(
      'is null, without throwing, when the digits overflow an int',
      () async {
        final matcher = DocTypeMatcher(await fixtureDocTypes());

        expect(
          matcher.entryNumber(['prds', 'features', 'f99999999999999999999_x']),
          isNull,
        );
      },
    );
  });

  group('DocTypeMatcher nested depths', () {
    MergedDocType docType(String id, String path, {int? maxDepth}) =>
        MergedDocType(
          id: id,
          path: path,
          maxDepth: maxDepth,
          fields: const [],
          sections: const [],
          lint: const MergedLint(),
          files: const [],
        );

    DocTypeMatcher matcherAt(int maxDepth) => DocTypeMatcher(
      MergedSet(
        docTypes: [
          docType(
            'feature',
            'prds/features/f{nn}_{slug}/FEATURE.md',
            maxDepth: maxDepth,
          ),
        ],
      ),
    );

    test('doc_model/s03/inv10: depth 3 matches feature and depth 4 matches '
        'none', () {
      final matcher = matcherAt(3);

      final match = matcher.match(
        'prds/features/f01_a/f01_b/f01_c/f01_d/FEATURE.md',
      );
      expect((match as MatchedDocType).docType.id, 'feature');

      const tooDeep = 'prds/features/f01_a/f01_b/f01_c/f01_d/f01_e/FEATURE.md';
      expect(matcher.match(tooDeep), isA<NoDocType>());
      expect(matcher.depthPastLimit(tooDeep), 4);
      expect(matcher.depthPastLimit('prds/features/f01_a/FEATURE.md'), isNull);
    });

    test('doc_model/s03/inv10: max_depth 0 reports depth 1 past the limit', () {
      expect(
        matcherAt(0).depthPastLimit('prds/features/f01_a/f01_b/FEATURE.md'),
        1,
      );
    });

    test('depthPastLimit is null for a set with no nesting type', () async {
      final matcher = DocTypeMatcher(await fixtureDocTypes());

      expect(
        matcher.depthPastLimit('prds/features/f01_a/f01_b/FEATURE.md'),
        isNull,
      );
    });

    test('doc_model/s03/inv10: entryNumber reads the number of a nested '
        'segment', () {
      expect(
        matcherAt(1).entryNumber(['prds', 'features', 'f01_a', 'f02_b']),
        2,
      );
    });
  });
}
