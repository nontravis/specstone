import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/temp_tree.dart';

const _configPath = '.specstone/config.yaml';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

/// The shipped fixture: `prd-core` holds `feature`, `software-tech` holds
/// `architecture`.
Map<String, Uint8List> shipped({String prdCoreVersion = '1.1.0'}) => {
  'prd-core/pack.yaml': _bytes('name: prd-core\nversion: $prdCoreVersion\n'),
  'prd-core/feature.yaml': _bytes('description: A feature\n'),
  'software-tech/pack.yaml': _bytes('name: software-tech\nversion: 1.0.0\n'),
  'software-tech/architecture.yaml': _bytes('description: Architecture\n'),
};

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

void main() {
  group('TemplateResolver.resolve', () {
    test('f03/us05/s3, f03/us05/fr02/e01, f03/us01/fr01/e03: '
        'an older shipped pin is pack_pin_older', () async {
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

    test(
      'f03/us05/s1, f03/us05/fr02: equal pins resolve the listed packs',
      () async {
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
      },
    );

    test(
      'f03/us05/s4, f03/us05/fr02/e02: a newer pin is pack_pin_newer',
      () async {
        final project = await writeTree({
          _configPath: 'packs:\n  prd-core: 2.0.0\n',
        });
        final home = await writeTree({});
        final resolver = TemplateResolver(shippedFiles: shipped());

        expect(
          () =>
              resolver.resolve(workingDirectory: project, homeDirectory: home),
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
      },
    );

    test('f03/us05/fr01, f03/us05/fr01/e05, f03/us02/fr01/e07: '
        'an unlisted shipped pack never loads', () async {
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
      'f03/us01/s5, f03/us01/fr01/e01, f03/us01/fr02/e03, f03/us05/fr02/e05, '
      'f03/us05/fr01/e04: no project root loads every shipped pack',
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

    test('f03/us04/s4, f03/us04/fr01/e01: a missing personal pack is pack_not_found', () async {
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

    test(
      'f03/us04/s5, f03/us04/fr01/e02, f03/us05/fr02/e06: '
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

    test('f03/us04/fr01/e07: a pack.yaml name unequal to the folder is '
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

    test('f03/us04/s2, f03/us04/fr01/e03, f03/us02/fr01/e06: '
        'an unlisted personal pack never loads', () async {
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

    test(
      'f03/us04/fr01: a listed personal pack adds its doc types with its pack',
      () async {
        final project = await writeTree({
          _configPath: 'packs:\n  prd-core: 1.1.0\n  nont-software: 1.0.0\n',
        });
        final home = await writeTree({
          '.specstone/packs/nont-software/pack.yaml':
              'name: nont-software\nversion: 1.0.0\n',
          '.specstone/packs/nont-software/runbook.yaml':
              'description: Runbook\n',
        });
        final resolver = TemplateResolver(shippedFiles: shipped());

        final merged = resolver.resolve(
          workingDirectory: project,
          homeDirectory: home,
        );

        expect(merged.lookup('runbook')!.pack, 'nont-software');
        expect(merged.lookup('runbook')!.description, 'Runbook');
      },
    );

    test(
      'a personal pack reference to a nested file resolves against disk',
      () async {
        final project = await writeTree({
          _configPath: 'packs:\n  prd-core: 1.1.0\n  nont-software: 1.0.0\n',
        });
        final home = await writeTree({
          '.specstone/packs/nont-software/pack.yaml':
              'name: nont-software\nversion: 1.0.0\n',
          '.specstone/packs/nont-software/runbook.yaml': '''
description: Runbook
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
      },
    );

    test(
      'a shipped pack reference to a nested file resolves against the map',
      () async {
        final files = shipped()
          ..['prd-core/refs/handbook.md'] = _bytes('# Handbook\n');
        files['prd-core/feature.yaml'] = _bytes('''
description: A feature
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
      },
    );

    test(
      'f03/us05/fr02/e04: a template fault in the project layer is thrown',
      () async {
        final project = await writeTree({
          _configPath: 'packs:\n  prd-core: 1.1.0\n',
          '.specstone/templates/feature.yaml': 'bogus: x\n',
        });
        final home = await writeTree({});
        final resolver = TemplateResolver(shippedFiles: shipped());

        expect(
          () =>
              resolver.resolve(workingDirectory: project, homeDirectory: home),
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
      },
    );

    test(
      'f03/us05/fr02/e07: a second resolve reads the new config, no cache',
      () async {
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
          () =>
              resolver.resolve(workingDirectory: project, homeDirectory: home),
          throwsA(
            isA<TemplateFault>().having(
              (f) => f.code,
              'code',
              FaultCode.packPinNewer,
            ),
          ),
        );
      },
    );

    test('f03/s03/inv22: two faulty project templates fault the first by code '
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

    test('f03/us03/fr03/e03: a project reference to a missing file is '
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
  });
}
