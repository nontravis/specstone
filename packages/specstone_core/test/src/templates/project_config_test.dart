import 'dart:io';

import 'package:specstone_core/src/templates/code_target.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:test/test.dart';

import '../../helpers/fixture_doc_types.dart';
import '../../helpers/relative_link.dart';
import '../../helpers/temp_tree.dart';

const _configPath = '.specstone/config.yaml';

TypeMatcher<TemplateFault> _fault(FaultCode code, {String? key, int? line}) =>
    isA<TemplateFault>()
        .having((f) => f.code, 'code', code)
        .having((f) => f.file, 'file', _configPath)
        .having((f) => f.key, 'key', key)
        .having((f) => f.line, 'line', line);

/// The root a project is found at is canonical, as a `docs` link makes it.
String _canonical(Directory dir) => dir.resolveSymbolicLinksSync();

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

    for (final (name, text, key) in [
      ('a path-escape key', 'prd-core: 1.0.0\n  ../x: 1.0.0', 'packs.../x'),
      (
        'an upper-case or underscore key',
        'prd-core: 1.0.0\n  My_Pack: 1.0.0',
        'packs.My_Pack',
      ),
      (
        'a doubled or leading hyphen, first in file order',
        'prd-core: 1.0.0\n  a--b: 1.0.0\n  -a: 1.0.0',
        'packs.a--b',
      ),
      (
        'a bad key before its bad pin',
        'My_Pack: 1.2\n  prd-core: 1.0.0',
        'packs.My_Pack',
      ),
      (
        'a bad key instead of prd_core_missing',
        'My_Pack: 1.0.0',
        'packs.My_Pack',
      ),
    ]) {
      test('f03/us05/fr01/e08: $name is unknown_key', () async {
        final root = await _withConfig('packs:\n  $text\n');

        expect(
          () => ProjectConfig.read(root),
          throwsA(
            _fault(
              FaultCode.unknownKey,
              key: key,
            ).having((f) => f.code.exitStatus, 'exitStatus', 78),
          ),
        );
      });
    }

    test('f03/us05/fr01: a kebab-case key with digits reads', () async {
      final root = await _withConfig(
        'packs:\n  prd-core: 1.0.0\n  tech-2: 1.0.0\n',
      );

      expect(ProjectConfig.read(root).pins.keys, ['prd-core', 'tech-2']);
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

    test('code_root defaults to .', () async {
      final root = await _withConfig('packs:\n  prd-core: 1.0.0\n');

      expect(ProjectConfig.read(root).codeRoot, '.');
    });

    test('f06/us01/fr05/e10: hasCodeRoot is true for code_root: . and false '
        'with no key', () async {
      final written = await _withConfig(
        'packs:\n  prd-core: 1.0.0\ncode_root: .\n',
      );
      final absent = await _withConfig('packs:\n  prd-core: 1.0.0\n');

      expect(ProjectConfig.read(written).hasCodeRoot, isTrue);
      expect(ProjectConfig.read(written).codeRoot, '.');
      expect(ProjectConfig.read(absent).hasCodeRoot, isFalse);
    });

    for (final value in ['stratum_ui', '../stratum_ui/example']) {
      test('reads code_root: $value', () async {
        final root = await _withConfig(
          'packs:\n  prd-core: 1.0.0\ncode_root: $value\n',
        );

        expect(ProjectConfig.read(root).codeRoot, value);
      });
    }

    for (final (name, line) in [
      ('a rooted path', 'code_root: /abs'),
      ('a drive-letter path', 'code_root: C:/abs'),
      ('a backslash', r"code_root: 'a\b'"),
      ('a trailing dot', "code_root: 'src.'"),
      ('a trailing space', "code_root: 'src '"),
      ('a non-string', 'code_root: [a]'),
      ('an empty string', "code_root: ''"),
    ]) {
      test('rejects $name as code_root', () async {
        final root = await _withConfig('packs:\n  prd-core: 1.0.0\n$line\n');

        expect(
          () => ProjectConfig.read(root),
          throwsA(
            _fault(
              FaultCode.unknownValue,
              key: 'code_root',
            ).having((f) => f.code.exitStatus, 'exitStatus', 78),
          ),
        );
      });
    }

    group('agent_file_roots', () {
      for (final value in ['', ' ~', ' null']) {
        test('template_packs/pin_pack_versions/read_project_config: '
            '`agent_file_roots:$value` reads as an empty list', () async {
          final root = await _withConfig(
            'packs:\n  prd-core: 1.0.0\nagent_file_roots:$value\n',
          );

          expect(ProjectConfig.read(root).agentFileRoots, isEmpty);
        });
      }

      test('template_packs/pin_pack_versions/read_project_config: entries read '
          'back as written, without normalizing or dedup', () async {
        final root = await _withConfig(
          'packs:\n  prd-core: 1.0.0\nagent_file_roots: [./a, ./a, a/]\n',
        );

        expect(ProjectConfig.read(root).agentFileRoots, ['./a', './a', 'a/']);
      });

      test('template_packs/pin_pack_versions/read_project_config E16: no agent_file_roots key reads as an empty list', () async {
        final root = await _withConfig('packs:\n  prd-core: 1.0.0\n');

        expect(ProjectConfig.read(root).agentFileRoots, isEmpty);
      });

      test('template_packs/pin_pack_versions/read_project_config E17: an entry outside the project root is accepted', () async {
        final root = await _withConfig(
          'packs:\n  prd-core: 1.0.0\nagent_file_roots: [../stratum_ui]\n',
        );

        expect(ProjectConfig.read(root).agentFileRoots, ['../stratum_ui']);
      });

      for (final (name, line) in [
        ('a scalar value', 'agent_file_roots: ../stratum_ui'),
        ('a number value', 'agent_file_roots: 3'),
        ('a rooted entry', 'agent_file_roots: [/srv/code]'),
        ('a drive-letter entry', 'agent_file_roots: [C:/code]'),
        ('a backslash entry', r"agent_file_roots: ['..\stratum_ui']"),
        ('an empty entry', "agent_file_roots: ['']"),
        ('an entry ending in a dot', "agent_file_roots: ['vendor/lib.']"),
        ('an entry ending in a space', "agent_file_roots: ['vendor ']"),
        ('a non-string entry', 'agent_file_roots: [3]'),
      ]) {
        test(
          'template_packs/pin_pack_versions/read_project_config E18-E21: $name is unknown_value',
          () async {
            final root = await _withConfig(
              'packs:\n  prd-core: 1.0.0\n$line\n',
            );

            expect(
              () => ProjectConfig.read(root),
              throwsA(
                _fault(
                  FaultCode.unknownValue,
                  key: 'agent_file_roots',
                ).having((f) => f.code.exitStatus, 'exitStatus', 78),
              ),
            );
          },
        );
      }
    });

    group('targets', () {
      test('template_packs/pin_pack_versions/read_project_config E23: two '
          'targets read in file order, each with its own code root', () async {
        final root = await _withConfig(
          'packs:\n  prd-core: 1.0.0\n'
          'targets:\n  flutter:\n    code_root: stratum_ui\n'
          '  jaspr:\n    code_root: jaspr-stratum-ui\n',
        );

        final config = ProjectConfig.read(root);

        expect(config.targets, [
          const CodeTarget('flutter', codeRoot: 'stratum_ui'),
          const CodeTarget('jaspr', codeRoot: 'jaspr-stratum-ui'),
        ]);
      });

      test(
        'template_packs/pin_pack_versions/read_project_config E24, s03/inv29: '
        'targets beside code_root is unknown_value at code_root',
        () async {
          final root = await _withConfig(
            'packs:\n  prd-core: 1.0.0\ncode_root: lib\n'
            'targets:\n  flutter:\n    code_root: stratum_ui\n',
          );

          expect(
            () => ProjectConfig.read(root),
            throwsA(
              _fault(
                FaultCode.unknownValue,
                key: 'code_root',
              ).having((f) => f.code.exitStatus, 'exitStatus', 78),
            ),
          );
        },
      );

      for (final (name, line) in [
        ('an empty map', 'targets: {}'),
        ('a null value', 'targets:'),
        ('a list value', 'targets: [flutter]'),
        ('a scalar value', 'targets: flutter'),
      ]) {
        test('template_packs/pin_pack_versions/read_project_config E25, s03/inv29: '
            'targets as $name is unknown_value at targets', () async {
          final root = await _withConfig('packs:\n  prd-core: 1.0.0\n$line\n');

          expect(
            () => ProjectConfig.read(root),
            throwsA(
              _fault(
                FaultCode.unknownValue,
                key: 'targets',
              ).having((f) => f.code.exitStatus, 'exitStatus', 78),
            ),
          );
        });
      }

      for (final (name, key, line) in [
        (
          'an upper-case name',
          'targets.Flutter',
          '  Flutter:\n    code_root: a\n',
        ),
        (
          'a hyphenated name',
          'targets.jaspr-ui',
          '  jaspr-ui:\n    code_root: a\n',
        ),
      ]) {
        test('template_packs/pin_pack_versions/read_project_config E26, s03/inv29: '
            '$name is unknown_key', () async {
          final root = await _withConfig(
            'packs:\n  prd-core: 1.0.0\ntargets:\n$line',
          );

          expect(
            () => ProjectConfig.read(root),
            throwsA(
              _fault(
                FaultCode.unknownKey,
                key: key,
              ).having((f) => f.code.exitStatus, 'exitStatus', 78),
            ),
          );
        });
      }

      test(
        'Review Focus 1: a name differing from another only in letter case is '
        'refused by the slug rule, so no two spec trees share a folder',
        () async {
          final root = await _withConfig(
            'packs:\n  prd-core: 1.0.0\n'
            'targets:\n  flutter:\n    code_root: a\n'
            '  Flutter:\n    code_root: b\n',
          );

          expect(
            () => ProjectConfig.read(root),
            throwsA(_fault(FaultCode.unknownKey, key: 'targets.Flutter')),
          );
        },
      );

      for (final (name, code, key, line) in [
        (
          'a scalar target value',
          FaultCode.unknownValue,
          'targets.flutter',
          '  flutter: stratum_ui\n',
        ),
        (
          'a key other than code_root in a target',
          FaultCode.unknownKey,
          'targets.flutter.name',
          '  flutter:\n    code_root: a\n    name: x\n',
        ),
        (
          'an absolute code_root',
          FaultCode.unknownValue,
          'targets.flutter.code_root',
          '  flutter:\n    code_root: /srv/code\n',
        ),
        (
          'a code_root with a backslash',
          FaultCode.unknownValue,
          'targets.flutter.code_root',
          "  flutter:\n    code_root: 'a\\b'\n",
        ),
        (
          'an empty code_root',
          FaultCode.unknownValue,
          'targets.flutter.code_root',
          "  flutter:\n    code_root: ''\n",
        ),
        (
          'a non-string code_root',
          FaultCode.unknownValue,
          'targets.flutter.code_root',
          '  flutter:\n    code_root: 3\n',
        ),
      ]) {
        test(
          'template_packs/pin_pack_versions/read_project_config E27: $name',
          () async {
            final root = await _withConfig(
              'packs:\n  prd-core: 1.0.0\ntargets:\n$line',
            );

            expect(
              () => ProjectConfig.read(root),
              throwsA(
                _fault(
                  code,
                  key: key,
                ).having((f) => f.code.exitStatus, 'exitStatus', 78),
              ),
            );
          },
        );
      }

      test(
        'template_packs/pin_pack_versions/read_project_config E27: a target '
        'with no code_root key reads the project root, as code_root does',
        () async {
          final root = await _withConfig(
            'packs:\n  prd-core: 1.0.0\ntargets:\n  flutter: {}\n',
          );

          expect(ProjectConfig.read(root).targets, [
            const CodeTarget('flutter', codeRoot: '.'),
          ]);
        },
      );

      test(
        'template_packs/pin_pack_versions/read_project_config E28, s03/inv29: '
        'two targets whose code roots name one folder are unknown_value '
        'naming both',
        () async {
          final root = await _withConfig(
            'packs:\n  prd-core: 1.0.0\n'
            'targets:\n  flutter:\n    code_root: .\n'
            '  jaspr:\n    code_root: ./\n',
          );

          Object? thrown;
          try {
            ProjectConfig.read(root);
          } on TemplateFault catch (fault) {
            thrown = fault;
          }

          expect(
            thrown,
            isA<TemplateFault>()
                .having((f) => f.code, 'code', FaultCode.unknownValue)
                .having((f) => f.key, 'key', 'targets')
                .having((f) => f.code.exitStatus, 'exitStatus', 78)
                .having((f) => f.message, 'message', contains('flutter'))
                .having((f) => f.message, 'message', contains('jaspr')),
          );
        },
      );

      test(
        'template_packs/pin_pack_versions/read_project_config E29: one entry '
        'gives one named target and codeRoot reads its root',
        () async {
          final root = await _withConfig(
            'packs:\n  prd-core: 1.0.0\ntargets:\n  flutter:\n'
            '    code_root: stratum_ui\n',
          );

          final config = ProjectConfig.read(root);

          expect(config.targets, [
            const CodeTarget('flutter', codeRoot: 'stratum_ui'),
          ]);
          expect(config.codeRoot, 'stratum_ui');
          expect(config.hasCodeRoot, isFalse);
        },
      );

      test(
        'template_packs/pin_pack_versions/read_project_config E30: targets in '
        'a merged set with no record doc type is unknown_value at targets',
        () async {
          final root = await _withConfig(
            'packs:\n  prd-core: 1.0.0\n'
            'targets:\n  flutter:\n    code_root: stratum_ui\n',
          );
          final set = await fixtureDocTypes();

          expect(
            () => ProjectConfig.read(root, mergedSet: set),
            throwsA(
              _fault(
                FaultCode.unknownValue,
                key: 'targets',
              ).having((f) => f.code.exitStatus, 'exitStatus', 78),
            ),
          );
        },
      );

      test(
        'template_packs/pin_pack_versions/read_project_config: no targets key '
        'gives one unnamed target at code_root',
        () async {
          final root = await _withConfig(
            'packs:\n  prd-core: 1.0.0\ncode_root: stratum_ui\n',
          );

          final config = ProjectConfig.read(root);

          expect(config.targets, [
            const CodeTarget(null, codeRoot: 'stratum_ui'),
          ]);
          expect(config.codeRoot, 'stratum_ui');
        },
      );
    });

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

      expect(_canonical(findProjectRoot(start)!), _canonical(root));
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
        _canonical(findProjectRoot(start)!),
        _canonical(Directory.fromUri(root.uri.resolve('sub/'))),
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

        expect(_canonical(findProjectRoot(start)!), _canonical(root));
      },
    );
  });

  group('findProjectRoot through a docs link', () {
    Directory at(Directory tree, String path) =>
        Directory('${tree.path}/$path');

    /// Links `ws/code/<folder>/docs` to `<target>`; false when links need
    /// privileges the machine lacks.
    bool link(Directory tree, String folder, String target) {
      final path = [
        '${tree.path}/ws/code',
        if (folder.isNotEmpty) folder,
        'docs',
      ];
      try {
        createRelativeLink(path.join('/'), target);
        return true;
      } on FileSystemException {
        markTestSkipped('symbolic links need privileges on this machine');
        return false;
      }
    }

    test('finds the workspace from the code folder', () async {
      final tree = await writeTree({
        'ws/$_configPath': 'packs: {}\n',
        'ws/docs/keep.txt': '',
        'ws/code/lib/keep.txt': '',
      });
      if (!link(tree, '', '../docs')) return;

      final found = findProjectRoot(at(tree, 'ws/code'));

      expect(_canonical(found!), _canonical(at(tree, 'ws')));
    });

    test('finds the nested project, not the outer one', () async {
      final tree = await writeTree({
        'ws/$_configPath': 'packs: {}\n',
        'ws/docs/keep.txt': '',
        'ws/example/$_configPath': 'packs: {}\n',
        'ws/example/docs/keep.txt': '',
        'ws/code/example/keep.txt': '',
      });
      if (!link(tree, '', '../docs')) return;
      if (!link(tree, 'example', '../../example/docs')) return;

      final found = findProjectRoot(at(tree, 'ws/code/example'));

      expect(_canonical(found!), _canonical(at(tree, 'ws/example')));
    });

    test("prefers the link's project over the folder's own config", () async {
      final tree = await writeTree({
        'ws/$_configPath': 'packs: {}\n',
        'ws/docs/keep.txt': '',
        'ws/code/$_configPath': 'packs: {}\n',
      });
      if (!link(tree, '', '../docs')) return;

      final found = findProjectRoot(at(tree, 'ws/code'));

      expect(_canonical(found!), _canonical(at(tree, 'ws')));
    });

    test('a dangling link stands for the folder itself', () async {
      final tree = await writeTree({'ws/code/$_configPath': 'packs: {}\n'});
      if (!link(tree, '', '../missing')) return;

      final found = findProjectRoot(at(tree, 'ws/code'));

      expect(_canonical(found!), _canonical(at(tree, 'ws/code')));
    });

    test('a folder with its own config whose docs link leaves every project '
        'is its own root', () async {
      final tree = await writeTree({
        'ws/code/$_configPath': 'packs: {}\n',
        'plain/docs/keep.txt': '',
      });
      if (!link(tree, '', '../../plain/docs')) return;

      final found = findProjectRoot(at(tree, 'ws/code'));

      expect(_canonical(found!), _canonical(at(tree, 'ws/code')));
    });
  });
}
