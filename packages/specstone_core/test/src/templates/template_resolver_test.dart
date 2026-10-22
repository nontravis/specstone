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
      },
    );

    test('f03/us03/fr03: a personal pack reference to a nested file resolves '
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

    test('f03/us03/fr03: a shipped pack reference to a nested file resolves '
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

    test('s03/inv22: two faulty project templates fault the first by code '
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

    test(
      'f03/us03/fr01: non-doc-type project files are ignored as doc types',
      () async {
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
      },
    );

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

    test('f03/us05/fr02/e01: a shipped pin fault wins over a bad doc-type file '
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

    test('f03/us04/fr01/e07: a personal pack_name_mismatch wins over a bad '
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

    test('s03/inv22: a pin fault wins over a doc-type fault in the other '
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

    test(
      'f03/us04/fr01/e04: an absent personal pack.yaml is missing_key',
      () async {
        final project = await writeTree({
          _configPath: 'packs:\n  prd-core: 1.1.0\n  nont-software: 1.0.0\n',
        });
        final home = await writeTree({
          '.specstone/packs/nont-software/runbook.yaml': 'description: R\n',
        });
        final resolver = TemplateResolver(shippedFiles: shipped());

        expect(
          () =>
              resolver.resolve(workingDirectory: project, homeDirectory: home),
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
      },
    );

    test('f03/us04/s6, f03/us04/fr02/e01, f03/us02/fr01/e08: a personal pack '
        'and a shipped pack with one doc type id, no extends, are '
        'doc_type_duplicate', () async {
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

    test('f03/us04/s1, f03/us04/fr02/e02, f03/us04/fr01, f03/us03/fr04: an '
        'extending personal pack layers its same-id doc type over the shipped '
        'one', () async {
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

    test('f03/us04/fr02/e05, f03/us02/fr01/e09, f03/us04/fr01/e10: a chain '
        'three packs deep layers top down', () async {
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
      expect(architecture.files, [
        'packs/software-tech/architecture.yaml',
        '~/.specstone/packs/nont-flutter/architecture.yaml',
      ]);
    });

    test('f03/us04/s3, f03/us04/fr01/e05: the project layer wins over the '
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

    test('f03/us04/fr01/e09: two personal packs extending one pack are '
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

    test('f03/us03/fr04/e02: an extends naming no loaded pack is '
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

    test('f03/us03/fr04/e01: a pack chain back to its start is '
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

    test('f03/us04/fr02/e03, f03/us03/fr02/e01: a project template with a '
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

    test('f03/us04/s2, f03/us04/s6, f03/us04/fr02: resolve end to end '
        'layers chain, project, and duplicates', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n  nont-x: 1.0.0\n',
        '.specstone/templates/feature.yaml': 'description: Project feature\n',
      });
      final home = await writeTree({
        '.specstone/packs/nont-x/pack.yaml':
            'name: nont-x\nversion: 1.0.0\nextends: prd-core\n',
        '.specstone/packs/nont-x/feature.yaml': 'description: Mine\n',
      });
      final resolver = TemplateResolver(shippedFiles: shipped());

      final merged = resolver.resolve(
        workingDirectory: project,
        homeDirectory: home,
      );

      expect(merged.lookup('feature')!.description, 'Project feature');
      expect(merged.lookup('architecture'), isNull);
    });

    test('f03/us03/s1, f03/us03/fr02: a project template with a new id '
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
        'reference',
      ]);
      expect(runbook.sections.single.id, 'steps');
    });

    test(
      'f03/us03/s9, f03/us03/fr02/e04, f03/us03/fr01/e07: a new doc type '
      'without path, or without description and extends, is missing_key',
      () async {
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
          () =>
              resolver.resolve(workingDirectory: project, homeDirectory: home),
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
                .having((f) => f.key, 'key', 'description'),
          ),
        );
      },
    );

    test('f03/us03/fr01/e08, f03/us03/fr04/e05, f03/us03/fr02/e03: a new '
        'doc type with extends inherits every key of the target except id '
        'and path (F3-D49)', () async {
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

    test('f03/us03/fr04/e05: an extending doc type writes its own parent and '
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

    test('f03/us03/fr04: an extending doc type changes inherited lists by '
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

    test('f03/us02/fr03/e06, f03/us02/fr05/e04: a plain list over an '
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

    test('f03/us03/fr01/e07: an extending doc type without path is '
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

    test('f03/us03/s2, f03/us03/fr04: an extending doc type adds a section '
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

    test('f03/us03/fr04/e03: an extending doc type changes a section of its '
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

    test('f03/us03/fr04/e04: an extending entry whose id the target lacks '
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

    test('f03/us03/fr04/e06, s03/inv4: a layer above the defining layer '
        'writes extends is extends_in_override', () async {
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

    test('f03/us03/fr04/e06, s03/inv4: several layers above the defining '
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

    test('f03/us03/fr04/e06, s03/inv4: extends_in_override faults the first '
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

    test('f03/us03/s6, f03/us03/fr04/e01: a doc type extending itself is '
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

    test('f03/us03/s7, f03/us03/fr04/e02: an extends naming no doc type is '
        'extends_target_unknown', () async {
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
              .having((f) => f.file, 'file', '.specstone/templates/adr.yaml'),
        ),
      );
    });

    test('f03/us03/s6, f03/us03/fr04/e01: a doc-type extends loop is '
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

    test('f03/us03/s6, f03/us03/fr04/e01, s03/inv22: a doc-type extends loop '
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

    test('s03/inv5, s03/inv22: a shipped pack extending another shipped pack '
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

    test('f03/us03/fr02/e05: a new doc type with no parent is a top-level '
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

    test('f03/us03/fr01/e11, f03/us03/fr02/e06: two doc types with one path '
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

    test('f03/us03/fr02/e06, s03/inv19: a project doc type sharing a shipped '
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

    test('f03/us03/fr02/e06, s03/inv22: a path conflict names the file that '
        'loads later by path, not by doc type id', () async {
      final project = await writeTree({
        _configPath: 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/run.yaml': '''
id: run
description: A run
path: ops/{slug}/RUN.md
''',
        '.specstone/templates/run-book.yaml': '''
id: run-book
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
              .having((f) => f.file, 'file', '.specstone/templates/run.yaml')
              .having((f) => f.relatedFiles, 'relatedFiles', [
                '.specstone/templates/run-book.yaml',
              ]),
        ),
      );
    });

    test('f03/us03/fr01/e12, f03/us02/fr04/e05: a parent naming no id is '
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

    test('f03/us02/fr04/e04: overriding parent with an existing id is '
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

    test('f03/us03/fr01/e13: a parent loop is parent_cycle; a self parent '
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

    test('f03/us03/fr01/e13, s03/inv22: a parent loop across layers names the '
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

    test('f03/us03/fr01/e14: a doc_types entry naming no id is '
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

    test('f03/us04/fr02/e04: a project adr extends a pack-defined feature '
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

    test(
      's03/inv4: every list of an extends-built doc type is unmodifiable',
      () async {
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
      },
    );
  });
}
