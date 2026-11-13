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

  group('PathPattern.forTarget', () {
    final pattern = PathPattern('specs/f{nn}_{slug}/ARCHITECTURE.md');

    test('doc_model/s03/rule-20: inserts the target folder after the first '
        'segment and matches and fills with it', () {
      final targeted = pattern.forTarget('jaspr');

      expect(targeted.source, 'specs/jaspr/f{nn}_{slug}/ARCHITECTURE.md');
      expect(targeted.matches('specs/jaspr/f01_login/ARCHITECTURE.md'), isTrue);
      expect(
        targeted.matches('specs/flutter/f01_login/ARCHITECTURE.md'),
        isFalse,
      );
      expect(targeted.valuesOf('specs/jaspr/f01_login/ARCHITECTURE.md'), [
        '01',
        'login',
      ]);
      expect(
        targeted.fill(['01', 'login']),
        'specs/jaspr/f01_login/ARCHITECTURE.md',
      );
    });

    test('doc_model/s03/rule-20: a two-segment pattern takes the target as a '
        'folder of its own', () {
      expect(
        PathPattern('specs/TECH_STACK.md').forTarget('jaspr').source,
        'specs/jaspr/TECH_STACK.md',
      );
    });

    test('doc_model/s03/rule-20: a pattern with no folder inserts the target '
        'folder beside it, so each target matches its own doc', () {
      final targeted = PathPattern('{slug}.md').forTarget('jaspr');

      expect(targeted.source, 'jaspr/{slug}.md');
      expect(targeted.matches('jaspr/deploy.md'), isTrue);
      expect(targeted.matches('deploy.md'), isFalse);
      expect(targeted.matches('flutter/deploy.md'), isFalse);
    });

    test('doc_model/s03/rule-20: targetFolder is the first folder and the '
        'target, where forTarget puts it', () {
      expect(
        PathPattern('specs/f{nn}_{slug}/ARCHITECTURE.md').targetFolder('jaspr'),
        'specs/jaspr/',
      );
      expect(PathPattern('{slug}.md').targetFolder('jaspr'), 'jaspr/');
    });
  });

  group('PathPattern.valuesOf and fill', () {
    test('f06/us02/fr02/e04: valuesOf and fill keep the placeholder values '
        'in order', () {
      expect(
        PathPattern('prds/runbooks/{slug}/RUNBOOK.md')
            .valuesOf('prds/runbooks/deploy/RUNBOOK.md'),
        ['deploy'],
      );
      expect(PathPattern('ops/{slug}/r{nn}.md').valuesOf('ops/deploy/r03.md'), [
        'deploy',
        '03',
      ]);
      expect(
        PathPattern('ops/{slug}/r{nn}.md').fill(['deploy', '03']),
        'ops/deploy/r03.md',
      );
      expect(PathPattern('ops/{slug}/r{nn}.md').valuesOf('ops/x.md'), isNull);
    });

    test('f06/us02/fr02/e04: valuesOf reads {nn} before {slug}, and fill '
        'output matches the pattern again', () {
      final pattern = PathPattern('prds/features/f{nn}_{slug}/FEATURE.md');
      final values = pattern.valuesOf('prds/features/f06_setup/FEATURE.md');

      expect(values, ['06', 'setup']);
      expect(pattern.matches(pattern.fill(values!)), isTrue);
    });

    test('f06/us02/fr02/e04: fill refuses a value count that differs from '
        'the placeholder count', () {
      expect(
        () => PathPattern('ops/{slug}/r{nn}.md').fill(['deploy']),
        throwsArgumentError,
      );
    });
  });
}
