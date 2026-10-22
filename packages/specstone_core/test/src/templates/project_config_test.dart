import 'dart:io';

import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:test/test.dart';

import '../../helpers/temp_tree.dart';

const _configPath = '.specstone/config.yaml';

TypeMatcher<TemplateFault> _fault(FaultCode code, {String? key, int? line}) =>
    isA<TemplateFault>()
        .having((f) => f.code, 'code', code)
        .having((f) => f.file, 'file', _configPath)
        .having((f) => f.key, 'key', key)
        .having((f) => f.line, 'line', line);

Future<Directory> _withConfig(String text) => writeTree({_configPath: text});

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
  group('ProjectConfig.read', () {
    test(
      'f03/us05/fr01: reads pins in file order with parsed versions',
      () async {
        final root = await _withConfig(
          'packs:\n  prd-core: 1.0.0\n  software-tech: 2.1.0\n',
        );

        final config = ProjectConfig.read(root);

        expect(config.pins.keys, ['prd-core', 'software-tech']);
        expect(config.pins['software-tech']!.toString(), '2.1.0');
        expect(config.pins['prd-core']!.major, 1);
        expect(config.file, _configPath);
      },
    );

    test('f03/us05/s5, f03/us05/fr01/e01, s03/inv7: packs without prd-core is '
        'prd_core_missing', () async {
      final root = await _withConfig('packs:\n  software-tech: 1.0.0\n');

      expect(
        () => ProjectConfig.read(root),
        throwsA(_fault(FaultCode.prdCoreMissing, key: 'packs')),
      );
    });

    test(
      'f03/us05/fr01/e02, s03/inv10: a syntax error is yaml_syntax with line 1',
      () async {
        final root = await _withConfig('packs: [');

        expect(
          () => ProjectConfig.read(root),
          throwsA(_fault(FaultCode.yamlSyntax, line: 1)),
        );
      },
    );

    test(
      'f03/us05/fr01/e03, s03/inv10: an unknown top-level key is unknown_key',
      () async {
        final root = await _withConfig('spec_packs: [x]\n');

        expect(
          () => ProjectConfig.read(root),
          throwsA(_fault(FaultCode.unknownKey, key: 'spec_packs')),
        );
      },
    );

    test(
      'f03/us05/fr01, s03/inv10: a config without packs is missing_key',
      () async {
        final root = await _withConfig('# empty\n');

        expect(
          () => ProjectConfig.read(root),
          throwsA(_fault(FaultCode.missingKey, key: 'packs')),
        );
      },
    );

    for (final (label, pin) in [
      ('an unquoted double', '1.2'),
      ('a quoted two-part version', "'1.2'"),
      ('a pre-release tag', '1.2.0-beta'),
    ]) {
      test(
        'f03/us05/fr01/e06, s03/inv16: $label pin is pack_version_invalid',
        () async {
          final root = await _withConfig('packs:\n  prd-core: $pin\n');

          expect(
            () => ProjectConfig.read(root),
            throwsA(
              _fault(FaultCode.packVersionInvalid, key: 'packs.prd-core'),
            ),
          );
        },
      );
    }

    test('f03/us05/fr01/e02: non-UTF-8 config bytes are yaml_syntax', () async {
      final root = await writeTree({});
      final config = File.fromUri(root.uri.resolve(_configPath));
      await config.create(recursive: true);
      await config.writeAsBytes([0xff, 0xfe]);

      expect(
        () => ProjectConfig.read(root),
        throwsA(
          _fault(FaultCode.yamlSyntax).having((f) => f.line, 'line', isNull),
        ),
      );
    });

    test('f03/us05/fr01/e02: a CRLF config reads its pins', () async {
      final root = await _withConfig(
        'packs:\r\n  prd-core: 1.0.0\r\n  software-tech: 2.1.0\r\n',
      );

      final config = ProjectConfig.read(root);

      expect(config.pins.keys, ['prd-core', 'software-tech']);
    });
  });

  group('findProjectRoot', () {
    test('f03/us01/fr04: finds the config in an ancestor folder', () async {
      final root = await writeTree({_configPath: 'packs: {}\n'});
      final start = Directory.fromUri(root.uri.resolve('docs/prds/'));
      await start.create(recursive: true);

      expect(findProjectRoot(start)?.uri, root.uri);
    });

    test(
      'f03/us01/fr04/e01: no config in any ancestor gives null',
      () async {
        final root = await writeTree({});

        expect(findProjectRoot(root), isNull);
      },
      skip: _tempHasConfigAncestor()
          ? 'an ancestor of the system temp folder holds $_configPath'
          : false,
    );

    test('f03/us01/fr04/e02: the nearest config wins', () async {
      final root = await writeTree({
        _configPath: 'packs: {}\n',
        'sub/$_configPath': 'packs: {}\n',
      });
      final start = Directory.fromUri(root.uri.resolve('sub/x/'));
      await start.create(recursive: true);

      expect(
        findProjectRoot(start)?.uri,
        Directory.fromUri(root.uri.resolve('sub/')).uri,
      );
    });

    test(
      'f03/us01/fr04/e03: a .specstone folder without config.yaml is skipped',
      () async {
        final root = await writeTree({
          _configPath: 'packs: {}\n',
          'a/.specstone/notes.txt': 'x',
        });
        final start = Directory.fromUri(root.uri.resolve('a/'));

        expect(findProjectRoot(start)?.uri, root.uri);
      },
    );
  });
}
