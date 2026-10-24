import 'package:specstone_core/src/doc_model/path_pattern.dart';
import 'package:test/test.dart';

void main() {
  group('PathPattern.matches', () {
    test('f05/us01/fr02/e04, doc_model/s03/inv1: a pattern is a full path '
        'from the docs root', () {
      expect(
        PathPattern('prds/features/f{nn}_{slug}/FEATURE.md')
            .matches('prds/features/f05_rendering/FEATURE.md'),
        isTrue,
      );
      expect(
        PathPattern('features/f{nn}_{slug}/FEATURE.md')
            .matches('prds/features/f05_rendering/FEATURE.md'),
        isFalse,
      );
    });

    test('doc_model/s03/inv2: several placeholders, each matched on its '
        'own', () {
      final pattern = PathPattern(
        'prds/features/f{nn}_{slug}/us{nn}_{slug}/functional_requirements/'
        'fr{nn}_{slug}.md',
      );

      expect(
        pattern.matches(
          'prds/features/f05_rendering/us01_format_docs/'
          'functional_requirements/fr01_resolve_format_target.md',
        ),
        isTrue,
      );
      expect(
        pattern.matches(
          'prds/features/f05_rendering/us01_a/b/functional_requirements/'
          'fr01_x.md',
        ),
        isFalse,
      );
    });

    test('f05/us01/fr02/e01, doc_model/s03/inv2: {nn} takes digits, {slug} '
        'takes [a-z0-9_], and other characters are literal', () {
      final pattern = PathPattern('f{nn}_{slug}.md');
      final results = [
        for (final path in [
          'f5_a.md',
          'f123_a_b9.md',
          'fx_a.md',
          'f05_A.md',
          'f05_a-b.md',
          'f05_a/b.md',
          'f05_axmd',
        ])
          pattern.matches(path),
      ];

      expect(results, [true, true, false, false, false, false, false]);
    });
  });

  group('PathPattern.numberAt', () {
    final feature = PathPattern('prds/features/f{nn}_{slug}/FEATURE.md');

    test('returns the first {nn} of the segment at the entry depth', () {
      expect(feature.numberAt(['prds', 'features', 'f05_rendering']), 5);
      expect(
        PathPattern('prds/d{nn}_{slug}.md')
            .numberAt(['prds', 'd01_context.md']),
        1,
      );
    });

    test('takes the first of several {nn} in one segment', () {
      expect(PathPattern('x{nn}_y{nn}.md').numberAt(['x07_y09.md']), 7);
    });

    test('is null when an earlier segment does not match', () {
      expect(feature.numberAt(['docs', 'features', 'f05_rendering']), isNull);
    });

    test('is null when the segment at the entry depth has no {nn}', () {
      expect(
        feature.numberAt(['prds', 'features', 'f05_rendering', 'FEATURE.md']),
        isNull,
      );
    });

    test('is null when the entry is deeper than the pattern', () {
      expect(
        feature.numberAt([
          'prds',
          'features',
          'f05_rendering',
          'FEATURE.md',
          'extra',
        ]),
        isNull,
      );
    });

    test('is null when the last segment does not match its pattern '
        'segment', () {
      expect(feature.numberAt(['prds', 'features', 'fx_rendering']), isNull);
    });

    test('is null for an empty segment list', () {
      expect(feature.numberAt([]), isNull);
    });

    test('is null, without throwing, when the {nn} digits overflow an int', () {
      const overlong = 'f99999999999999999999_x';

      expect(feature.numberAt(['prds', 'features', overlong]), isNull);
      expect(feature.matches('prds/features/$overlong/FEATURE.md'), isTrue);
    });
  });

  group('PathPattern.slugValues', () {
    test('f01/us01/fr03/e01, s03/inv5: every slug value in pattern order, '
        'nn values dropped', () {
      expect(
        PathPattern('prds/features/f{nn}_{slug}/us{nn}_{slug}/fr{nn}_{slug}.md')
            .slugValues(
              'prds/features/f01_login/us02_email_login/'
              'fr01_validate_credentials.md',
            ),
        ['login', 'email_login', 'validate_credentials'],
      );
    });

    test('f01/us01/fr03/e02: a pattern with no slug gives an empty list; no '
        'match gives null', () {
      expect(
        PathPattern('prds/PROJECT.md').slugValues('prds/PROJECT.md'),
        isEmpty,
      );
      expect(PathPattern('prds/PROJECT.md').slugValues('prds/GNFR.md'), isNull);
    });
  });
}
