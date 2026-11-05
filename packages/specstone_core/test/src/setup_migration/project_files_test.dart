import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/setup_migration/legacy_tree.dart';
import 'package:specstone_core/src/setup_migration/project_files.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/legacy_fixture.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';

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

    group('configText code_root', () {
      final pins = {
        'prd-core': PackVersion.parse('1.2.3', file: 'f', key: 'k'),
      };

      test('the default code root writes the packs lines only', () {
        expect(configText(pins), 'packs:\n  prd-core: 1.2.3\n');
      });

      test('a code root other than . is the last line', () {
        expect(
          configText(pins, codeRoot: 'stratum_ui'),
          'packs:\n  prd-core: 1.2.3\ncode_root: stratum_ui\n',
        );
        expect(
          configText(pins, codeRoot: '../NTD OS/example'),
          endsWith('\ncode_root: ../NTD OS/example\n'),
        );
      });

      for (final (name, codeRoot, line) in [
        ('a number', '2024', "code_root: '2024'\n"),
        ('a comment mark', 'a #b', "code_root: 'a #b'\n"),
        ('a mapping mark', 'a: b', "code_root: 'a: b'\n"),
        ('a broken quote', "'a", "code_root: '''a'\n"),
      ]) {
        test('a code root YAML reads as $name is quoted', () {
          expect(configText(pins, codeRoot: codeRoot), endsWith(line));
        });
      }

      // `a: b` would read as a drive letter, which the reader refuses.
      for (final codeRoot in ['2024', 'a #b', 'lib: b']) {
        test('the config reader reads back code root $codeRoot', () async {
          final root = await writeTree({
            '.specstone/config.yaml': configText(pins, codeRoot: codeRoot),
          });

          expect(ProjectConfig.read(root).codeRoot, codeRoot);
        });
      }
    });

    group('configText agent_file_roots', () {
      final pins = {
        'prd-core': PackVersion.parse('1.2.3', file: 'f', key: 'k'),
      };
      const source = 'setup_migration/migrate_legacy_docs/write_project_files';

      test('$source: no agent file roots write no key', () {
        expect(configText(pins, agentFileRoots: const []), configText(pins));
      });

      test(
        '$source: the key follows packs and code_root, one entry a line',
        () {
          expect(
            configText(
              pins,
              codeRoot: 'stratum_ui',
              agentFileRoots: const ['../stratum_ui', '../other'],
            ),
            'packs:\n  prd-core: 1.2.3\n'
            'code_root: stratum_ui\n'
            'agent_file_roots:\n  - ../stratum_ui\n  - ../other\n',
          );
        },
      );

      test('$source: an entry YAML reads as another value is quoted', () {
        expect(
          configText(pins, agentFileRoots: const ['2024']),
          endsWith("agent_file_roots:\n  - '2024'\n"),
        );
      });

      for (final roots in [
        ['../stratum_ui'],
        ['../a', 'b/c', '2024', 'x #y'],
      ]) {
        test('$source: the config reader reads back $roots', () async {
          final root = await writeTree({
            '.specstone/config.yaml': configText(pins, agentFileRoots: roots),
          });

          expect(ProjectConfig.read(root).agentFileRoots, roots);
        });
      }
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
        "    header: 'Data integrity'\n"
        '  - id: token_efficiency\n'
        "    header: 'Token efficiency'\n",
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

    test('f06/us01/fr05/e04: an id a carried section holds is taken, so the '
        'override adds a section', () {
      final entry = gnfrOverride(['Safety!'], carriedIds: {'safety'})!;

      expect(entry.value, contains('id: safety_2\n'));
      expect(entry.value, isNot(contains('id: safety\n')));
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

    test('f06/us01/fr05/e04: free-text legacy headers round-trip through the '
        'gnfr override', () {
      const headers = [
        'Cost: low',
        'ความปลอดภัย',
        'Data integrity',
        'Data-integrity',
        'true',
        'a # b',
        "it's",
        '2024',
        '&anchor',
      ];

      final entry = gnfrOverride(headers)!;
      final set = TemplateResolver().resolveCarried(
        packNames: _packs,
        homeDirectory: null,
        projectLayers: parseOverrides({entry.key: entry.value}),
      );

      final sections = set.lookup('gnfr')!.sections;
      final ids = [for (final section in sections) section.id];
      expect(ids.toSet(), hasLength(ids.length));
      final merged = sections.map((section) => section.header);
      for (final header in headers) {
        expect(merged, contains(header));
      }
      expect(entry.value, contains('id: category_2\n'));
      expect(entry.value, contains("id: 'true'\n"));
      expect(entry.value, contains('id: data_integrity\n'));
      expect(entry.value, contains('id: data_integrity_2\n'));
    });

    test('f06/us01/fr05/e01: headers Cost, cost and Cost 2 get three distinct '
        'ids and keep three sections', () {
      final entry = gnfrOverride(['Cost', 'cost', 'Cost 2'])!;

      final set = TemplateResolver().resolveCarried(
        packNames: _packs,
        homeDirectory: null,
        projectLayers: parseOverrides({entry.key: entry.value}),
      );

      final sections = [
        for (final section in set.lookup('gnfr')!.sections)
          if (const ['Cost', 'cost', 'Cost 2'].contains(section.header))
            section,
      ];
      final ids = [for (final section in sections) section.id];
      expect(sections, hasLength(3));
      expect(ids.toSet(), hasLength(3));
    });

    test('f06/us01/fr05/e01: covers skips an empty Code path and quotes a '
        'path holding a colon', () {
      final rows = [
        const SpecMapRow(codePath: '', specPath: 'specs/a/', featureId: 'f01'),
        const SpecMapRow(
          codePath: 'lib/x: y/',
          specPath: 'specs/a/',
          featureId: 'f01',
        ),
        const SpecMapRow(codePath: '', specPath: 'specs/b/', featureId: 'f02'),
      ];

      final covers = coversOf('specs/a/', rows);

      expect(covers?.block, "covers:\n  - 'lib/x: y/'\n");
      expect(covers?.label, 'covers (1 path)');
      expect(coversOf('specs/b/', rows), isNull);
    });

    test('f06/us01/fr05/e01: covers quotes a path YAML reads as a number or '
        'a word', () {
      final rows = [
        for (final codePath in ['2024', 'true', 'null', '1.5'])
          SpecMapRow(codePath: codePath, specPath: 'specs/a/', featureId: 'f'),
      ];

      final covers = coversOf('specs/a/', rows);

      expect(
        covers?.block,
        "covers:\n  - '2024'\n  - 'true'\n  - 'null'\n  - '1.5'\n",
      );
    });

    test('f06/us01/fr05/e06: a project-layer singular doc type follows the '
        'four by DocPath', () {
      final set = TemplateResolver().resolveCarried(
        packNames: _packs,
        homeDirectory: null,
        projectLayers: parseOverrides({
          '.specstone/templates/extra.yaml':
              'id: extra\ndescription: Extra.\npath: prds/EXTRA.md\n',
        }),
      );

      expect(singularDocTypes(set).map((type) => type.path), [
        'prds/PROJECT.md',
        'prds/FEATURES.md',
        'prds/GNFR.md',
        'specs/TECH_STACK.md',
        'prds/EXTRA.md',
      ]);
    });

    test('f06/us01/fr05: parseOverrides reads only doc-type files, in code '
        'point order', () {
      final layers = parseOverrides({
        '.specstone/templates/zeta.yaml': 'path: z/{slug}.md\n',
        '.specstone/templates/pack.yaml': 'not: a doc type\n',
        '.specstone/templates/sub/inner.yaml': 'bad: key\n',
        '.specstone/templates/alpha.yaml': 'path: a/{slug}.md\n',
      });

      expect(layers.map((layer) => layer.docTypeId), ['alpha', 'zeta']);
    });
  });
}
