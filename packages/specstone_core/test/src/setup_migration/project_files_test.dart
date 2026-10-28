import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/setup_migration/legacy_tree.dart';
import 'package:specstone_core/src/setup_migration/project_files.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/legacy_fixture.dart';
import '../../helpers/shipped_pins.dart';

const _packs = ['prd-core', 'software-tech'];

DocTypeMatcher _matcherWith(Map<String, String> overrides) {
  final set = TemplateResolver().resolveCarried(
    packNames: _packs,
    homeDirectory: null,
    projectLayers: parseOverrides(overrides),
  );
  return DocTypeMatcher(set);
}

String? _matchedId(DocTypeMatcher matcher, String docPath) =>
    switch (matcher.match(docPath)) {
      MatchedDocType(:final docType) => docType.id,
      _ => null,
    };

void main() {
  group('project files', () {
    test('f06/us01/fr05: the config pins prd-core and software-tech at the '
        'carried versions', () {
      final manifests = TemplateResolver().availableManifests(
        _packs,
        homeDirectory: null,
      );

      final text = configText({
        for (final entry in manifests.entries) entry.key: entry.value.version,
      });

      expect(text, shippedPinsConfig());
    });

    test('f06/us01/fr05/e01: an ARCHITECTURE renamed one to one covers each '
        'Code path of its old folder, in row order', () {
      final rows = [
        const SpecMapRow(
          codePath: 'lib/a/',
          specPath: 'specs/api/auth/',
          featureId: 'f01_login',
        ),
        const SpecMapRow(
          codePath: 'lib/other/',
          specPath: 'specs/other/',
          featureId: 'f02_other',
        ),
        const SpecMapRow(
          codePath: 'lib/b/',
          specPath: 'specs/api/auth/',
          featureId: 'f01_login',
        ),
      ];

      final covers = coversOf('specs/api/auth/', rows);

      expect(covers?.block, 'covers:\n  - lib/a/\n  - lib/b/\n');
      expect(covers?.label, 'covers (2 paths)');
      expect(coversOf('specs/missing/', rows), isNull);
    });

    test('f06/us01/fr05/e01: the acme fixture covers one path', () {
      final rows = readSpecMap(acmeLegacy['docs/specs/INDEX.md']!);

      final covers = coversOf('specs/api/auth/', rows);

      expect(covers?.block, 'covers:\n  - api/auth/\n');
      expect(covers?.label, 'covers (1 path)');
    });

    test('f06/us01/fr05/e03: a grouped tree gets the ten path overrides, '
        'and they load', () {
      final overrides = groupedPathOverrides();

      expect(overrides.keys, [
        for (final id in [
          'feature',
          'user_story',
          'fr',
          'nf',
          'architecture',
          'api',
          'domain',
          'error',
          'integration',
          'auth',
        ])
          '.specstone/templates/$id.yaml',
      ]);
      expect(
        overrides['.specstone/templates/domain.yaml'],
        'path: specs/{slug}/f{nn}_{slug}/DOMAIN.md\n',
      );
      final matcher = _matcherWith(overrides);
      expect(
        _matchedId(matcher, 'prds/features/utilities/f01_slot/FEATURE.md'),
        'feature',
      );
      expect(
        _matchedId(
          matcher,
          'prds/features/utilities/f01_slot/us01_place/fr02_fill.md',
        ),
        'fr',
      );
      expect(_matchedId(matcher, 'specs/utilities/f01_slot/API.md'), 'api');
    });

    test('f06/us01/fr05/e04: a legacy NFR category with no GNFR section '
        'becomes a gnfr section override', () {
      final entry = gnfrOverride(['Data integrity', 'Token efficiency']);

      expect(entry?.key, '.specstone/templates/gnfr.yaml');
      expect(
        entry?.value,
        'sections:\n'
        '  - id: data_integrity\n'
        '    header: Data integrity\n'
        '  - id: token_efficiency\n'
        '    header: Token efficiency\n',
      );
      final set = TemplateResolver().resolveCarried(
        packNames: _packs,
        homeDirectory: null,
        projectLayers: parseOverrides({entry!.key: entry.value}),
      );
      final headers = [
        for (final section in set.lookup('gnfr')!.sections) section.header,
      ];
      expect(headers, contains('Data integrity'));
      expect(gnfrOverride([]), isNull);
    });

    test('f06/us01/fr05/e06, f06/us01/fr05/e07: the singular doc types are '
        'project, features, gnfr, tech_stack', () {
      final set = TemplateResolver().resolveCarried(
        packNames: _packs,
        homeDirectory: null,
      );

      expect(singularDocTypes(set).map((type) => type.path), [
        'prds/PROJECT.md',
        'prds/FEATURES.md',
        'prds/GNFR.md',
        'specs/TECH_STACK.md',
      ]);
    });
  });
}
