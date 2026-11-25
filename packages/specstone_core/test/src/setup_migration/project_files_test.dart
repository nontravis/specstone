import 'package:specstone_core/src/release_version.dart';
import 'package:specstone_core/src/setup_migration/project_files.dart';
import 'package:specstone_core/src/templates/code_target.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';

const _packs = ['prd-core', 'software-tech'];

void main() {
  group('project files', () {
    test('the config pins prd-core and software-tech at the '
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

      test('no agent file roots write no key', () {
        expect(configText(pins, agentFileRoots: const []), configText(pins));
      });

      test('the key follows packs and code_root, one entry a line', () {
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
      });

      for (final bad in ['', '/abs', 'C:/x', r'a\b']) {
        test('the entry "$bad" the reader refuses is an ArgumentError', () {
          expect(
            () => configText(pins, agentFileRoots: [bad]),
            throwsA(
              isA<ArgumentError>().having((e) => e.invalidValue, 'value', bad),
            ),
          );
        });
      }

      test('an entry YAML reads as another value is quoted', () {
        expect(
          configText(pins, agentFileRoots: const ['2024']),
          endsWith("agent_file_roots:\n  - '2024'\n"),
        );
      });

      for (final roots in [
        ['../stratum_ui'],
        ['../a', 'b/c', '2024', 'x #y'],
      ]) {
        test('the config reader reads back $roots', () async {
          final root = await writeTree({
            '.specstone/config.yaml': configText(pins, agentFileRoots: roots),
          });

          expect(ProjectConfig.read(root).agentFileRoots, roots);
        });
      }
    });

    group('configText agent_files_version', () {
      final pins = {
        'prd-core': PackVersion.parse('1.2.3', file: 'f', key: 'k'),
      };

      test('no Version writes no key', () {
        expect(configText(pins), isNot(contains('agent_files_version')));
      });

      test('the key ends the file, after agent_file_roots', () {
        expect(
          configText(
            pins,
            agentFileRoots: const ['../other'],
            agentFilesVersion: ReleaseVersion.tryParse('1.3.0'),
          ),
          'packs:\n  prd-core: 1.2.3\n'
          'agent_file_roots:\n  - ../other\n'
          'agent_files_version: 1.3.0\n',
        );
      });

      for (final version in ['1.3.0', '1.2.0-beta.1', '1.3.0-dev.39']) {
        test('the config reader reads back $version', () async {
          final root = await writeTree({
            '.specstone/config.yaml': configText(
              pins,
              agentFilesVersion: ReleaseVersion.tryParse(version),
            ),
          });

          expect(
            ProjectConfig.read(root).agentFilesVersion.toString(),
            version,
          );
        });
      }
    });

    group('configText targets', () {
      final pins = {
        'prd-core': PackVersion.parse('1.2.3', file: 'f', key: 'k'),
      };
      const targets = [
        CodeTarget('flutter', codeRoot: 'flutter_ws'),
        CodeTarget('jaspr', codeRoot: '../jaspr ws'),
      ];

      test('the map follows packs, one target a block, before '
          'the agent file roots', () {
        expect(
          configText(
            pins,
            targets: targets,
            agentFileRoots: const ['../jaspr'],
          ),
          'packs:\n  prd-core: 1.2.3\n'
          'targets:\n  flutter:\n    code_root: flutter_ws\n'
          '  jaspr:\n    code_root: ../jaspr ws\n'
          'agent_file_roots:\n  - ../jaspr\n',
        );
      });

      test('the config reader reads the map back', () async {
        final root = await writeTree({
          '.specstone/config.yaml': configText(pins, targets: targets),
        });

        expect(ProjectConfig.read(root).targets, targets);
      });

      for (final (label, call) in <(String, void Function())>[
        (
          'a code_root line',
          () => configText(pins, targets: targets, codeRoot: 'x'),
        ),
        (
          'a kept code_root key',
          () => configText(pins, targets: targets, keepCodeRootKey: true),
        ),
        (
          'an unnamed target',
          () => configText(
            pins,
            targets: const [CodeTarget(null, codeRoot: 'x')],
          ),
        ),
      ]) {
        test('targets beside $label is an ArgumentError', () {
          expect(call, throwsArgumentError);
        });
      }
    });

    test("the singular types' paths, one per target for a per-target type "
        'with two targets', () {
      final set = TemplateResolver().resolveCarried(
        packNames: _packs,
        homeDirectory: null,
      );

      final shared = singularLayoutPathsOf(set, twinNames: const []);
      final twins = singularLayoutPathsOf(set, twinNames: const ['app', 'web']);

      expect(shared, containsAll(['prds/GOAL.md', 'specs/TECH_STACK.md']));
      expect(
        twins,
        containsAll(['specs/app/TECH_STACK.md', 'specs/web/TECH_STACK.md']),
      );
      expect(twins, isNot(contains('specs/TECH_STACK.md')));
      expect(twins, contains('prds/GOAL.md'));
    });

    test("a project spec type's one path is a layout path too, though it "
        'gets no draft', () {
      final set = TemplateResolver().resolveCarried(
        packNames: _packs,
        homeDirectory: null,
      );

      expect(
        singularLayoutPathsOf(set, twinNames: const []),
        containsAll(['specs/SECURITY.md', 'specs/API.md']),
      );
      expect(
        singularDocTypes(set).map((type) => type.path),
        isNot(contains('specs/SECURITY.md')),
      );
    });

    test('a path is a singular layout path when it, or it under the docs '
        'folder, is in the set', () {
      const paths = {'prds/GOAL.md'};

      expect(isSingularLayoutPath('prds/GOAL.md', paths), isTrue);
      expect(isSingularLayoutPath('docs/prds/GOAL.md', paths), isTrue);
      expect(isSingularLayoutPath('../../GOAL.md', paths), isFalse);
      expect(
        isSingularLayoutPath('prds/features/f01_login/FEATURE.md', paths),
        isFalse,
      );
    });

    test('singular doc types order '
        'goal after project', () {
      final set = TemplateResolver().resolveCarried(
        packNames: _packs,
        homeDirectory: null,
      );

      expect(singularDocTypes(set).map((type) => type.path), [
        'prds/PROJECT.md',
        'prds/GOAL.md',
        'prds/GLOSSARY.md',
        'prds/FEATURES.md',
        'prds/GNFR.md',
        'specs/TECH_STACK.md',
      ]);
    });

    test('a project-layer singular doc type follows the '
        'five by DocPath', () {
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
        'prds/GOAL.md',
        'prds/GLOSSARY.md',
        'prds/FEATURES.md',
        'prds/GNFR.md',
        'specs/TECH_STACK.md',
        'prds/EXTRA.md',
      ]);
    });

    test('a singular doc type built on a per-feature type gets no '
        'draft', () {
      final set = TemplateResolver().resolveCarried(
        packNames: _packs,
        homeDirectory: null,
        projectLayers: parseOverrides({
          '.specstone/templates/extra.yaml':
              'id: extra\ndescription: Extra.\npath: prds/EXTRA.md\n',
          '.specstone/templates/edge_security.yaml':
              'id: edge_security\nextends: security\n'
              'path: specs/EDGE_SECURITY.md\nparent:\n',
        }),
      );

      expect(singularDocTypes(set).map((type) => type.path), [
        'prds/PROJECT.md',
        'prds/GOAL.md',
        'prds/GLOSSARY.md',
        'prds/FEATURES.md',
        'prds/GNFR.md',
        'specs/TECH_STACK.md',
        'prds/EXTRA.md',
      ]);
    });

    test('parseOverrides reads only doc-type files, in code '
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
