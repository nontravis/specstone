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
  });
}
