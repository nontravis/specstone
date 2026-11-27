import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:specstone_core/src/doc_model/path_pattern.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/generator_kinds.dart';
import 'package:specstone_core/src/templates/layer.dart';
import 'package:specstone_core/src/templates/layer_source.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pack_floors.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:specstone_core/src/version.dart';
import 'package:test/test.dart';

import '../../helpers/grouped_fixture.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';

const _configPath = '.specstone/config.yaml';
const _frozenX = 'prd-core/frozen/x.yaml';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

/// A project type no pack defines that derives its patterns from the groups.
const _areaIndexLayer =
    'id: area_index\n'
    'description: One index per group.\n'
    'path_from: feature_groups\n'
    'file: AREA.md\n';

PackVersion _version(String text) =>
    PackVersion.parse(text, file: 'test', key: 'version');

/// The shipped fixture: `prd-core` holds `feature`, `software-tech` holds
/// `architecture`.
Map<String, Uint8List> shipped({String prdCoreVersion = '1.1.0'}) => {
  'prd-core/pack.yaml': _bytes('name: prd-core\nversion: $prdCoreVersion\n'),
  'prd-core/feature.yaml': _bytes(
    'id: feature\ndescription: A feature\npath: '
    'features/f{nn}_{slug}/FEATURE.md\n',
  ),
  'software-tech/pack.yaml': _bytes('name: software-tech\nversion: 1.0.0\n'),
  'software-tech/architecture.yaml': _bytes(
    'id: architecture\ndescription: Architecture\npath: '
    'architecture/{slug}.md\n',
  ),
};

/// A [LayerFiles] holding no file.
final class _NoFiles implements LayerFiles {
  const new();

  @override
  bool exists(String layerRelativePath) => false;
}

/// True when an ancestor of the system temp folder holds a project config.
bool _tempHasConfigAncestor() {
  Directory? dir = Directory.systemTemp.absolute;
  while (dir != null) {
    if (File.fromUri(dir.uri.resolve(_configPath)).existsSync()) return true;
    final parent = dir.parent;
    dir = parent.path == dir.path ? null : parent;
  }
  return false;
}

/// Resolves [project] and [home] as trees and returns the fault it throws.
Future<TemplateFault> _resolveFault({
  required Map<String, String> project,
  Map<String, String> home = const {},
  Map<String, Uint8List>? shippedFiles,
}) async {
  final projectDir = await writeTree(project);
  final homeDir = await writeTree(home);
  final resolver = TemplateResolver(shippedFiles: shippedFiles ?? shipped());
  try {
    resolver.resolve(workingDirectory: projectDir, homeDirectory: homeDir);
  } on TemplateFault catch (fault) {
    return fault;
  }
  fail('resolve threw no fault');
}

void main() {
  group('TemplateResolver.resolve', () {
    test('an older shipped pin is pack_pin_older', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.0.0\n',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(
        shippedFiles: shipped(prdCoreVersion: '1.1.0'),
      );

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.packPinOlder)
              .having((f) => f.file, 'file', _configPath)
              .having((f) => f.key, 'key', 'packs.prd-core')
              .having(
                (f) => f.message,
                'message',
                allOf(
                  contains('1.0.0'),
                  contains('1.1.0'),
                  contains('specstone migrate --dry-run'),
                ),
              ),
        ),
      );
    });

    test('a pin below its floor is pack_pin_below_floor', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.0.0\n',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(
        shippedFiles: shipped(),
        floors: PackFloors({'prd-core': _version('1.1.0')}),
      );

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.packPinBelowFloor)
              .having((f) => f.file, 'file', _configPath)
              .having((f) => f.key, 'key', 'packs.prd-core')
              .having(
                (f) => f.message,
                'message',
                allOf(
                  contains('prd-core'),
                  contains('1.0.0'),
                  contains('1.1.0'),
                  contains(specstoneVersion),
                  contains('migrate the project with Specstone 2.0.x first'),
                ),
              ),
        ),
      );
    });

    test('a below-floor pin wins over a newer pin of a pack that sorts '
        'first', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 2.0.0\n  software-tech: 0.9.0\n',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(
        shippedFiles: shipped(),
        floors: PackFloors({'software-tech': _version('1.0.0')}),
      );

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.packPinBelowFloor)
              .having((f) => f.key, 'key', 'packs.software-tech'),
        ),
      );
    });

    test('requireAtFloor throws the first below-floor pin of its floors and '
        'passes a pin at its floor or a resolver with none', () {
      final floors = PackFloors({
        'prd-core': _version('1.1.0'),
        'software-tech': _version('1.0.0'),
      });
      final withFloors = TemplateResolver(
        shippedFiles: shipped(),
        floors: floors,
      );
      final pins = {
        'prd-core': _version('1.0.0'),
        'software-tech': _version('0.9.0'),
      };

      expect(
        () => withFloors.requireAtFloor(pins),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.packPinBelowFloor)
              .having((f) => f.key, 'key', 'packs.prd-core'),
        ),
      );
      expect(
        () => withFloors.requireAtFloor({'prd-core': _version('1.1.0')}),
        returnsNormally,
      );
      expect(
        () => TemplateResolver(shippedFiles: shipped()).requireAtFloor(pins),
        returnsNormally,
      );
    });

    test('a personal pack pin resolves against its home pack.yaml, '
        'floors set', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n  nont-software: 0.1.0\n',
      });
      final home = await writeTree({
        '.specstone/packs/nont-software/pack.yaml':
            'name: nont-software\nversion: 0.1.0\n',
      });
      final resolver = TemplateResolver(
        shippedFiles: shipped(),
        floors: PackFloors({'prd-core': _version('1.1.0')}),
      );

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      expect(merged.lookup('feature'), isNotNull);
    });

    test('equal pins resolve the listed packs', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n  software-tech: 1.0.0\n',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      expect(merged.lookup('feature'), isNotNull);
      expect(merged.lookup('architecture'), isNotNull);
    });

    test('a newer pin is pack_pin_newer', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 2.0.0\n',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.packPinNewer)
              .having((f) => f.file, 'file', _configPath)
              .having((f) => f.key, 'key', 'packs.prd-core')
              .having(
                (f) => f.message,
                'message',
                allOf(
                  contains('2.0.0'),
                  contains('1.1.0'),
                  contains('Upgrade Specstone'),
                ),
              ),
        ),
      );
    });

    test('an unlisted shipped pack never loads', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      expect(merged.lookup('feature'), isNotNull);
      expect(merged.lookup('architecture'), isNull);
    });

    test(
      'no project root loads every shipped pack',
      () async {
        final working = await writeTree({});
        final home = await writeTree({});
        final resolver = TemplateResolver(
          shippedFiles: shipped(prdCoreVersion: '9.9.9'),
        );

        final merged = resolver.resolve(
          workingDirectory: working,
          homeDirectory: home,
        );

        expect(merged.docTypes.map((docType) => docType.id), [
          'architecture',
          'feature',
        ]);
      },
      skip: _tempHasConfigAncestor()
          ? 'an ancestor of the system temp folder holds $_configPath'
          : false,
    );

    test('a missing personal pack is pack_not_found', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n  nont-software: 1.0.0\n',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.packNotFound)
              .having((f) => f.file, 'file', _configPath)
              .having((f) => f.key, 'key', 'packs.nont-software'),
        ),
      );
    });

    test('a null home makes a listed personal pack '
        'pack_not_found', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n  nont-software: 1.0.0\n',
      });
      final resolver = TemplateResolver(shippedFiles: shipped());

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: null),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.packNotFound)
              .having((f) => f.file, 'file', _configPath)
              .having((f) => f.key, 'key', 'packs.nont-software'),
        ),
      );
    });

    test('a null home still resolves a project that lists only '
        'shipped packs', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
      });
      final resolver = TemplateResolver(shippedFiles: shipped());

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: null,
      );

      expect(merged.docTypes.map((d) => d.id), ['feature']);
    });

    test(
      'a differing personal version is personal_pack_version_differs',
      () async {
        final project = await writeTree({
          _configPath: 'packs:\n  prd-core: 1.1.0\n  nont-software: 1.0.0\n',
        });
        final home = await writeTree({
          '.specstone/packs/nont-software/pack.yaml':
              'name: nont-software\nversion: 1.1.0\n',
        });
        final resolver = TemplateResolver(shippedFiles: shipped());

        expect(
          () =>
              resolver.resolve(workingDirectory: project, homeDirectory: home),
          throwsA(
            isA<TemplateFault>()
                .having(
                  (f) => f.code,
                  'code',
                  FaultCode.personalPackVersionDiffers,
                )
                .having((f) => f.file, 'file', _configPath)
                .having((f) => f.key, 'key', 'packs.nont-software')
                .having(
                  (f) => f.message,
                  'message',
                  allOf(contains('1.0.0'), contains('1.1.0')),
                ),
          ),
        );
      },
    );

    test('a pack.yaml name unequal to the folder is '
        'pack_name_mismatch', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n  nont-software: 1.0.0\n',
      });
      final home = await writeTree({
        '.specstone/packs/nont-software/pack.yaml':
            'name: nont-sw\nversion: 1.0.0\n',
      });
      final resolver = TemplateResolver(shippedFiles: shipped());

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.packNameMismatch)
              .having(
                (f) => f.file,
                'file',
                '~/.specstone/packs/nont-software/pack.yaml',
              )
              .having((f) => f.key, 'key', 'name'),
        ),
      );
    });

    test('an unlisted personal pack never loads', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
      });
      final home = await writeTree({
        '.specstone/packs/nont-extra/pack.yaml':
            'name: nont-extra\nversion: 1.0.0\n',
        '.specstone/packs/nont-extra/chip.yaml': 'description: Chip\n',
      });
      final resolver = TemplateResolver(shippedFiles: shipped());

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      expect(merged.lookup('chip'), isNull);
      expect(merged.lookup('feature'), isNotNull);
    });

    test('a listed personal pack adds its doc types with its pack', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n  nont-software: 1.0.0\n',
      });
      final home = await writeTree({
        '.specstone/packs/nont-software/pack.yaml':
            'name: nont-software\nversion: 1.0.0\n',
        '.specstone/packs/nont-software/runbook.yaml':
            'id: runbook\ndescription: Runbook\n'
            'path: ops/runbooks/{slug}/RUNBOOK.md\n',
      });
      final resolver = TemplateResolver(shippedFiles: shipped());

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      expect(merged.lookup('runbook')!.pack, 'nont-software');
      expect(merged.lookup('runbook')!.description, 'Runbook');
    });

    test('a personal pack reference to a nested file resolves '
        'against disk', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n  nont-software: 1.0.0\n',
      });
      final home = await writeTree({
        '.specstone/packs/nont-software/pack.yaml':
            'name: nont-software\nversion: 1.0.0\n',
        '.specstone/packs/nont-software/runbook.yaml': '''
id: runbook
description: Runbook
path: ops/runbooks/{slug}/RUNBOOK.md
reference:
  - title: H
    file: refs/handbook.md
''',
        '.specstone/packs/nont-software/refs/handbook.md': '# Handbook\n',
      });
      final resolver = TemplateResolver(shippedFiles: shipped());

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      expect(merged.lookup('runbook')!.reference!.single.file, isNotNull);
    });

    test('a shipped pack reference to a nested file resolves '
        'against the map', () async {
      final files = shipped()
        ..['prd-core/refs/handbook.md'] = _bytes('# Handbook\n');
      files['prd-core/feature.yaml'] = _bytes('''
id: feature
description: A feature
path: features/f{nn}_{slug}/FEATURE.md
reference:
  - title: H
    file: refs/handbook.md
''');
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: files);

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      expect(merged.lookup('feature')!.reference!.single.file, isNotNull);
    });

    test('a template fault in the project layer is thrown', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/feature.yaml': 'bogus: x\n',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.unknownKey)
              .having(
                (f) => f.file,
                'file',
                '.specstone/templates/feature.yaml',
              ),
        ),
      );
    });

    test('a second resolve reads the new config, no cache', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      final first = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );
      expect(first.lookup('feature'), isNotNull);

      await File.fromUri(project.uri.resolve(_configPath))
          .writeAsString('packs:\n  prd-core: 2.0.0\n');

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>().having(
            (f) => f.code,
            'code',
            FaultCode.packPinNewer,
          ),
        ),
      );
    });

    test('two faulty project templates fault the first by code '
        'point', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/a.yaml': 'bogus: x\n',
        '.specstone/templates/b.yaml': 'bogus: x\n',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.unknownKey)
              .having((f) => f.file, 'file', '.specstone/templates/a.yaml'),
        ),
      );
    });

    test('non-doc-type project files are ignored as doc types', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/notes.md': 'notes\n',
        '.specstone/templates/refs/x.yaml': 'x\n',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      expect(merged.lookup('notes'), isNull);
      expect(merged.lookup('x'), isNull);
      expect(merged.lookup('refs'), isNull);
    });

    test('a project reference to a missing file is '
        'reference_file_missing', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/feature.yaml': '''
description: Project feature
reference:
  - title: H
    file: refs/handbook.md
  - title: N
    file: refs/sub/none.md
''',
        '.specstone/templates/refs/handbook.md': '# Handbook\n',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.referenceFileMissing)
              .having(
                (f) => f.file,
                'file',
                '.specstone/templates/feature.yaml',
              )
              .having(
                (f) => f.message,
                'message',
                contains('refs/sub/none.md'),
              ),
        ),
      );
    });

    test('a shipped pin fault wins over a bad doc-type file '
        'in the same pack', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.0.0\n',
      });
      final home = await writeTree({});
      final files = shipped(prdCoreVersion: '1.1.0')
        ..['prd-core/feature.yaml'] = _bytes('bogus: x\n');
      final resolver = TemplateResolver(shippedFiles: files);

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.packPinOlder)
              .having((f) => f.key, 'key', 'packs.prd-core'),
        ),
      );
    });

    test('a personal pack_name_mismatch wins over a bad '
        'doc-type file', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n  nont-software: 1.0.0\n',
      });
      final home = await writeTree({
        '.specstone/packs/nont-software/pack.yaml':
            'name: nont-sw\nversion: 1.0.0\n',
        '.specstone/packs/nont-software/runbook.yaml': 'bogus: x\n',
      });
      final resolver = TemplateResolver(shippedFiles: shipped());

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.packNameMismatch)
              .having(
                (f) => f.file,
                'file',
                '~/.specstone/packs/nont-software/pack.yaml',
              ),
        ),
      );
    });

    test('a pin fault wins over a doc-type fault in the other '
        'pack whatever the YAML order', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  software-tech: 1.0.0\n  prd-core: 2.0.0\n',
      });
      final home = await writeTree({});
      final files = shipped()
        ..['software-tech/architecture.yaml'] = _bytes('bogus: x\n');
      final resolver = TemplateResolver(shippedFiles: files);

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.packPinNewer)
              .having((f) => f.key, 'key', 'packs.prd-core'),
        ),
      );
    });

    test('an absent personal pack.yaml is missing_key', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n  nont-software: 1.0.0\n',
      });
      final home = await writeTree({
        '.specstone/packs/nont-software/runbook.yaml': 'description: R\n',
      });
      final resolver = TemplateResolver(shippedFiles: shipped());

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.missingKey)
              .having(
                (f) => f.file,
                'file',
                '~/.specstone/packs/nont-software/pack.yaml',
              )
              .having((f) => f.key, 'key', 'name'),
        ),
      );
    });

    test('a personal pack and a shipped pack with one doc type id, no extends, '
        'are doc_type_duplicate', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n  nont-x: 1.0.0\n',
      });
      final home = await writeTree({
        '.specstone/packs/nont-x/pack.yaml': 'name: nont-x\nversion: 1.0.0\n',
        '.specstone/packs/nont-x/feature.yaml': 'description: Mine\n',
      });
      final resolver = TemplateResolver(shippedFiles: shipped());

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.docTypeDuplicate)
              .having(
                (f) => f.file,
                'file',
                '~/.specstone/packs/nont-x/feature.yaml',
              )
              .having((f) => f.relatedFiles, 'relatedFiles', [
                'packs/prd-core/feature.yaml',
              ])
              .having((f) => f.message, 'message', contains('feature')),
        ),
      );
    });

    test('an extending personal pack layers its same-id doc type over the '
        'shipped one', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n  nont-x: 1.0.0\n',
      });
      final home = await writeTree({
        '.specstone/packs/nont-x/pack.yaml':
            'name: nont-x\nversion: 1.0.0\nextends: prd-core\n',
        '.specstone/packs/nont-x/feature.yaml': '''
description: Mine
sections:
  - id: goal
    description: What the personal pack wants
''',
      });
      final files = shipped()
        ..['prd-core/feature.yaml'] = _bytes('''
id: feature
description: A feature
path: features/f{nn}_{slug}/FEATURE.md
sections:
  - id: goal
    header: Feature goal
''');
      final resolver = TemplateResolver(shippedFiles: files);

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      final feature = merged.lookup('feature')!;
      expect(feature.description, 'Mine');
      expect(feature.pack, 'prd-core');
      final goal = feature.sections.singleWhere((s) => s.id == 'goal');
      expect(goal.description, 'What the personal pack wants');
      expect(feature.files, [
        'packs/prd-core/feature.yaml',
        '~/.specstone/packs/nont-x/feature.yaml',
      ]);
    });

    test('a chain three packs deep layers top down', () async {
      final project = await writeTree({
        _configPath:
            'packs:\n'
            '  prd-core: 1.1.0\n'
            '  software-tech: 1.0.0\n'
            '  nont-software: 1.0.0\n'
            '  nont-flutter: 1.0.0\n',
      });
      final home = await writeTree({
        '.specstone/packs/nont-software/pack.yaml':
            'name: nont-software\nversion: 1.0.0\nextends: software-tech\n',
        '.specstone/packs/nont-software/runbook.yaml':
            'id: runbook\ndescription: Runbook\n'
            'path: ops/runbooks/{slug}/RUNBOOK.md\n',
        '.specstone/packs/nont-software/architecture.yaml':
            'description: Software architecture\nlint:\n  max_lines: 300\n',
        '.specstone/packs/nont-flutter/pack.yaml':
            'name: nont-flutter\nversion: 1.0.0\nextends: nont-software\n',
        '.specstone/packs/nont-flutter/architecture.yaml':
            'description: Flutter architecture\n',
      });
      final files = shipped()
        ..['software-tech/architecture.yaml'] = _bytes(
          'id: architecture\ndescription: Architecture\n'
          'path: architecture/{slug}.md\n',
        );
      final resolver = TemplateResolver(shippedFiles: files);

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      expect(merged.lookup('runbook')!.description, 'Runbook');
      final architecture = merged.lookup('architecture')!;
      expect(architecture.description, 'Flutter architecture');
      expect(architecture.lint.maxLines, 300);
      expect(architecture.files, [
        'packs/software-tech/architecture.yaml',
        '~/.specstone/packs/nont-software/architecture.yaml',
        '~/.specstone/packs/nont-flutter/architecture.yaml',
      ]);
    });

    test('the project layer wins over the '
        'personal pack', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n  nont-x: 1.0.0\n',
        '.specstone/templates/feature.yaml': '''
description: Project feature
sections:
  - id: goal
    description: What the project wants
''',
      });
      final home = await writeTree({
        '.specstone/packs/nont-x/pack.yaml':
            'name: nont-x\nversion: 1.0.0\nextends: prd-core\n',
        '.specstone/packs/nont-x/feature.yaml': '''
description: Mine
sections:
  - id: goal
    description: What the personal pack wants
''',
      });
      final files = shipped()
        ..['prd-core/feature.yaml'] = _bytes('''
id: feature
description: A feature
path: features/f{nn}_{slug}/FEATURE.md
sections:
  - id: goal
    header: Feature goal
''');
      final resolver = TemplateResolver(shippedFiles: files);

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      final feature = merged.lookup('feature')!;
      expect(feature.description, 'Project feature');
      final goal = feature.sections.singleWhere((s) => s.id == 'goal');
      expect(goal.description, 'What the project wants');
    });

    test('two personal packs extending one pack are '
        'personal_pack_conflict', () async {
      final project = await writeTree({
        _configPath:
            'packs:\n  prd-core: 1.1.0\n  nont-a: 1.0.0\n'
            '  nont-b: 1.0.0\n',
      });
      final home = await writeTree({
        '.specstone/packs/nont-a/pack.yaml':
            'name: nont-a\nversion: 1.0.0\nextends: prd-core\n',
        '.specstone/packs/nont-b/pack.yaml':
            'name: nont-b\nversion: 1.0.0\nextends: prd-core\n',
      });
      final resolver = TemplateResolver(shippedFiles: shipped());

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.personalPackConflict)
              .having((f) => f.file, 'file', _configPath)
              .having((f) => f.key, 'key', 'packs'),
        ),
      );
    });

    test('an extends naming no loaded pack is '
        'extends_target_unknown', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n  nont-a: 1.0.0\n',
      });
      final home = await writeTree({
        '.specstone/packs/nont-a/pack.yaml':
            'name: nont-a\nversion: 1.0.0\nextends: missing-pack\n',
      });
      final resolver = TemplateResolver(shippedFiles: shipped());

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.extendsTargetUnknown)
              .having(
                (f) => f.file,
                'file',
                '~/.specstone/packs/nont-a/pack.yaml',
              )
              .having((f) => f.key, 'key', 'extends'),
        ),
      );
    });

    test('a pack chain back to its start is '
        'extends_cycle', () async {
      final project = await writeTree({
        _configPath:
            'packs:\n  prd-core: 1.1.0\n  nont-a: 1.0.0\n  nont-b: 1.0.0\n',
      });
      final home = await writeTree({
        '.specstone/packs/nont-a/pack.yaml':
            'name: nont-a\nversion: 1.0.0\nextends: nont-b\n',
        '.specstone/packs/nont-b/pack.yaml':
            'name: nont-b\nversion: 1.0.0\nextends: nont-a\n',
      });
      final resolver = TemplateResolver(shippedFiles: shipped());

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.extendsCycle)
              .having(
                (f) => f.file,
                'file',
                '~/.specstone/packs/nont-b/pack.yaml',
              )
              .having((f) => f.relatedFiles, 'relatedFiles', [
                '~/.specstone/packs/nont-a/pack.yaml',
              ]),
        ),
      );
    });

    test('a project template with a '
        'pack-defined id is an override, not a duplicate', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/feature.yaml': 'description: Project feature\n',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      expect(merged.lookup('feature')!.description, 'Project feature');
    });

    test('a generators kind no one registers is unknown_value', () async {
      const template = '''
id: note
description: A note
path: prds/notes/{slug}/NOTE.md
''';
      final home = await writeTree({});
      final bad = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/note.yaml':
            '${template}generators: [journey_map]\n',
      });
      final resolver = TemplateResolver(
        shippedFiles: shipped(),
        generatorKinds: {...shippedGeneratorKinds, 'note_toc'},
      );

      expect(
        () => resolver.resolve(workingDirectory: bad, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.unknownValue)
              .having((f) => f.file, 'file', '.specstone/templates/note.yaml')
              .having((f) => f.key, 'key', 'generators')
              .having((f) => f.message, 'message', contains('journey_map')),
        ),
      );

      final good = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/note.yaml': '${template}generators: [note_toc]\n',
        '.specstone/templates/memo.yaml':
            'id: memo\ndescription: A memo\npath: memos/{slug}.md\n',
      });
      final merged = resolver.resolve(
        workingDirectory: good,
        homeDirectory: home,
      );
      expect(merged.lookup('note')!.generators, ['note_toc']);
      expect(merged.lookup('memo')!.generators, isNull);
      expect(merged.lookup('memo')!.listedGenerators, isEmpty);
    });

    group('leftover_homes', () {
      const personalFile = '~/.specstone/packs/nont-x/pack.yaml';

      Future<MergedSet> resolveWith(String entries) async =>
          TemplateResolver(shippedFiles: shipped()).resolve(
            workingDirectory: await writeTree({
              _configPath: 'packs:\n  prd-core: 1.1.0\n  nont-x: 1.0.0\n',
            }),
            homeDirectory: await writeTree({
              '.specstone/packs/nont-x/pack.yaml':
                  'name: nont-x\nversion: 1.0.0\nextends: prd-core\n'
                  'leftover_homes:\n$entries',
            }),
          );

      TypeMatcher<TemplateFault> unknownAt(String key) => isA<TemplateFault>()
          .having((f) => f.code, 'code', FaultCode.unknownValue)
          .having((f) => f.file, 'file', personalFile)
          .having((f) => f.key, 'key', key);

      test('a leftover_homes to type the merged set lacks is unknown_value '
          'naming the file', () async {
        await expectLater(
          resolveWith('  - path: notes/{slug}.md\n    to: [fr]\n    home: x\n'),
          throwsA(unknownAt('leftover_homes[0].to')),
        );
      });

      test('a leftover_homes doc_types type the merged set lacks is '
          'unknown_value', () async {
        await expectLater(
          resolveWith(
            '  - doc_types: [fr]\n'
            '    section: {id: goal, header: Goal}\n'
            '    to: [feature]\n'
            '    home: x\n',
          ),
          throwsA(unknownAt('leftover_homes[0].doc_types')),
        );
      });

      test('a leftover_homes to type of a pack below it in the chain '
          'resolves', () async {
        final merged = await resolveWith(
          '  - doc_types: [feature]\n'
          '    section: {id: goal, header: Goal}\n'
          '    to: [feature]\n'
          '    home: x\n',
        );

        expect(merged.leftoverHomes, hasLength(1));
        expect(merged.leftoverHomes.single.to, ['feature']);
        expect(merged.leftoverHomes.single.home, 'x');
      });

      Future<MergedSet> resolveShippedWith(String entries) async {
        final shippedFiles = shipped()
          ..['software-tech/pack.yaml'] = _bytes(
            'name: software-tech\nversion: 1.0.0\nleftover_homes:\n$entries',
          );
        return TemplateResolver(shippedFiles: shippedFiles).resolve(
          workingDirectory: await writeTree({
            _configPath: 'packs:\n  prd-core: 1.1.0\n  software-tech: 1.0.0\n',
          }),
          homeDirectory: await writeTree({}),
        );
      }

      test('a shipped pack entry whose to type the merged set lacks loads '
          'and gives no leftover home', () async {
        final merged = await resolveShippedWith(
          '  - doc_types: [architecture]\n'
          '    section: {id: goal, header: Goal}\n'
          '    to: [glossary]\n'
          '    home: x\n'
          '  - doc_types: [architecture]\n'
          '    section: {id: aim, header: Aim}\n'
          '    to: [feature]\n'
          '    home: y\n',
        );

        expect(merged.leftoverForSection('architecture', 'Goal'), isNull);
        expect(merged.leftoverForSection('architecture', 'Aim')!.home, 'y');
      });

      test('a shipped pack entry whose doc_types type the merged set lacks '
          'loads and gives no leftover home', () async {
        final merged = await resolveShippedWith(
          '  - doc_types: [gnfr]\n'
          '    section: {id: goal, header: Goal}\n'
          '    to: [feature]\n'
          '    home: x\n',
        );

        expect(merged.leftoverHomes, isEmpty);
      });
    });

    group('a bullet_lines step', () {
      Map<String, Uint8List> files({
        String docType = 'feature',
        String section = 'goal',
      }) => {
        ...shipped(),
        'prd-core/pack.yaml': _bytes(
          'name: prd-core\nversion: 1.1.0\nmigrations:\n'
          '  - from: 1.0.0\n    steps:\n'
          '      - bullet_lines: {doc_type: $docType, section: $section,'
          " prefixes: ['**Serves:**']}\n",
        ),
        'prd-core/feature.yaml': _bytes(
          'id: feature\ndescription: A feature\n'
          'path: features/f{nn}_{slug}/FEATURE.md\n'
          'sections:\n  - id: goal\n    header: Goal\n',
        ),
      };

      Future<MergedSet> resolveWith(
        Map<String, Uint8List> shippedFiles, {
        Map<String, String> project = const {},
      }) async => TemplateResolver(shippedFiles: shippedFiles).resolve(
        workingDirectory: await writeTree({
          _configPath: 'packs:\n  prd-core: 1.1.0\n',
          ...project,
        }),
        homeDirectory: await writeTree({}),
      );

      TypeMatcher<TemplateFault> unknownAt(String key) => isA<TemplateFault>()
          .having((f) => f.code, 'code', FaultCode.unknownValue)
          .having(
            (f) => f.code.exitStatus,
            'exit',
            FaultCode.unknownValue.exitStatus,
          )
          .having((f) => f.file, 'file', 'packs/prd-core/pack.yaml')
          .having(
            (f) => f.key,
            'key',
            'migrations[0].steps[0].bullet_lines.$key',
          );

      test('naming a doc type no layer defines is unknown_value', () async {
        await expectLater(
          resolveWith(files(docType: 'featur')),
          throwsA(unknownAt('doc_type')),
        );
        expect(await resolveWith(files()), isA<MergedSet>());
      });

      test('naming a section no layer of the doc type defines is '
          'unknown_value', () async {
        await expectLater(
          resolveWith(files(section: 'goall')),
          throwsA(unknownAt('section')),
        );
      });

      test('naming a section a project layer disables still loads', () async {
        final merged = await resolveWith(
          files(),
          project: {
            '.specstone/templates/feature.yaml':
                'sections:\n  - id: goal\n    disabled: true\n',
          },
        );

        expect(merged.lookup('feature'), isNotNull);
      });
    });

    test('a regenerate generators kind no one registers is unknown_value '
        'at that key', () async {
      Map<String, Uint8List> files(String generators) => {
        ...shipped(),
        'prd-core/pack.yaml': _bytes(
          'name: prd-core\nversion: 1.1.0\nmigrations:\n'
          '  - from: 1.0.0\n    steps:\n'
          '      - regenerate: {generators: $generators}\n',
        ),
      };
      Future<MergedSet> resolveWith(String generators) async =>
          TemplateResolver(shippedFiles: files(generators)).resolve(
            workingDirectory: await writeTree({
              _configPath: 'packs:\n  prd-core: 1.1.0\n',
            }),
            homeDirectory: await writeTree({}),
          );

      await expectLater(
        resolveWith('[feature_catalog, journey_map]'),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.unknownValue)
              .having((f) => f.file, 'file', 'packs/prd-core/pack.yaml')
              .having(
                (f) => f.key,
                'key',
                'migrations[0].steps[0].regenerate.generators',
              ),
        ),
      );
      expect(await resolveWith('[feature_catalog]'), isA<MergedSet>());
    });

    group('a mark_retrim step', () {
      Map<String, Uint8List> files({
        String docTypes = '[feature]',
        String sections = '[goal]',
        Map<String, String> more = const {},
      }) => {
        ...shipped(),
        'prd-core/pack.yaml': _bytes(
          'name: prd-core\nversion: 1.1.0\nmigrations:\n'
          '  - from: 1.0.0\n    steps:\n'
          '      - mark_retrim: {doc_types: $docTypes,'
          ' sections: $sections}\n',
        ),
        'prd-core/feature.yaml': _bytes(
          'id: feature\ndescription: A feature\n'
          'path: features/f{nn}_{slug}/FEATURE.md\n'
          'sections:\n  - id: goal\n    header: Goal\n',
        ),
        for (final MapEntry(:key, :value) in more.entries) key: _bytes(value),
      };

      Future<MergedSet> resolveWith(
        Map<String, Uint8List> shippedFiles, {
        Map<String, String> project = const {},
      }) async => TemplateResolver(shippedFiles: shippedFiles).resolve(
        workingDirectory: await writeTree({
          _configPath: 'packs:\n  prd-core: 1.1.0\n',
          ...project,
        }),
        homeDirectory: await writeTree({}),
      );

      test('a mark_retrim id outside the merged set is refused at its '
          'index', () async {
        for (final (docTypes, sections, key) in [
          ('[feature, featur]', '[goal]', 'doc_types[1]'),
          ('[feature]', '[goall]', 'sections[0]'),
        ]) {
          await expectLater(
            resolveWith(files(docTypes: docTypes, sections: sections)),
            throwsA(
              isA<TemplateFault>()
                  .having((f) => f.code, 'code', FaultCode.unknownValue)
                  .having(
                    (f) => f.code.exitStatus,
                    'exit',
                    FaultCode.unknownValue.exitStatus,
                  )
                  .having((f) => f.file, 'file', 'packs/prd-core/pack.yaml')
                  .having(
                    (f) => f.key,
                    'key',
                    'migrations[0].steps[0].mark_retrim.$key',
                  ),
            ),
            reason: key,
          );
        }
        expect(await resolveWith(files()), isA<MergedSet>());
      });

      test(
        'a mark_retrim section a later layer disables still loads',
        () async {
          final merged = await resolveWith(
            files(),
            project: {
              '.specstone/templates/feature.yaml':
                  'sections:\n  - id: goal\n    disabled: true\n',
            },
          );

          expect(merged.lookup('feature'), isNotNull);
        },
      );

      test('a mark_retrim doc type finds its sections through '
          'extends', () async {
        final merged = await resolveWith(
          files(
            docTypes: '[saga]',
            more: {
              'prd-core/saga.yaml':
                  'id: saga\nextends: feature\npath: sagas/{slug}/SAGA.md\n',
            },
          ),
        );

        expect(merged.lookup('saga'), isNotNull);
      });
    });

    group('drop_section targets', () {
      Map<String, Uint8List> files({
        String docTypes = '[feature]',
        String sectionId = 'goal',
        Map<String, String> more = const {},
      }) => {
        ...shipped(),
        'prd-core/pack.yaml': _bytes(
          'name: prd-core\nversion: 1.1.0\nmigrations:\n'
          '  - from: 1.0.0\n    steps:\n'
          '      - drop_section: {doc_types: $docTypes,'
          ' section: {id: $sectionId, header: Goal}}\n',
        ),
        'prd-core/feature.yaml': _bytes(
          'id: feature\ndescription: A feature\n'
          'path: features/f{nn}_{slug}/FEATURE.md\n'
          'sections:\n  - id: goal\n    header: Goal\n',
        ),
        for (final MapEntry(:key, :value) in more.entries) key: _bytes(value),
      };

      Future<MergedSet> resolveWith(
        Map<String, Uint8List> shippedFiles,
      ) async => TemplateResolver(shippedFiles: shippedFiles).resolve(
        workingDirectory: await writeTree({
          _configPath: 'packs:\n  prd-core: 1.1.0\n',
        }),
        homeDirectory: await writeTree({}),
      );

      TypeMatcher<TemplateFault> unknownAt(String key, {String? message}) =>
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.unknownValue)
              .having((f) => f.file, 'file', 'packs/prd-core/pack.yaml')
              .having(
                (f) => f.key,
                'key',
                'migrations[0].steps[0].drop_section.$key',
              )
              .having(
                (f) => f.message,
                'message',
                message == null ? isNotEmpty : contains(message),
              );

      test('drop_section of an id its own pack still defines refuses the '
          'load', () async {
        await expectLater(
          resolveWith(files()),
          throwsA(
            unknownAt(
              'section',
              message: 'drop_section names a section the pack defines: goal',
            ),
          ),
        );
      });

      test('drop_section of an id its own pack only disables loads', () async {
        final merged = await resolveWith(
          files(
            docTypes: '[saga]',
            more: {
              'prd-core/saga.yaml':
                  'id: saga\nextends: feature\npath: sagas/{slug}/SAGA.md\n'
                  'sections:\n  - id: goal\n    disabled: true\n',
            },
          ),
        );

        expect(merged.lookup('saga'), isNotNull);
      });

      test('drop_section with empty or unknown doc_types refuses at '
          'doc_types', () async {
        for (final docTypes in ['[]', '[featur]', '[feature, featur]']) {
          await expectLater(
            resolveWith(files(docTypes: docTypes, sectionId: 'notes')),
            throwsA(unknownAt('doc_types')),
            reason: docTypes,
          );
        }
        expect(await resolveWith(files(sectionId: 'notes')), isA<MergedSet>());
        final folded = files(sectionId: 'notes');
        folded['prd-core/pack.yaml'] = _bytes(
          'name: prd-core\nversion: 1.1.0\nmigrations:\n'
          '  - from: 1.0.0\n    steps:\n'
          '      - drop_section: {doc_types: [x],'
          ' section: {id: notes, header: Notes}}\n'
          '      - merge_doc: {from: {id: x, path: specs/X.md}, to: feature,'
          ' sections: [{from: {id: catalog, header: Catalog}, to: goal}]}\n',
        );
        folded[_frozenX] = _bytes(
          'id: x\ndescription: An x\npath: specs/X.md\n'
          'sections:\n  - id: notes\n    header: Notes\n',
        );
        expect(await resolveWith(folded), isA<MergedSet>());
      });
    });

    group('a drop_doc_type step', () {
      Map<String, Uint8List> files({required String id}) => {
        ...shipped(),
        'prd-core/pack.yaml': _bytes(
          'name: prd-core\nversion: 1.1.0\nmigrations:\n'
          '  - from: 1.0.0\n    steps:\n'
          '      - drop_doc_type: {id: $id, path: "topics/{slug}.md"}\n',
        ),
        'prd-core/feature.yaml': _bytes(
          'id: feature\ndescription: A feature\n'
          'path: features/f{nn}_{slug}/FEATURE.md\n'
          'sections:\n  - id: goal\n    header: Goal\n',
        ),
      };

      Future<MergedSet> resolveWith(
        Map<String, Uint8List> shippedFiles,
      ) async => TemplateResolver(shippedFiles: shippedFiles).resolve(
        workingDirectory: await writeTree({
          _configPath: 'packs:\n  prd-core: 1.1.0\n',
        }),
        homeDirectory: await writeTree({}),
      );

      test('drop_doc_type of an id its own pack defines refuses the '
          'load', () async {
        await expectLater(
          resolveWith(files(id: 'feature')),
          throwsA(
            isA<TemplateFault>()
                .having((f) => f.code, 'code', FaultCode.unknownValue)
                .having((f) => f.file, 'file', 'packs/prd-core/pack.yaml')
                .having(
                  (f) => f.key,
                  'key',
                  'migrations[0].steps[0].drop_doc_type.id',
                )
                .having(
                  (f) => f.message,
                  'message',
                  'drop_doc_type names a doc type the pack defines: feature',
                ),
          ),
        );
      });

      test('drop_doc_type of an id no layer defines loads', () async {
        final merged = await resolveWith(files(id: 'topic'));

        expect(merged.lookup('feature'), isNotNull);
        expect(merged.lookup('topic'), isNull);
      });

      test('a pathless project layer file of the dropped doc type is kept '
          'beside the step and never loads as a doc type', () async {
        final merged = TemplateResolver(shippedFiles: files(id: 'topic'))
            .resolve(
              workingDirectory: await writeTree({
                _configPath: 'packs:\n  prd-core: 1.1.0\n',
                '.specstone/templates/topic.yaml':
                    'sections: [{id: gone, header: Gone}]\n',
              }),
              homeDirectory: await writeTree({}),
            );

        expect(merged.lookup('topic'), isNull);
        expect(merged.docTypes.map((type) => type.id), ['feature']);
      });
    });

    group('an earlier step on a doc type a later merge_doc folds', () {
      const steps =
          '      - mark_retrim: {doc_types: [x], sections: [goal]}\n'
          '      - bullet_lines: {doc_type: x, section: goal, prefixes: [A]}\n';
      const merge =
          '      - merge_doc: {from: {id: x, path: specs/X.md}, to: feature,'
          ' sections: [{from: {id: catalog, header: Catalog}, to: goal}]}\n';

      Map<String, Uint8List> files({required String tail}) => {
        ...shipped(),
        'prd-core/pack.yaml': _bytes(
          'name: prd-core\nversion: 1.1.0\nmigrations:\n'
          '  - from: 1.0.0\n    steps:\n$steps$tail',
        ),
        'prd-core/feature.yaml': _bytes(
          'id: feature\ndescription: A feature\n'
          'path: features/f{nn}_{slug}/FEATURE.md\n'
          'sections:\n  - id: goal\n    header: Goal\n',
        ),
        _frozenX: _bytes(
          'id: x\ndescription: An x\npath: specs/X.md\n'
          'sections:\n  - id: goal\n    header: Goal\n',
        ),
      };

      Future<MergedSet> resolveWith(
        Map<String, Uint8List> shippedFiles,
      ) async => TemplateResolver(shippedFiles: shippedFiles).resolve(
        workingDirectory: await writeTree({
          _configPath: 'packs:\n  prd-core: 1.1.0\n',
        }),
        homeDirectory: await writeTree({}),
      );

      test('mark_retrim and bullet_lines on x load '
          'before a merge_doc from x', () async {
        final merged = await resolveWith(files(tail: merge));

        expect(merged.lookup('x'), isNull);
        expect(merged.foldedDocTypes, {'x': 'feature'});
      });

      for (final (:name, :hasFrozen, :outcome) in [
        (name: 'loads', hasFrozen: true, outcome: returnsNormally),
        (
          name: 'with no frozen/x.yaml refuses missing_key at that file',
          hasFrozen: false,
          outcome: throwsA(
            isA<TemplateFault>()
                .having((f) => f.code, 'code', FaultCode.missingKey)
                .having((f) => f.file, 'file', 'packs/$_frozenX'),
          ),
        ),
      ]) {
        test('steps on x in an entry listed after the later-from entry whose '
            'merge_doc folds x read in from order: the pack $name', () async {
          final bytes = files(tail: '');
          bytes['prd-core/pack.yaml'] = _bytes(
            'name: prd-core\nversion: 1.2.0\nmigrations:\n'
            '  - from: 1.1.0\n    steps:\n$merge'
            '  - from: 1.0.0\n    steps:\n$steps',
          );
          if (!hasFrozen) bytes.remove(_frozenX);
          final project = await writeTree({
            _configPath: 'packs:\n  prd-core: 1.2.0\n',
          });
          final home = await writeTree({});

          expect(
            () =>
                TemplateResolver(shippedFiles: bytes)
                    .resolve(workingDirectory: project, homeDirectory: home),
            outcome,
          );
        });
      }

      test('the steps on x with no frozen/x.yaml in the pack refuse '
          'missing_key at that file', () async {
        final bytes = files(tail: merge)..remove(_frozenX);

        await expectLater(
          resolveWith(bytes),
          throwsA(
            isA<TemplateFault>()
                .having((f) => f.code, 'code', FaultCode.missingKey)
                .having((f) => f.file, 'file', 'packs/$_frozenX')
                .having((f) => f.key, 'key', 'id'),
          ),
        );
      });

      test('the same steps with no later merge_doc from x still '
          'refuse', () async {
        await expectLater(
          resolveWith(files(tail: '')),
          throwsA(
            isA<TemplateFault>()
                .having((f) => f.code, 'code', FaultCode.unknownValue)
                .having(
                  (f) => f.key,
                  'key',
                  'migrations[0].steps[1].bullet_lines.doc_type',
                ),
          ),
        );
      });

      test('a merge_doc from x placed before the steps does not exempt '
          'them', () async {
        final bytes = files(tail: '');
        bytes['prd-core/pack.yaml'] = _bytes(
          'name: prd-core\nversion: 1.1.0\nmigrations:\n'
          '  - from: 1.0.0\n    steps:\n$merge$steps',
        );

        await expectLater(
          resolveWith(bytes),
          throwsA(
            isA<TemplateFault>()
                .having((f) => f.code, 'code', FaultCode.unknownValue)
                .having(
                  (f) => f.key,
                  'key',
                  'migrations[0].steps[2].bullet_lines.doc_type',
                ),
          ),
        );
      });
    });

    group('merge_doc targets', () {
      Map<String, Uint8List> files({
        String from = 'error',
        String fromPath = 'specs/ERROR.md',
        String to = 'feature',
        String toSection = 'goal',
      }) => {
        ...shipped(),
        'prd-core/pack.yaml': _bytes(
          'name: prd-core\nversion: 1.1.0\nmigrations:\n'
          '  - from: 1.0.0\n    steps:\n'
          '      - merge_doc: {from: {id: $from, path: $fromPath},'
          ' to: $to, sections: [{from: {id: catalog, header: Catalog},'
          ' to: $toSection}]}\n',
        ),
        'prd-core/feature.yaml': _bytes(
          'id: feature\ndescription: A feature\n'
          'path: features/f{nn}_{slug}/FEATURE.md\n'
          'sections:\n  - id: goal\n    header: Goal\n',
        ),
      };

      Future<MergedSet> resolveWith(
        Map<String, Uint8List> shippedFiles,
      ) async => TemplateResolver(shippedFiles: shippedFiles).resolve(
        workingDirectory: await writeTree({
          _configPath: 'packs:\n  prd-core: 1.1.0\n',
        }),
        homeDirectory: await writeTree({}),
      );

      TypeMatcher<TemplateFault> unknownAt(String key) => isA<TemplateFault>()
          .having((f) => f.code, 'code', FaultCode.unknownValue)
          .having((f) => f.file, 'file', 'packs/prd-core/pack.yaml')
          .having((f) => f.key, 'key', 'migrations[0].steps[0].merge_doc.$key');

      test('merge_doc whose to names no doc type the pack defines refuses '
          'at to', () async {
        await expectLater(
          resolveWith(files(to: 'featur')),
          throwsA(unknownAt('to')),
        );
      });

      test('merge_doc whose section to id no layer of the to type defines '
          'refuses at that section', () async {
        await expectLater(
          resolveWith(files(toSection: 'goall')),
          throwsA(unknownAt('sections[0].to')),
        );
      });

      test('merge_doc whose from id and path no layer defines loads', () async {
        final merged = await resolveWith(files());

        expect(merged.lookup('feature'), isNotNull);
        expect(merged.lookup('error'), isNull);
      });

      group('layer files of the folded doc type', () {
        const folded = '.specstone/templates/x.yaml';

        Future<MergedSet> resolveProject(Map<String, String> templates) async =>
            TemplateResolver(
              shippedFiles: files(from: 'x', fromPath: 'specs/X.md'),
            ).resolve(
              workingDirectory: await writeTree({
                _configPath: 'packs:\n  prd-core: 1.1.0\n',
                ...templates,
              }),
              homeDirectory: await writeTree({}),
            );

        test('an x.yaml with no path adds no doc type', () async {
          final merged = await resolveProject({
            folded: 'id: x\nsections:\n  - id: gone\n    disabled: true\n',
          });

          expect(merged.docTypes.map((type) => type.id), ['feature']);
        });

        test('an x.yaml with a path adds no doc type', () async {
          final merged = await resolveProject({
            folded: 'id: x\ndescription: X\npath: xs/{slug}.md\n',
          });

          expect(merged.docTypes.map((type) => type.id), ['feature']);
        });

        test('an x.yaml holding invalid YAML resolves with no fault', () async {
          final merged = await resolveProject({folded: 'id: [unclosed\n'});

          expect(merged.docTypes.map((type) => type.id), ['feature']);
        });

        test('foldedDocTypes maps the from id to the to id', () async {
          final merged = await resolveProject({});

          expect(merged.foldedDocTypes, {'x': 'feature'});
        });

        const section =
            'sections: [{from: {id: catalog, header: Catalog}, to: goal}]';
        String foldTo(String to) =>
            '      - merge_doc: {from: {id: x, path: specs/X.md}, '
            'to: $to, $section}\n';
        for (final (:name, :migrations, :to) in [
          (
            name: 'in one entry',
            migrations:
                '  - from: 1.0.0\n    steps:\n'
                '${foldTo('feature')}${foldTo('other')}',
            to: 'other',
          ),
          (
            name: 'in an older-from entry listed after a newer one',
            migrations:
                '  - from: 1.1.0\n    steps:\n${foldTo('feature')}'
                '  - from: 1.0.0\n    steps:\n${foldTo('other')}',
            to: 'feature',
          ),
        ]) {
          test('foldedDocTypes keeps the later step in chain order when two '
              'steps fold one from id, $name', () async {
            final project = await writeTree({
              _configPath: 'packs:\n  prd-core: 1.2.0\n',
            });
            final home = await writeTree({});
            final merged = TemplateResolver(
              shippedFiles: {
                ...files(from: 'x', fromPath: 'specs/X.md'),
                'prd-core/pack.yaml': _bytes(
                  'name: prd-core\nversion: 1.2.0\nmigrations:\n$migrations',
                ),
                'prd-core/other.yaml': _bytes(
                  'id: other\ndescription: Other\npath: others/{slug}.md\n'
                  'sections:\n  - id: goal\n    header: Goal\n',
                ),
              },
            ).resolve(workingDirectory: project, homeDirectory: home);

            expect(merged.foldedDocTypes, {'x': to});
          });
        }

        test('foldedDocTypes is empty when no pack folds a doc type', () {
          final merged = TemplateResolver(shippedFiles: shipped())
              .resolveCarried(packNames: ['prd-core'], homeDirectory: null);

          expect(merged.foldedDocTypes, isEmpty);
        });

        test('a z.yaml no step folds still adds its doc type', () async {
          final merged = await resolveProject({
            '.specstone/templates/z.yaml':
                'id: z\ndescription: Z\npath: zs/{slug}.md\n',
          });

          expect(merged.docTypes.map((type) => type.id), ['feature', 'z']);
        });

        test('a carried x layer is dropped from the merged set', () async {
          final merged =
              TemplateResolver(
                shippedFiles: files(from: 'x', fromPath: 'specs/X.md'),
              ).resolveCarried(
                packNames: ['prd-core'],
                homeDirectory: null,
                projectLayers: [
                  DocTypeLayer.parse(
                    'id: x\ndescription: X\npath: xs/{slug}.md\n',
                    file: folded,
                    docTypeId: 'x',
                    kind: LayerKind.project,
                    files: const _NoFiles(),
                  ),
                ],
              );

          expect(merged.docTypes.map((type) => type.id), ['feature']);
        });
      });
    });

    test("an extends doc type keeps its target's "
        'generators', () async {
      final home = await writeTree({});
      final resolver = TemplateResolver(
        shippedFiles: shipped(),
        generatorKinds: {...shippedGeneratorKinds, 'note_toc', 'other'},
      );
      const note =
          'id: note\ndescription: A note\npath: prds/notes/{slug}/NOTE.md\n'
          'generators: [note_toc]\n';
      Future<List<String>?> extending(String extra) async {
        final project = await writeTree({
          _configPath: 'packs:\n  prd-core: 1.1.0\n',
          '.specstone/templates/note.yaml': note,
          '.specstone/templates/memo.yaml':
              'id: memo\nextends: note\npath: memos/{slug}.md\n$extra',
        });
        return resolver
            .resolve(workingDirectory: project, homeDirectory: home)
            .lookup('memo')!
            .generators;
      }

      expect(await extending(''), ['note_toc']);
      expect(await extending('generators: {add: [other]}\n'), [
        'note_toc',
        'other',
      ]);
    });

    test("an extends doc type keeps its target's summary_for", () async {
      final home = await writeTree({});
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/note.yaml':
            'id: note\ndescription: A note\npath: prds/notes/{slug}/NOTE.md\n'
            'summary_for: [note]\n',
        '.specstone/templates/memo.yaml':
            'id: memo\nextends: note\npath: memos/{slug}.md\n',
      });
      final merged = TemplateResolver(shippedFiles: shipped())
          .resolve(workingDirectory: project, homeDirectory: home);

      expect(merged.lookup('memo')!.summaryFor, ['note']);
    });

    test('an extending doc type inherits bundle_refs with bundle', () async {
      final home = await writeTree({});
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/note.yaml':
            'id: note\ndescription: A note\npath: prds/notes/{slug}/NOTE.md\n'
            'bundle: [implement]\nbundle_refs: true\n',
        '.specstone/templates/memo.yaml':
            'id: memo\nextends: note\npath: memos/{slug}.md\n',
      });
      final merged = TemplateResolver(shippedFiles: shipped())
          .resolve(workingDirectory: project, homeDirectory: home);

      final memo = merged.lookup('memo')!;
      expect(memo.bundle, ['implement']);
      expect(memo.bundleRefs, isTrue);
    });

    test('an extending doc type sets bundle_refs false over an inherited '
        'true', () async {
      final home = await writeTree({});
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/note.yaml':
            'id: note\ndescription: A note\npath: prds/notes/{slug}/NOTE.md\n'
            'bundle: [implement]\nbundle_refs: true\n',
        '.specstone/templates/memo.yaml':
            'id: memo\nextends: note\npath: memos/{slug}.md\n'
            'bundle_refs: false\n',
      });
      final merged = TemplateResolver(shippedFiles: shipped())
          .resolve(workingDirectory: project, homeDirectory: home);

      expect(merged.lookup('memo')!.bundleRefs, isFalse);
    });

    test('a doc type extending feature carries no '
        'max_depth', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/feature.yaml': 'max_depth: 3\n',
        '.specstone/templates/epic.yaml':
            'id: epic\nextends: feature\npath: prds/epics/{slug}/EPIC.md\n',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      expect(merged.lookup('feature')!.maxDepth, 3);
      expect(merged.lookup('epic')!.maxDepth, isNull);
    });

    test('a path_from doc type derives its patterns from a grouped '
        'feature path', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/feature.yaml':
            'path: prds/features/{slug}/f{nn}_{slug}/FEATURE.md\n',
        '.specstone/templates/area_index.yaml': _areaIndexLayer,
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      final areaIndex = merged.lookup('area_index')!;
      expect(areaIndex.path, isNull);
      expect(areaIndex.pathFrom, 'feature_groups');
      expect(areaIndex.paths, ['prds/features/{slug}/AREA.md']);
      expect(
        PathPattern(areaIndex.paths.single)
            .matches('prds/features/form/AREA.md'),
        isTrue,
      );
    });

    test('a doc type extending a path_from type with no pattern key is '
        'missing_key at path', () async {
      final fault = await _resolveFault(
        project: {
          _configPath: 'packs:\n  prd-core: 1.1.0\n',
          '.specstone/templates/area_index.yaml': _areaIndexLayer,
          '.specstone/templates/area_note.yaml':
              'id: area_note\n'
              'extends: area_index\n',
        },
      );

      expect(fault.code, FaultCode.missingKey);
      expect(fault.key, 'path');
      expect(fault.file, '.specstone/templates/area_note.yaml');
    });

    test('a project template with a new id '
        'adds a doc type', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/runbook.yaml': '''
id: runbook
description: How to run the system
path: ops/runbooks/{slug}/RUNBOOK.md
sections:
  - id: steps
    header: Steps
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      final runbook = merged.lookup('runbook')!;
      expect(runbook.pack, isNull);
      expect(runbook.path, 'ops/runbooks/{slug}/RUNBOOK.md');
      expect(runbook.description, 'How to run the system');
      expect(runbook.fields.map((f) => f.id).toList(), [
        'slug',
        'status',
        'draft',
        'approved',
        'reference',
        'retrim',
        'retired_ids',
      ]);
      expect(runbook.sections.single.id, 'steps');
    });

    // The test name stays one literal so specstone check can find it.
    // ignore: lines_longer_than_80_chars
    test('a new doc type without path, or without description and extends, is missing_key', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/runbook.yaml': '''
id: runbook
description: How to run the system
sections:
  - id: steps
    header: Steps
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.missingKey)
              .having((f) => f.key, 'key', 'path')
              .having(
                (f) => f.file,
                'file',
                '.specstone/templates/runbook.yaml',
              ),
        ),
      );

      final bare = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/runbook.yaml': '''
id: runbook
path: ops/runbooks/{slug}/RUNBOOK.md
''',
      });

      expect(
        () => resolver.resolve(workingDirectory: bare, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.missingKey)
              .having((f) => f.key, 'key', 'description')
              .having(
                (f) => f.file,
                'file',
                '.specstone/templates/runbook.yaml',
              ),
        ),
      );
    });

    test('a layer with no id or extends over a doc type no pack defines '
        'adds no doc type and is orphaned', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/auth.yaml': 'path: specs/{slug}/AUTH.md\n',
      });
      final resolver = TemplateResolver(shippedFiles: shipped());

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: await writeTree({}),
      );

      expect(merged.lookup('auth'), isNull);
      expect(merged.orphanedDocTypes, {'auth'});
    });

    test('a new doc type with extends inherits every key of the target except '
        'id and path', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/project.yaml': '''
id: project
description: A project
path: projects/{slug}/PROJECT.md
''',
        '.specstone/templates/feature.yaml': '''
parent: project
lint:
  max_lines: 300
  banned_words: [fast]
reference:
  - title: A
''',
        '.specstone/templates/adr.yaml': '''
id: adr
extends: feature
path: adr/{slug}.md
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      final feature = merged.lookup('feature')!;
      final adr = merged.lookup('adr')!;
      expect(adr.description, feature.description);
      expect(adr.parent, 'project');
      expect(adr.fields, feature.fields);
      expect(adr.sections, feature.sections);
      expect(adr.lint.maxLines, 300);
      expect(adr.lint.bannedWords, ['fast']);
      expect(adr.reference!.map((r) => r.title), ['A']);
      expect(adr.id, 'adr');
      expect(adr.path, 'adr/{slug}.md');
      expect(adr.extendsId, 'feature');
      expect(adr.pack, isNull);
    });

    test('a doc type that extends a titled type has no title', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/feature.yaml': 'title: Feature list\n',
        '.specstone/templates/adr.yaml': '''
id: adr
extends: feature
path: adr/{slug}.md
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      expect(merged.lookup('feature')!.title, 'Feature list');
      expect(merged.lookup('adr')!.title, isNull);
    });

    test('an extending doc type inherits the '
        'per_target of its target', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/feature.yaml': '''
id: feature
description: A feature
path: features/{slug}/FEATURE.md
per_target: true
''',
        '.specstone/templates/adr.yaml': '''
id: adr
extends: feature
path: adr/{slug}.md
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      expect(merged.lookup('feature')!.isPerTarget, isTrue);
      expect(merged.lookup('adr')!.isPerTarget, isTrue);
    });

    test('an extending doc type inherits the '
        'fixed_numbers of its target', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/feature.yaml': '''
id: feature
description: A feature
path: features/{slug}/FEATURE.md
fixed_numbers: true
''',
        '.specstone/templates/adr.yaml': '''
id: adr
extends: feature
path: adr/{slug}.md
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      expect(merged.lookup('feature')!.fixedNumbers, isTrue);
      expect(merged.lookup('adr')!.fixedNumbers, isTrue);
    });

    test('an extending doc type writes its own parent and '
        'lint, the target keeps its own', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/project.yaml': '''
id: project
description: A project
path: projects/{slug}/PROJECT.md
''',
        '.specstone/templates/epic.yaml': '''
id: epic
description: An epic
path: epics/{slug}/EPIC.md
''',
        '.specstone/templates/feature.yaml': '''
parent: project
lint:
  max_lines: 300
''',
        '.specstone/templates/adr.yaml': '''
id: adr
extends: feature
path: adr/{slug}.md
parent: epic
lint:
  max_lines: 120
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      final adr = merged.lookup('adr')!;
      final feature = merged.lookup('feature')!;
      expect(adr.parent, 'epic');
      expect(adr.lint.maxLines, 120);
      expect(feature.parent, 'project');
      expect(feature.lint.maxLines, 300);
    });

    test('a defining extends layer that clears parent gives a doc type with '
        'no parent', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/project.yaml': '''
id: project
description: A project
path: projects/{slug}/PROJECT.md
''',
        '.specstone/templates/feature.yaml': 'parent: project\n',
        '.specstone/templates/adr.yaml': '''
id: adr
extends: feature
path: adr/{slug}.md
parent:
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      expect(merged.lookup('adr')!.parent, isNull);
      expect(merged.lookup('feature')!.parent, 'project');
    });

    test('a layer above the defining layer that clears parent stays '
        'locked_field_disabled', () async {
      final home = await writeTree({
        '.specstone/packs/nont-x/pack.yaml':
            'name: nont-x\nversion: 1.0.0\nextends: prd-core\n',
        '.specstone/packs/nont-x/adr.yaml': '''
id: adr
extends: feature
path: adr/{slug}.md
parent: project
''',
      });
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n  nont-x: 1.0.0\n',
        '.specstone/templates/project.yaml': '''
id: project
description: A project
path: projects/{slug}/PROJECT.md
''',
        '.specstone/templates/adr.yaml': 'parent:\n',
      });
      final resolver = TemplateResolver(shippedFiles: shipped());

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.lockedFieldDisabled)
              .having((f) => f.key, 'key', 'parent'),
        ),
      );
    });

    test('a defining layer without extends that clears parent is not '
        'affected', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/runbook.yaml': '''
id: runbook
description: A runbook
path: ops/{slug}/runbook.md
parent:
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      expect(merged.lookup('runbook')!.parent, isNull);
    });

    test('an extending doc type that writes no '
        'bundle inherits the bundle of its target', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/project.yaml': '''
id: project
description: A project
path: projects/{slug}/PROJECT.md
''',
        '.specstone/templates/feature.yaml': '''
parent: project
bundle: [implement, design]
''',
        '.specstone/templates/adr.yaml': '''
id: adr
extends: feature
path: adr/{slug}.md
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      expect(merged.lookup('adr')!.bundle, ['implement', 'design']);
      expect(merged.lookup('feature')!.bundle, ['implement', 'design']);
    });

    test('a layer over an extending doc type '
        'removes one inherited bundle mode and keeps the other', () async {
      final home = await writeTree({
        '.specstone/packs/nont-x/pack.yaml':
            'name: nont-x\nversion: 1.0.0\nextends: prd-core\n',
        '.specstone/packs/nont-x/adr.yaml': '''
id: adr
extends: feature
path: adr/{slug}.md
''',
      });
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n  nont-x: 1.0.0\n',
        '.specstone/templates/project.yaml': '''
id: project
description: A project
path: projects/{slug}/PROJECT.md
''',
        '.specstone/templates/feature.yaml': '''
parent: project
bundle: [implement, design]
''',
        '.specstone/templates/adr.yaml': '''
bundle:
  remove: [design]
''',
      });
      final resolver = TemplateResolver(shippedFiles: shipped());

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      expect(merged.lookup('adr')!.bundle, ['implement']);
      expect(merged.lookup('feature')!.bundle, ['implement', 'design']);
    });

    test('an extending doc type changes inherited lists by '
        'add and remove', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/project.yaml': '''
id: project
description: A project
path: projects/{slug}/PROJECT.md
''',
        '.specstone/templates/feature.yaml': '''
parent: project
lint:
  banned_words: [fast]
reference:
  - title: A
''',
        '.specstone/templates/adr.yaml': '''
id: adr
extends: feature
path: adr/{slug}.md
lint:
  banned_words:
    add: [simply]
reference:
  remove: [A]
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      final adr = merged.lookup('adr')!;
      final feature = merged.lookup('feature')!;
      expect(adr.lint.bannedWords, ['fast', 'simply']);
      expect(adr.reference, isEmpty);
      expect(feature.lint.bannedWords, ['fast']);
      expect(feature.reference!.map((r) => r.title), ['A']);
    });

    test('a plain list over an '
        'inherited list is list_override_needs_add_remove', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/project.yaml': '''
id: project
description: A project
path: projects/{slug}/PROJECT.md
''',
        '.specstone/templates/feature.yaml': '''
parent: project
lint:
  banned_words: [fast]
reference:
  - title: A
''',
        '.specstone/templates/adr.yaml': '''
id: adr
extends: feature
path: adr/{slug}.md
lint:
  banned_words: [x]
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having(
                (f) => f.code,
                'code',
                FaultCode.listOverrideNeedsAddRemove,
              )
              .having((f) => f.key, 'key', 'lint.banned_words')
              .having((f) => f.file, 'file', '.specstone/templates/adr.yaml'),
        ),
      );

      final plainReference = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/project.yaml': '''
id: project
description: A project
path: projects/{slug}/PROJECT.md
''',
        '.specstone/templates/feature.yaml': '''
parent: project
reference:
  - title: A
''',
        '.specstone/templates/adr.yaml': '''
id: adr
extends: feature
path: adr/{slug}.md
reference:
  - title: B
''',
      });

      expect(
        () => resolver.resolve(
          workingDirectory: plainReference,
          homeDirectory: home,
        ),
        throwsA(
          isA<TemplateFault>()
              .having(
                (f) => f.code,
                'code',
                FaultCode.listOverrideNeedsAddRemove,
              )
              .having((f) => f.key, 'key', 'reference'),
        ),
      );
    });

    test('an extending doc type without path is '
        'missing_key; path is never inherited', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/feature.yaml': '''
description: A feature
path: features/f{nn}_{slug}/FEATURE.md
''',
        '.specstone/templates/adr.yaml': '''
id: adr
extends: feature
description: An architecture decision
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.missingKey)
              .having((f) => f.key, 'key', 'path')
              .having((f) => f.file, 'file', '.specstone/templates/adr.yaml'),
        ),
      );
    });

    test('an extending doc type adds a section '
        'after the inherited ones', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/feature.yaml': '''
description: A feature
path: features/f{nn}_{slug}/FEATURE.md
sections:
  - id: goal
    header: Goal
  - id: scope
    header: Scope
''',
        '.specstone/templates/adr.yaml': '''
id: adr
extends: feature
path: adr/{slug}.md
sections:
  - id: decision
    header: Decision
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      expect(merged.lookup('adr')!.sections.map((s) => s.id).toList(), [
        'goal',
        'scope',
        'decision',
      ]);
    });

    test('an extending doc type changes a section of its '
        'target, the target keeps its own', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/feature.yaml': '''
description: A feature
path: features/f{nn}_{slug}/FEATURE.md
sections:
  - id: goal
    header: Goal
    description: What the feature wants
''',
        '.specstone/templates/adr.yaml': '''
id: adr
extends: feature
path: adr/{slug}.md
sections:
  - id: goal
    description: What the decision changes
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      expect(
        merged.lookup('adr')!.sections.single.description,
        'What the decision changes',
      );
      expect(
        merged.lookup('feature')!.sections.single.description,
        'What the feature wants',
      );
    });

    test('an extending entry whose id the target lacks '
        'is override_id_not_found', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/feature.yaml': '''
description: A feature
path: features/f{nn}_{slug}/FEATURE.md
''',
        '.specstone/templates/adr.yaml': '''
id: adr
extends: feature
path: adr/{slug}.md
sections:
  - id: nope
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.overrideIdNotFound)
              .having((f) => f.key, 'key', 'sections.nope')
              .having((f) => f.file, 'file', '.specstone/templates/adr.yaml'),
        ),
      );
    });

    test('extends written by a layer above the defining layer is '
        'extends_in_override', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/feature.yaml': '''
description: Project feature
extends: feature
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.extendsInOverride)
              .having((f) => f.key, 'key', 'extends')
              .having(
                (f) => f.file,
                'file',
                '.specstone/templates/feature.yaml',
              )
              .having(
                (f) => f.message,
                'message',
                contains(
                  'Write `extends` only in the file that first defines '
                  'the doc type',
                ),
              ),
        ),
      );
    });

    test('several layers above the defining '
        'layer fault the first in load order', () async {
      final home = await writeTree({
        '.specstone/packs/nont-x/pack.yaml':
            'name: nont-x\nversion: 1.0.0\nextends: prd-core\n',
        '.specstone/packs/nont-x/feature.yaml': '''
extends: feature
''',
      });
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n  nont-x: 1.0.0\n',
        '.specstone/templates/feature.yaml': '''
extends: feature
''',
      });
      final resolver = TemplateResolver(shippedFiles: shipped());

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.extendsInOverride)
              .having(
                (f) => f.file,
                'file',
                '~/.specstone/packs/nont-x/feature.yaml',
              ),
        ),
      );
    });

    test('extends_in_override faults the first '
        'offender in load order across doc types', () async {
      final files = shipped()
        ..['prd-core/z.yaml'] = _bytes(
          'id: z\ndescription: Z\npath: z/{slug}.md\n',
        );
      final home = await writeTree({
        '.specstone/packs/nont-x/pack.yaml':
            'name: nont-x\nversion: 1.0.0\nextends: prd-core\n',
        '.specstone/packs/nont-x/z.yaml': 'extends: z\n',
      });
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n  nont-x: 1.0.0\n',
        '.specstone/templates/feature.yaml': 'extends: feature\n',
      });
      final resolver = TemplateResolver(shippedFiles: files);

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.extendsInOverride)
              .having(
                (f) => f.file,
                'file',
                '~/.specstone/packs/nont-x/z.yaml',
              ),
        ),
      );
    });

    test('a doc type extending itself is '
        'extends_cycle naming it once', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/a.yaml': 'id: a\nextends: a\npath: a/{slug}.md\n',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.extendsCycle)
              .having((f) => f.file, 'file', '.specstone/templates/a.yaml')
              .having((f) => f.relatedFiles, 'relatedFiles', isEmpty)
              .having(
                (f) => f.message,
                'message',
                'extends chain returns to its start: a, a',
              ),
        ),
      );
    });

    test('an extends naming no doc type is extends_target_unknown', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/adr.yaml': '''
extends: nothing
path: adr/{slug}.md
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.extendsTargetUnknown)
              .having((f) => f.key, 'key', 'extends')
              .having((f) => f.file, 'file', '.specstone/templates/adr.yaml')
              .having((f) => f.message, 'message', contains('nothing')),
        ),
      );
    });

    test('a doc-type extends loop is '
        'extends_cycle', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/a.yaml': '''
extends: b
path: a/{slug}.md
''',
        '.specstone/templates/b.yaml': '''
extends: a
path: b/{slug}.md
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.extendsCycle)
              .having((f) => f.file, 'file', '.specstone/templates/b.yaml')
              .having((f) => f.relatedFiles, 'relatedFiles', [
                '.specstone/templates/a.yaml',
              ]),
        ),
      );
    });

    test('a doc-type extends loop '
        'across layers names the upper layer file', () async {
      final files = shipped()
        ..['prd-core/feature.yaml'] = _bytes('''
id: feature
description: A feature
path: features/f{nn}_{slug}/FEATURE.md
extends: epic
''');
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/epic.yaml': '''
id: epic
extends: feature
path: epics/{slug}/EPIC.md
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: files);

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.extendsCycle)
              .having((f) => f.file, 'file', '.specstone/templates/epic.yaml')
              .having((f) => f.relatedFiles, 'relatedFiles', [
                'packs/prd-core/feature.yaml',
              ]),
        ),
      );
    });

    test('a shipped pack extending another shipped pack '
        'loads above it, so its override resolves', () async {
      final files = shipped()
        ..['prd-core/pack.yaml'] = _bytes(
          'name: prd-core\nversion: 1.1.0\nextends: software-tech\n',
        )
        ..['prd-core/architecture.yaml'] = _bytes('description: Overridden\n');
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n  software-tech: 1.0.0\n',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: files);

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      expect(merged.lookup('architecture')!.description, 'Overridden');
    });

    test('a new doc type with no parent is a top-level '
        'doc type', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/runbook.yaml': '''
id: runbook
description: How to run the system
path: ops/runbooks/{slug}/RUNBOOK.md
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      expect(merged.lookup('runbook')!.parent, isNull);
    });

    test('two doc types with one path '
        'are doc_type_path_conflict', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/playbook.yaml': '''
id: playbook
description: A playbook
path: ops/{slug}/RUNBOOK.md
''',
        '.specstone/templates/runbook.yaml': '''
id: runbook
description: A runbook
path: ops/{slug}/RUNBOOK.md
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.docTypePathConflict)
              .having((f) => f.key, 'key', 'path')
              .having(
                (f) => f.file,
                'file',
                '.specstone/templates/runbook.yaml',
              )
              .having((f) => f.relatedFiles, 'relatedFiles', [
                '.specstone/templates/playbook.yaml',
              ]),
        ),
      );
    });

    test('a project doc type sharing a shipped '
        'path faults on the project file', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/epic.yaml': '''
id: epic
description: An epic
path: features/f{nn}_{slug}/FEATURE.md
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.docTypePathConflict)
              .having((f) => f.key, 'key', 'path')
              .having((f) => f.file, 'file', '.specstone/templates/epic.yaml')
              .having((f) => f.relatedFiles, 'relatedFiles', [
                'packs/prd-core/feature.yaml',
              ]),
        ),
      );
    });

    test('a path conflict names the file that '
        'loads later by path', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/run.yaml': '''
id: run
description: A run
path: ops/{slug}/RUN.md
''',
        '.specstone/templates/run_book.yaml': '''
id: run_book
description: A run book
path: ops/{slug}/RUN.md
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.docTypePathConflict)
              .having(
                (f) => f.file,
                'file',
                '.specstone/templates/run_book.yaml',
              )
              .having((f) => f.relatedFiles, 'relatedFiles', [
                '.specstone/templates/run.yaml',
              ]),
        ),
      );
    });

    test('a project path_from type clashing with a pack type faults on the '
        'project file', () async {
      final fault = await _resolveFault(
        project: {
          _configPath: 'packs:\n  prd-core: 1.1.0\n',
          '.specstone/templates/feature.yaml':
              'path: prds/features/{slug}/f{nn}_{slug}/FEATURE.md\n',
          '.specstone/templates/area_index.yaml': _areaIndexLayer,
        },
        shippedFiles: {
          ...shipped(),
          'prd-core/area.yaml': _bytes(
            'id: area\ndescription: An area\n'
            'path: prds/features/{slug}/AREA.md\n',
          ),
        },
      );

      expect(fault.code, FaultCode.docTypePathConflict);
      expect(fault.key, 'file');
      expect(fault.file, '.specstone/templates/area_index.yaml');
      expect(fault.relatedFiles, ['packs/prd-core/area.yaml']);
    });

    test('two project doc types listing group_feature_catalog are '
        'unknown_value at generators', () async {
      final projectDir = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/area_a.yaml':
            'id: area_a\ndescription: A\npath: area_a/{slug}.md\n'
            'generators: [group_feature_catalog]\n',
        '.specstone/templates/area_b.yaml':
            'id: area_b\ndescription: B\npath: area_b/{slug}.md\n'
            'generators: [group_feature_catalog]\n',
      });
      final homeDir = await writeTree({});
      final resolver = TemplateResolver(
        shippedFiles: shipped(),
        generatorKinds: {...shippedGeneratorKinds, groupFeatureCatalogKind},
      );

      expect(
        () => resolver.resolve(
          workingDirectory: projectDir,
          homeDirectory: homeDir,
        ),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.unknownValue)
              .having((f) => f.key, 'key', 'generators')
              .having((f) => f.file, 'file', '.specstone/templates/area_b.yaml')
              .having((f) => f.relatedFiles, 'relatedFiles', [
                '.specstone/templates/area_a.yaml',
              ]),
        ),
      );
    });

    test('a project type listing group_feature_catalog beside the shipped '
        'group_features is refused at generators', () async {
      final projectDir = await writeTree({
        _configPath: shippedPinsConfig(['prd-core']),
        '.specstone/templates/area_index.yaml':
            'id: area_index\ndescription: A\npath: area/{slug}.md\n'
            'generators: [group_feature_catalog]\n',
      });
      final homeDir = await writeTree({});

      expect(
        () => TemplateResolver().resolve(
          workingDirectory: projectDir,
          homeDirectory: homeDir,
        ),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.unknownValue)
              .having((f) => f.key, 'key', 'generators')
              .having(
                (f) => f.file,
                'file',
                '.specstone/templates/area_index.yaml',
              )
              .having((f) => f.relatedFiles, 'relatedFiles', [
                'packs/prd-core/group_features.yaml',
              ]),
        ),
      );
    });

    test('a project doc type with a parent naming no doc type id is '
        'unknown_value', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/runbook.yaml': '''
id: runbook
description: A runbook
path: ops/{slug}/RUNBOOK.md
parent: nope
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.unknownValue)
              .having((f) => f.key, 'key', 'parent')
              .having(
                (f) => f.file,
                'file',
                '.specstone/templates/runbook.yaml',
              ),
        ),
      );
    });

    test('overriding parent with an existing id is '
        'accepted', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/runbook.yaml': '''
id: runbook
description: A runbook
path: ops/{slug}/RUNBOOK.md
''',
        '.specstone/templates/feature.yaml': '''
parent: runbook
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      expect(merged.lookup('feature')!.parent, 'runbook');
    });

    test('a parent loop is parent_cycle; a self parent '
        'names one file', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/epic.yaml': '''
id: epic
description: An epic
path: epics/{slug}/EPIC.md
parent: story
''',
        '.specstone/templates/story.yaml': '''
id: story
description: A story
path: stories/{slug}/STORY.md
parent: epic
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.parentCycle)
              .having((f) => f.key, 'key', 'parent')
              .having((f) => f.file, 'file', '.specstone/templates/story.yaml')
              .having((f) => f.relatedFiles, 'relatedFiles', [
                '.specstone/templates/epic.yaml',
              ]),
        ),
      );

      final selfParent = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/self.yaml': '''
id: self
description: A self
path: selfs/{slug}/SELF.md
parent: self
''',
      });

      expect(
        () =>
            resolver.resolve(workingDirectory: selfParent, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.parentCycle)
              .having((f) => f.file, 'file', '.specstone/templates/self.yaml'),
        ),
      );
    });

    test('a parent loop across layers names the '
        'upper layer file', () async {
      final files = shipped()
        ..['prd-core/feature.yaml'] = _bytes('''
id: feature
description: A feature
path: features/f{nn}_{slug}/FEATURE.md
parent: epic
''');
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/epic.yaml': '''
id: epic
description: An epic
path: epics/{slug}/EPIC.md
parent: feature
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: files);

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.parentCycle)
              .having((f) => f.file, 'file', '.specstone/templates/epic.yaml')
              .having((f) => f.relatedFiles, 'relatedFiles', [
                'packs/prd-core/feature.yaml',
              ]),
        ),
      );
    });

    test('a doc_types entry naming no id is '
        'unknown_value', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/runbook.yaml': '''
id: runbook
description: A runbook
path: ops/{slug}/RUNBOOK.md
fields:
  - id: up
    type: doc_ref
    doc_types: [nope]
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      expect(
        () => resolver.resolve(workingDirectory: project, homeDirectory: home),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.unknownValue)
              .having((f) => f.key, 'key', 'fields.up.doc_types')
              .having(
                (f) => f.file,
                'file',
                '.specstone/templates/runbook.yaml',
              ),
        ),
      );
    });

    test('a project adr extends a pack-defined feature '
        'with no doc_type_duplicate', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/adr.yaml': '''
id: adr
extends: feature
path: adr/{slug}.md
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: shipped());

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      final adr = merged.lookup('adr')!;
      expect(adr.extendsId, 'feature');
      expect(adr.description, 'A feature');
      expect(merged.lookup('feature'), isNotNull);
    });

    test('every list of an extends-built doc type is unmodifiable', () async {
      final files = shipped()
        ..['prd-core/feature.yaml'] = _bytes('''
id: feature
description: A feature
path: features/f{nn}_{slug}/FEATURE.md
sections:
  - id: goal
    header: Feature goal
reference:
  - title: A
''');
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/adr.yaml': '''
id: adr
extends: feature
path: adr/{slug}.md
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(shippedFiles: files);

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      final adr = merged.lookup('adr')!;
      expect(
        () => adr.fields.add(adr.fields.first),
        throwsUnsupportedError,
        reason: 'fields of an extends-built doc type are unmodifiable',
      );
      expect(
        () => adr.sections.add(adr.sections.first),
        throwsUnsupportedError,
      );
      expect(() => adr.files.add('x'), throwsUnsupportedError);
      expect(
        () => adr.reference!.add(adr.reference!.first),
        throwsUnsupportedError,
      );
    });

    test('a section with no header in a new doc type is refused with exit '
        '78', () async {
      final fault = await _resolveFault(
        project: {
          _configPath: 'packs:\n  prd-core: 1.1.0\n',
          '.specstone/templates/runbook.yaml': '''
id: runbook
description: How to run the system
path: ops/runbooks/{slug}/RUNBOOK.md
sections:
  - id: steps
''',
        },
      );

      expect(fault.code, FaultCode.overrideIdNotFound);
      expect(fault.file, '.specstone/templates/runbook.yaml');
      expect(fault.key, 'sections.steps');
      expect(fault.exitStatus, 78);
    });

    test(
      'a project feature file with max_depth 0 keeps one path pattern',
      () async {
        final project = await writeTree({
          _configPath: 'packs:\n  prd-core: 1.1.0\n',
          '.specstone/templates/feature.yaml': 'max_depth: 0\n',
        });
        final home = await writeTree({});
        final resolver = TemplateResolver(shippedFiles: shipped());

        final merged = resolver.resolve(
          workingDirectory: project,
          homeDirectory: home,
        );

        final feature = merged.lookup('feature')!;
        expect(feature.maxDepth, 0);
        expect(feature.paths, ['features/f{nn}_{slug}/FEATURE.md']);
      },
    );

    test('an extending doc type disabling an id its target lacks is '
        'refused', () async {
      final fault = await _resolveFault(
        project: {
          _configPath: 'packs:\n  prd-core: 1.1.0\n',
          '.specstone/templates/adr.yaml': '''
id: adr
extends: feature
path: adr/{slug}.md
sections:
  - id: nope
    disabled: true
''',
        },
      );

      expect(fault.code, FaultCode.overrideIdNotFound);
      expect(fault.key, 'sections.nope');
      expect(fault.file, '.specstone/templates/adr.yaml');
      expect(fault.exitStatus, 78);
    });

    test('a doc-level extends does not excuse two packs defining one doc '
        'type id', () async {
      final fault = await _resolveFault(
        project: {
          _configPath:
              'packs:\n  prd-core: 1.1.0\n  software-tech: 1.0.0\n'
              '  nont-x: 1.0.0\n',
        },
        home: {
          '.specstone/packs/nont-x/pack.yaml': 'name: nont-x\nversion: 1.0.0\n',
          '.specstone/packs/nont-x/feature.yaml': '''
id: feature
extends: architecture
path: features/{slug}/FEATURE.md
''',
        },
      );

      expect(fault.code, FaultCode.docTypeDuplicate);
      expect(fault.file, '~/.specstone/packs/nont-x/feature.yaml');
      expect(fault.relatedFiles, ['packs/prd-core/feature.yaml']);
      expect(fault.exitStatus, 78);
    });
  });

  group('TemplateResolver grouped child types', () {
    Future<MergedSet> resolveGrouped(Directory project) async =>
        TemplateResolver().resolve(
          workingDirectory: project,
          homeDirectory: await writeTree({}),
        );

    test('a feature-only grouped project reads its child types '
        'with the group level', () async {
      final merged = await resolveGrouped(await writeFeatureGroupedProject());

      expect(
        [
          for (final id in ['user_story', 'fr', 'api', 'implementation'])
            merged.lookup(id)!.path,
        ],
        [
          'prds/features/{slug}/f{nn}_{slug}/us{nn}_{slug}/USER_STORY.md',
          'prds/features/{slug}/f{nn}_{slug}/us{nn}_{slug}/fr{nn}_{slug}.md',
          'specs/{slug}/f{nn}_{slug}/API.md',
          '.specstone/records/{slug}/f{nn}_{slug}/IMPLEMENTATION.md',
        ],
      );
    });

    test('the stratum-ui child overrides keep the group level once', () async {
      final merged = await resolveGrouped(await writeGroupedProject());

      expect(merged.lookup('api')!.path, 'specs/{slug}/f{nn}_{slug}/API.md');
      expect(
        merged.lookup('implementation')!.path,
        'specs/{slug}/f{nn}_{slug}/IMPLEMENTATION.md',
      );
    });

    test(
      'a grouped child type nests its feature folder after the group level',
      () async {
        final merged = await resolveGrouped(await writeFeatureGroupedProject());

        expect(merged.lookup('api')!.paths, [
          for (var depth = 0; depth <= 3; depth++)
            'specs/{slug}/f{nn}_{slug}${'/f{nn}_{slug}' * depth}/API.md',
        ]);
      },
    );

    test(
      'a project type at the grouped api pattern conflicts with api',
      () async {
        final project = await writeFeatureGroupedProject(
          extra: {
            '.specstone/templates/grid.yaml':
                'id: grid\ndescription: A grid.\n'
                'path: specs/{slug}/f{nn}_{slug}/API.md\n',
          },
        );

        final home = await writeTree({});

        expect(
          () => TemplateResolver().resolve(
            workingDirectory: project,
            homeDirectory: home,
          ),
          throwsA(
            isA<TemplateFault>()
                .having((f) => f.code, 'code', FaultCode.docTypePathConflict)
                .having((f) => f.file, 'file', '.specstone/templates/grid.yaml')
                .having((f) => f.relatedFiles, 'relatedFiles', [
                  'packs/software-tech/api.yaml',
                ]),
          ),
        );
      },
    );

    test('a project api override with two group folders fails at its own '
        'file', () async {
      final project = await writeFeatureGroupedProject(
        extra: {
          '.specstone/templates/api.yaml':
              'path: specs/{slug}/{slug}/f{nn}_{slug}/API.md\n',
        },
      );

      final home = await writeTree({});

      expect(
        () => TemplateResolver().resolve(
          workingDirectory: project,
          homeDirectory: home,
        ),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.unknownValue)
              .having((f) => f.file, 'file', '.specstone/templates/api.yaml')
              .having((f) => f.key, 'key', 'path'),
        ),
      );
    });
  });

  group('TemplateResolver project shared.yaml', () {
    const sharedPath = '.specstone/templates/shared.yaml';
    const config = 'packs:\n  prd-core: 1.1.0\n';

    test('a shared_lines file adds no doc type and loads its lines', () async {
      final project = await writeTree({
        _configPath: config,
        sharedPath: 'shared_lines:\n  - id: tone\n    text: Be brief.\n',
      });
      final resolver = TemplateResolver(shippedFiles: shipped());

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: await writeTree({}),
      );
      final lines = loadProjectSharedLines(project);

      expect(merged.docTypes.map((type) => type.id), ['feature']);
      expect(lines.map((line) => line.id), ['tone']);
      expect(lines.single.text, 'Be brief.');
      expect(lines.single.file, sharedPath);
    });

    test('a CRLF shared.yaml loads its line text without the CR', () async {
      final project = await writeTree({
        sharedPath: 'shared_lines:\r\n  - id: tone\r\n    text: Be brief.\r\n',
      });

      final lines = loadProjectSharedLines(project);

      expect(lines.single.text, 'Be brief.');
    });

    for (final (name, text) in [
      ('shared_fields', 'shared_fields:\n  - id: x\n    type: string\n'),
      (
        'shared_banned_patterns',
        'shared_banned_patterns:\n  - {id: x, pattern: y, message: z}\n',
      ),
      (
        'shared_required_patterns',
        'shared_required_patterns:\n  - {id: x, pattern: y, message: z}\n',
      ),
      ('notes', 'shared_lines:\n  - id: a\n    text: b\nnotes: x\n'),
    ]) {
      test('shared.yaml key $name is unknown_key at that key', () async {
        final fault = await _resolveFault(
          project: {_configPath: config, sharedPath: text},
        );

        expect(fault.code, FaultCode.unknownKey);
        expect(fault.file, sharedPath);
        expect(fault.key, name);
        expect(fault.exitStatus, 78);
      });
    }

    test(
      'an unknown key in a shared.yaml line names the shared format',
      () async {
        final fault = await _resolveFault(
          project: {
            _configPath: config,
            sharedPath: 'shared_lines:\n  - id: x\n    text: T\n    when: y\n',
          },
        );

        expect(fault.code, FaultCode.unknownKey);
        expect(fault.key, 'shared_lines[0].when');
        expect(fault.message, 'the shared format defines no key when');
      },
    );

    for (final (name, files) in [
      ('no file', <String, String>{}),
      ('a file with no key', {sharedPath: ''}),
      ('shared_lines with no value', {sharedPath: 'shared_lines:\n'}),
    ]) {
      test('no project shared layer and no fault for $name', () async {
        final project = await writeTree({_configPath: config, ...files});
        final resolver = TemplateResolver(shippedFiles: shipped());

        final merged = resolver.resolve(
          workingDirectory: project,
          homeDirectory: await writeTree({}),
        );

        expect(loadProjectSharedLines(project), isEmpty);
        expect(merged.docTypes.map((type) => type.id), ['feature']);
      });
    }
  });

  group('TemplateResolver.availableManifests and resolveCarried', () {
    test('availableManifests gives the carried version of each shipped '
        'pack', () {
      final manifests = TemplateResolver().availableManifests(
        shippedPackVersions().keys.toList(),
        homeDirectory: null,
      );

      expect({
        for (final e in manifests.entries) e.key: '${e.value.version}',
      }, shippedPackVersions());
    });

    test("a personal pack's available version is its "
        'home-folder pack.yaml version', () async {
      final home = await writeTree({
        '.specstone/packs/acme/pack.yaml':
            'name: acme\nversion: 1.2.0\nextends: software-tech\n',
      });

      final manifests = TemplateResolver().availableManifests([
        'acme',
      ], homeDirectory: home);

      expect('${manifests['acme']!.version}', '1.2.0');
    });

    test('a pack with no shipped name and no home folder is '
        'pack_not_found', () {
      expect(
        () => TemplateResolver().availableManifests([
          'acme',
        ], homeDirectory: null),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.packNotFound)
              .having((f) => f.key, 'key', 'packs.acme'),
        ),
      );
    });

    test('a personal pack.yaml name unequal to its folder is '
        'pack_name_mismatch', () async {
      final home = await writeTree({
        '.specstone/packs/acme/pack.yaml': 'name: other\nversion: 1.0.0\n',
      });

      expect(
        () => TemplateResolver().availableManifests([
          'acme',
        ], homeDirectory: home),
        throwsA(
          isA<TemplateFault>().having(
            (f) => f.code,
            'code',
            FaultCode.packNameMismatch,
          ),
        ),
      );
    });

    test('resolveCarried merges the named packs and the given '
        'layers and reads no config', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 0.1.0\n',
        'sub/keep': '',
      });
      final resolver = TemplateResolver();
      final inside = Directory.fromUri(project.uri.resolve('sub/'));

      final carried = IOOverrides.runZoned(
        () => resolver.resolveCarried(
          packNames: ['prd-core', 'software-tech'],
          homeDirectory: null,
        ),
        getCurrentDirectory: () => inside,
      );
      final layered = resolver.resolveCarried(
        packNames: ['prd-core', 'software-tech'],
        homeDirectory: null,
        projectLayers: [
          DocTypeLayer.parse(
            'path: prds/features/{slug}/f{nn}_{slug}/FEATURE.md\n',
            file: '.specstone/templates/feature.yaml',
            docTypeId: 'feature',
            kind: LayerKind.project,
            files: const _NoFiles(),
          ),
        ],
      );

      expect(carried.lookup('tech_stack'), isNotNull);
      expect(
        layered.lookup('feature')!.path,
        'prds/features/{slug}/f{nn}_{slug}/FEATURE.md',
      );
    });
  });

  group('TemplateResolver feature patterns', () {
    const crud = '''
id: crud
description: Create, read, update, and delete one record
items:
  - id: create
    text: Create one record
  - id: delete
    text: Delete one record
''';
    const allPacks =
        'packs:\n  prd-core: 1.1.0\n  software-tech: 1.0.0\n  nont-x: 1.0.0\n';
    const nontX = 'name: nont-x\nversion: 1.0.0\nextends: software-tech\n';

    Map<String, Uint8List> withCrud() =>
        shipped()..['software-tech/patterns/crud.yaml'] = _bytes(crud);

    Future<MergedSet> resolveTree({
      required Map<String, String> project,
      Map<String, String> home = const {},
      Map<String, Uint8List>? shippedFiles,
    }) async {
      final projectDir = await writeTree(project);
      final homeDir = await writeTree(home);
      return TemplateResolver(shippedFiles: shippedFiles ?? withCrud())
          .resolve(workingDirectory: projectDir, homeDirectory: homeDir);
    }

    test('a shipped, a personal, and a project layer merge in that order, '
        'ids matching', () async {
      final merged = await resolveTree(
        project: {
          _configPath: allPacks,
          '.specstone/templates/patterns/crud.yaml': '''
id: crud
items:
  - id: create
    disabled: true
  - id: export
    text: Export all records
''',
        },
        home: {
          '.specstone/packs/nont-x/pack.yaml': nontX,
          '.specstone/packs/nont-x/patterns/crud.yaml': '''
id: crud
items:
  - id: delete
    text: Delete one record, softly
  - id: audit
    text: Log each change
''',
        },
      );

      final pattern = merged.featurePattern('crud')!;
      expect(pattern.pack, 'software-tech');
      expect(
        pattern.description,
        'Create, read, update, and delete one record',
      );
      expect(
        [for (final item in pattern.items) (item.id, item.text)],
        [
          ('delete', 'Delete one record, softly'),
          ('audit', 'Log each change'),
          ('export', 'Export all records'),
        ],
      );
    });

    test('an id no lower layer defines is a new pattern of the defining '
        'layer', () async {
      final merged = await resolveTree(
        project: {
          _configPath:
              'packs:\n  prd-core: 1.1.0\n  software-tech: 1.0.0\n'
              '  nont-y: 1.0.0\n',
          '.specstone/templates/patterns/export.yaml': '''
id: export
description: Export records
items:
  - id: format
    text: Name the export format
''',
        },
        home: {
          '.specstone/packs/nont-y/pack.yaml': 'name: nont-y\nversion: 1.0.0\n',
          '.specstone/packs/nont-y/patterns/cart.yaml': '''
id: cart
description: Shopping cart
items:
  - id: add
    text: Add an item
''',
        },
      );

      expect(merged.featurePatterns.map((p) => p.id), [
        'cart',
        'crud',
        'export',
      ]);
      expect(merged.featurePattern('export')!.pack, isNull);
      expect(merged.featurePattern('cart')!.pack, 'nont-y');
      expect(merged.featurePattern('crud')!.pack, 'software-tech');
    });

    test('two packs defining one pattern id with no extends between them '
        'are feature_pattern_duplicate', () {
      expect(
        resolveTree(
          project: {_configPath: allPacks},
          home: {
            '.specstone/packs/nont-x/pack.yaml':
                'name: nont-x\nversion: 1.0.0\n',
            '.specstone/packs/nont-x/patterns/crud.yaml': crud,
          },
        ),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.featurePatternDuplicate)
              .having(
                (f) => f.file,
                'file',
                '~/.specstone/packs/nont-x/patterns/crud.yaml',
              )
              .having((f) => f.relatedFiles, 'relatedFiles', [
                'packs/software-tech/patterns/crud.yaml',
              ])
              .having((f) => f.message, 'message', contains('crud')),
        ),
      );
    });

    test('a pack extending another through a chain of listed packs layers '
        'its pattern over it', () async {
      final merged = await resolveTree(
        project: {
          _configPath:
              'packs:\n  prd-core: 1.1.0\n  software-tech: 1.0.0\n'
              '  nont-a: 1.0.0\n  nont-b: 1.0.0\n',
        },
        home: {
          '.specstone/packs/nont-b/pack.yaml':
              'name: nont-b\nversion: 1.0.0\nextends: software-tech\n',
          '.specstone/packs/nont-b/patterns/crud.yaml':
              'id: crud\nitems:\n  - id: from_b\n    text: B item\n',
          '.specstone/packs/nont-a/pack.yaml':
              'name: nont-a\nversion: 1.0.0\nextends: nont-b\n',
          '.specstone/packs/nont-a/patterns/crud.yaml':
              'id: crud\nitems:\n  - id: from_a\n    text: A item\n',
        },
      );

      expect(merged.featurePattern('crud')!.items.map((i) => i.id), [
        'create',
        'delete',
        'from_b',
        'from_a',
      ]);
    });

    // The test name stays one literal so specstone check can find it.
    // ignore: lines_longer_than_80_chars
    test('a file in a patterns subfolder or not ending .yaml is no pattern and stays a reference file target', () async {
      final merged = await resolveTree(
        project: {
          _configPath: allPacks,
          '.specstone/templates/patterns/sub/y.yaml': 'bogus: x\n',
          '.specstone/templates/patterns/notes.txt': 'notes\n',
        },
        home: {
          '.specstone/packs/nont-x/pack.yaml': nontX,
          '.specstone/packs/nont-x/patterns/sub/crud.yaml': 'bogus: x\n',
          '.specstone/packs/nont-x/patterns/README.md': 'readme\n',
          '.specstone/packs/nont-x/patterns/sub/guide.yaml': 'bogus: x\n',
          '.specstone/packs/nont-x/patterns/crud.yaml': '''
id: crud
reference:
  - title: Notes
    file: README.md
  - title: Guide
    file: sub/guide.yaml
''',
        },
        shippedFiles: withCrud()
          ..['software-tech/patterns/deep/x.yaml'] = _bytes('bogus: x\n')
          ..['software-tech/patterns/notes.txt'] = _bytes('notes\n'),
      );

      expect(merged.featurePatterns.map((p) => p.id), ['crud']);
      expect(merged.featurePattern('crud')!.reference.map((r) => r.file), [
        'patterns/README.md',
        'patterns/sub/guide.yaml',
      ]);
      expect(merged.docTypes.map((d) => d.id), ['architecture', 'feature']);
    });

    test('a pin at the carried pack version loads its patterns and an older '
        'pin is refused', () async {
      final merged = await resolveTree(
        project: {
          _configPath: 'packs:\n  prd-core: 1.1.0\n  software-tech: 1.0.0\n',
        },
      );
      expect(merged.featurePattern('crud'), isNotNull);

      expect(
        resolveTree(
          project: {
            _configPath: 'packs:\n  prd-core: 1.1.0\n  software-tech: 0.9.0\n',
          },
        ),
        throwsA(
          isA<TemplateFault>().having(
            (f) => f.code,
            'code',
            FaultCode.packPinOlder,
          ),
        ),
      );
    });

    test('a project listing only prd-core and holding no pattern file '
        'loads no pattern', () async {
      final merged = await resolveTree(
        project: {_configPath: 'packs:\n  prd-core: 1.1.0\n'},
      );

      expect(merged.featurePatterns, isEmpty);
      expect(merged.featurePattern('crud'), isNull);
    });

    test('a personal pattern file with CRLF line ends and a BOM loads as '
        'the LF file does', () async {
      const lf = '''
id: crud
items:
  - id: audit
    text: Log each change
''';
      final project = {_configPath: allPacks};
      final lfSet = await resolveTree(
        project: project,
        home: {
          '.specstone/packs/nont-x/pack.yaml': nontX,
          '.specstone/packs/nont-x/patterns/crud.yaml': lf,
        },
      );
      final crlfSet = await resolveTree(
        project: project,
        home: {
          '.specstone/packs/nont-x/pack.yaml': nontX,
          '.specstone/packs/nont-x/patterns/crud.yaml':
              '﻿${lf.replaceAll('\n', '\r\n')}',
        },
      );

      expect(
        crlfSet.featurePattern('crud')!.toJson(),
        lfSet.featurePattern('crud')!.toJson(),
      );
    });

    test('two personal packs holding one pattern id, neither extending the '
        'other, exit 78 naming both files', () async {
      final fault = await _resolveFault(
        project: {
          _configPath:
              'packs:\n  prd-core: 1.1.0\n  nont-a: 1.0.0\n'
              '  nont-b: 1.0.0\n',
        },
        home: {
          '.specstone/packs/nont-a/pack.yaml': 'name: nont-a\nversion: 1.0.0\n',
          '.specstone/packs/nont-a/patterns/crud.yaml': crud,
          '.specstone/packs/nont-b/pack.yaml': 'name: nont-b\nversion: 1.0.0\n',
          '.specstone/packs/nont-b/patterns/crud.yaml': crud,
        },
      );

      expect(fault.code, FaultCode.featurePatternDuplicate);
      expect(fault.exitStatus, 78);
      expect(
        [fault.file, ...fault.relatedFiles],
        unorderedEquals([
          '~/.specstone/packs/nont-a/patterns/crud.yaml',
          '~/.specstone/packs/nont-b/patterns/crud.yaml',
        ]),
      );
      expect(fault.message, contains('crud'));
    });
  });

  group('TemplateResolver pattern carriers', () {
    Future<MergedSet> resolveShipped(Map<String, String> project) async {
      final projectDir = await writeTree({
        _configPath: shippedPinsConfig(),
        ...project,
      });
      final homeDir = await writeTree({});
      return TemplateResolver().resolve(
        workingDirectory: projectDir,
        homeDirectory: homeDir,
      );
    }

    test('the shipped packs alone load with no fault', () async {
      final merged = await resolveShipped({});

      final feature = merged.lookup('feature')!;
      expect(feature.fields.any((f) => f.id == 'patterns'), isTrue);
      expect(feature.sections.any((s) => s.id == 'out_of_scope'), isTrue);
    });

    test('a project doc type with the patterns field and no out_of_scope '
        'section is refused at the project file', () {
      expect(
        resolveShipped({
          '.specstone/templates/epic.yaml': '''
id: epic
description: One epic
path: epics/{slug}.md
fields:
  - id: patterns
    type: string
    list: true
''',
        }),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.unknownValue)
              .having((f) => f.key, 'key', 'sections.out_of_scope')
              .having((f) => f.file, 'file', '.specstone/templates/epic.yaml'),
        ),
      );
    });
  });

  group('TemplateResolver.frozenDocTypes', () {
    // D12.
    test('a frozen doc type holding pattern_ref is pattern_ref_invalid at '
        'that key', () {
      final resolver = TemplateResolver(
        shippedFiles: {
          ...shipped(),
          _frozenX: _bytes(
            'id: x\ndescription: An x\npath: specs/X.md\n'
            'sections:\n  - id: goal\n    header: Goal\n'
            '    lint:\n      banned_patterns:\n'
            '        - id: a\n          pattern_ref: b\n          message: m\n',
          ),
        },
      );

      expect(
        () => resolver.frozenDocTypes(
          packNames: ['prd-core'],
          homeDirectory: null,
        ),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.patternRefInvalid)
              .having((f) => f.file, 'file', 'packs/$_frozenX')
              .having(
                (f) => f.key,
                'key',
                'sections.goal.lint.banned_patterns[0].pattern_ref',
              ),
        ),
      );
    });
  });
}
