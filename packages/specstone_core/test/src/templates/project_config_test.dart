import 'dart:io';

import 'package:specstone_core/src/templates/cleanup_bounds.dart';
import 'package:specstone_core/src/templates/code_target.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:test/test.dart';

import '../../helpers/relative_link.dart';
import '../../helpers/temp_tree.dart';

const _configPath = '.specstone/config.yaml';

final String? _linksUnavailable = Platform.isWindows
    ? 'a link needs a privilege on Windows'
    : null;

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
    test('reads pins in file order with parsed versions', () async {
      final root = await _withConfig(
        'packs:\n  prd-core: 1.0.0\n  software-tech: 2.1.0\n',
      );

      final config = ProjectConfig.read(root);

      expect(config.pins.keys, ['prd-core', 'software-tech']);
      expect(config.pins['software-tech']!.toString(), '2.1.0');
      expect(config.pins['prd-core']!.major, 1);
      expect(config.file, _configPath);
    });

    test('packs without prd-core is '
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
      test('$name as a packs key is unknown_key', () async {
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

    test('a kebab-case key with digits reads', () async {
      final root = await _withConfig(
        'packs:\n  prd-core: 1.0.0\n  tech-2: 1.0.0\n',
      );

      expect(ProjectConfig.read(root).pins.keys, ['prd-core', 'tech-2']);
    });

    test('a syntax error is yaml_syntax with line 1', () async {
      final root = await _withConfig('packs: [');

      expect(
        () => ProjectConfig.read(root),
        throwsA(_fault(FaultCode.yamlSyntax, line: 1)),
      );
    });

    test('an unknown top-level key is unknown_key', () async {
      final root = await _withConfig('spec_packs: [x]\n');

      expect(
        () => ProjectConfig.read(root),
        throwsA(_fault(FaultCode.unknownKey, key: 'spec_packs')),
      );
    });

    test('an unknown top-level key exits 78', () async {
      final root = await _withConfig('spec_packs: [x]\n');

      expect(
        () => ProjectConfig.read(root),
        throwsA(
          _fault(
            FaultCode.unknownKey,
            key: 'spec_packs',
          ).having((f) => f.code.exitStatus, 'exitStatus', 78),
        ),
      );
    });

    test('code_root defaults to .', () async {
      final root = await _withConfig('packs:\n  prd-core: 1.0.0\n');

      expect(ProjectConfig.read(root).codeRoot, '.');
    });

    test('hasCodeRoot is true for code_root: . and false '
        'with no key', () async {
      final written = await _withConfig(
        'packs:\n  prd-core: 1.0.0\ncode_root: .\n',
      );
      final absent = await _withConfig('packs:\n  prd-core: 1.0.0\n');

      expect(ProjectConfig.read(written).hasCodeRoot, isTrue);
      expect(ProjectConfig.read(written).codeRoot, '.');
      expect(ProjectConfig.read(absent).hasCodeRoot, isFalse);
    });

    test('a code_root key with no value reads as the project root', () async {
      final root = await _withConfig('packs:\n  prd-core: 1.0.0\ncode_root:\n');

      expect(ProjectConfig.read(root).codeRoot, '.');
    });

    test('code_root: 3 is unknown_value', () async {
      final root = await _withConfig(
        'packs:\n  prd-core: 1.0.0\ncode_root: 3\n',
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
        test('Read the project config: '
            '`agent_file_roots:$value` reads as an empty list', () async {
          final root = await _withConfig(
            'packs:\n  prd-core: 1.0.0\nagent_file_roots:$value\n',
          );

          expect(ProjectConfig.read(root).agentFileRoots, isEmpty);
        });
      }

      test('entries read '
          'back as written, without normalizing or dedup', () async {
        final root = await _withConfig(
          'packs:\n  prd-core: 1.0.0\nagent_file_roots: [./a, ./a, a/]\n',
        );

        expect(ProjectConfig.read(root).agentFileRoots, ['./a', './a', 'a/']);
      });

      test('no agent_file_roots key reads as an empty list', () async {
        final root = await _withConfig('packs:\n  prd-core: 1.0.0\n');

        expect(ProjectConfig.read(root).agentFileRoots, isEmpty);
      });

      test('an entry outside the project root is accepted', () async {
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
        test('$name is unknown_value for agent_file_roots', () async {
          final root = await _withConfig('packs:\n  prd-core: 1.0.0\n$line\n');

          expect(
            () => ProjectConfig.read(root),
            throwsA(
              _fault(
                FaultCode.unknownValue,
                key: 'agent_file_roots',
              ).having((f) => f.code.exitStatus, 'exitStatus', 78),
            ),
          );
        });
      }
    });

    group('agent_files_version', () {
      test('no agent_files_version key reads as no stamp', () async {
        final root = await _withConfig('packs:\n  prd-core: 1.0.0\n');

        expect(ProjectConfig.read(root).agentFilesVersion, isNull);
      });

      for (final value in ['', ' ~', ' null']) {
        test('`agent_files_version:$value` reads as no stamp', () async {
          final root = await _withConfig(
            'packs:\n  prd-core: 1.0.0\nagent_files_version:$value\n',
          );

          expect(ProjectConfig.read(root).agentFilesVersion, isNull);
        });
      }

      for (final text in ['1.3.0', '1.3.0-beta.2', '0.0.1']) {
        test('$text reads as that Version', () async {
          final root = await _withConfig(
            'packs:\n  prd-core: 1.0.0\nagent_files_version: $text\n',
          );

          expect(ProjectConfig.read(root).agentFilesVersion.toString(), text);
        });
      }

      for (final (name, line) in [
        ('a two-field number', 'agent_files_version: 1.3'),
        ('a whole number', 'agent_files_version: 3'),
        ('a quoted two-field value', "agent_files_version: '1.3'"),
        ('a leading-zero field', 'agent_files_version: 01.3.0'),
        ('a build suffix', 'agent_files_version: 1.3.0+5'),
        ('a list', 'agent_files_version: [1.3.0]'),
        ('text', 'agent_files_version: latest'),
      ]) {
        test('$name is unknown_value for agent_files_version', () async {
          final root = await _withConfig('packs:\n  prd-core: 1.0.0\n$line\n');

          expect(
            () => ProjectConfig.read(root),
            throwsA(
              _fault(
                FaultCode.unknownValue,
                key: 'agent_files_version',
              ).having((f) => f.code.exitStatus, 'exitStatus', 78),
            ),
          );
        });
      }
    });

    group('verification_coverage', () {
      test('verification coverage defaults to off', () async {
        final root = await _withConfig('packs:\n  prd-core: 1.0.0\n');

        expect(ProjectConfig.read(root).verificationCoverage, isFalse);
      });

      for (final (text, expected) in [
        ('', false),
        (' ~', false),
        (' false', false),
        (' true', true),
      ]) {
        test('`verification_coverage:$text` reads as $expected', () async {
          final root = await _withConfig(
            'packs:\n  prd-core: 1.0.0\nverification_coverage:$text\n',
          );

          expect(ProjectConfig.read(root).verificationCoverage, expected);
        });
      }

      for (final (name, line) in [
        ('a number', 'verification_coverage: 3'),
        ('a quoted word', "verification_coverage: 'yes'"),
        ('a list', 'verification_coverage: [true]'),
      ]) {
        test(
          'a non-boolean verification coverage ($name) is refused',
          () async {
            final root = await _withConfig(
              'packs:\n  prd-core: 1.0.0\n$line\n',
            );

            expect(
              () => ProjectConfig.read(root),
              throwsA(
                _fault(
                  FaultCode.unknownValue,
                  key: 'verification_coverage',
                ).having((f) => f.code.exitStatus, 'exitStatus', 78),
              ),
            );
          },
        );
      }
    });

    group('cleanup', () {
      Future<Directory> withCleanup(String lines) =>
          _withConfig('packs:\n  prd-core: 1.0.0\n$lines');

      for (final (name, lines) in [
        ('an absent map', ''),
        ('a bare key', 'cleanup:\n'),
        ('a null inner key', 'cleanup:\n  bundles_max_mb:\n'),
      ]) {
        test('$name reads the defaults', () async {
          final root = await withCleanup(lines);

          final cleanup = ProjectConfig.read(root).cleanup;

          expect(cleanup.bundlesMaxAge, CleanupBounds.defaults.bundlesMaxAge);
          expect(
            cleanup.bundlesMaxBytes,
            CleanupBounds.defaults.bundlesMaxBytes,
          );
          expect(cleanup.reportsMaxAge, CleanupBounds.defaults.reportsMaxAge);
        });
      }

      test('the defaults are 24 hours, 256 MB, and 7 days', () {
        expect(CleanupBounds.defaults.bundlesMaxAge, const Duration(hours: 24));
        expect(CleanupBounds.defaults.bundlesMaxBytes, 256 * 1000 * 1000);
        expect(CleanupBounds.defaults.reportsMaxAge, const Duration(days: 7));
      });

      test('three set values read back as given', () async {
        final root = await withCleanup(
          'cleanup: {bundles_max_age_hours: 48, bundles_max_mb: 512, '
          'reports_max_age_days: 30}\n',
        );

        final cleanup = ProjectConfig.read(root).cleanup;

        expect(cleanup.bundlesMaxAge, const Duration(hours: 48));
        expect(cleanup.bundlesMaxBytes, 512 * 1000 * 1000);
        expect(cleanup.reportsMaxAge, const Duration(days: 30));
      });

      test(
        'a count past the microsecond range clamps and stays positive',
        () async {
          final root = await withCleanup(
            'cleanup: {bundles_max_age_hours: 9000000000000, '
            'bundles_max_mb: 9000000000000000, '
            'reports_max_age_days: 9000000000000}\n',
          );

          final cleanup = ProjectConfig.read(root).cleanup;

          expect(cleanup.bundlesMaxAge, greaterThan(const Duration(days: 365)));
          expect(cleanup.bundlesMaxBytes, greaterThan(256 * 1000 * 1000));
          expect(cleanup.reportsMaxAge, greaterThan(const Duration(days: 365)));
        },
      );

      for (final (name, line) in [
        ('a scalar', 'cleanup: 7'),
        ('a list', 'cleanup: [7]'),
      ]) {
        test('$name is unknown_value for cleanup', () async {
          final root = await withCleanup('$line\n');

          expect(
            () => ProjectConfig.read(root),
            throwsA(
              _fault(
                FaultCode.unknownValue,
                key: 'cleanup',
              ).having((f) => f.code.exitStatus, 'exitStatus', 78),
            ),
          );
        });
      }

      test('an extra inner key is unknown_key at cleanup.<key>', () async {
        final root = await withCleanup('cleanup:\n  tmp_days: 3\n');

        expect(
          () => ProjectConfig.read(root),
          throwsA(_fault(FaultCode.unknownKey, key: 'cleanup.tmp_days')),
        );
      });

      for (final key in [
        'bundles_max_age_hours',
        'bundles_max_mb',
        'reports_max_age_days',
      ]) {
        for (final value in ['0', '-1', "'7'", '1.5', '[7]', 'true']) {
          test('$key: $value is unknown_value at cleanup.$key', () async {
            final root = await withCleanup('cleanup:\n  $key: $value\n');

            expect(
              () => ProjectConfig.read(root),
              throwsA(
                _fault(
                  FaultCode.unknownValue,
                  key: 'cleanup.$key',
                ).having((f) => f.code.exitStatus, 'exitStatus', 78),
              ),
            );
          });
        }
      }
    });

    group('targets', () {
      test('two '
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

      test('targets beside code_root is unknown_value at code_root', () async {
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
      });

      test(
        'targets beside code_root names the target-owned code_root',
        () async {
          final root = await _withConfig(
            'packs:\n  prd-core: 1.0.0\ncode_root: lib\n'
            'targets:\n  flutter:\n    code_root: stratum_ui\n',
          );

          expect(
            () => ProjectConfig.read(root),
            throwsA(
              _fault(FaultCode.unknownValue, key: 'code_root').having(
                (f) => f.message,
                'message',
                contains('each target holds its own code_root'),
              ),
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
        test('targets as $name is unknown_value at targets', () async {
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
        test('$name as a target name is unknown_key', () async {
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

      for (final name in ['refs', 'REFS', 'Refs']) {
        test('$name is refused at the targets key', () async {
          final root = await _withConfig(
            'packs:\n  prd-core: 1.0.0\ntargets:\n  $name:\n    code_root: a\n',
          );

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

      test(
        'a name differing from another only in letter case is '
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
          'a null target value',
          FaultCode.unknownValue,
          'targets.flutter',
          '  flutter:\n',
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
        (
          'a drive-letter code_root',
          FaultCode.unknownValue,
          'targets.flutter.code_root',
          '  flutter:\n    code_root: C:/code\n',
        ),
        (
          'a code_root with a trailing dot',
          FaultCode.unknownValue,
          'targets.flutter.code_root',
          "  flutter:\n    code_root: 'src.'\n",
        ),
        (
          'a code_root with a trailing space',
          FaultCode.unknownValue,
          'targets.flutter.code_root',
          "  flutter:\n    code_root: 'src '\n",
        ),
        (
          'a list code_root',
          FaultCode.unknownValue,
          'targets.flutter.code_root',
          '  flutter:\n    code_root: [a]\n',
        ),
      ]) {
        test('$name is refused at its own target key', () async {
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
        });
      }

      test('a target with no code_root key reads the project root', () async {
        final root = await _withConfig(
          'packs:\n  prd-core: 1.0.0\ntargets:\n  flutter: {}\n',
        );

        expect(ProjectConfig.read(root).targets, [
          const CodeTarget('flutter', codeRoot: '.'),
        ]);
      });

      test('two targets whose code roots name one folder are unknown_value '
          'naming both', () async {
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
      });

      test('two targets on one code folder name the config file', () async {
        final root = await _withConfig(
          'packs:\n  prd-core: 1.0.0\n'
          'targets:\n  flutter:\n    code_root: .\n'
          '  jaspr:\n    code_root: ./\n',
        );

        expect(
          () => ProjectConfig.read(root),
          throwsA(
            _fault(
              FaultCode.unknownValue,
              key: 'targets',
            ).having((f) => f.file, 'file', '.specstone/config.yaml'),
          ),
        );
      });

      test(
        'one entry gives one named target and codeRoot reads its root',
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

      test('no targets key '
          'gives one unnamed target at code_root', () async {
        final root = await _withConfig(
          'packs:\n  prd-core: 1.0.0\ncode_root: stratum_ui\n',
        );

        final config = ProjectConfig.read(root);

        expect(config.targets, [
          const CodeTarget(null, codeRoot: 'stratum_ui'),
        ]);
        expect(config.codeRoot, 'stratum_ui');
      });
    });

    test('a config without packs is missing_key', () async {
      final root = await _withConfig('# empty\n');

      expect(
        () => ProjectConfig.read(root),
        throwsA(_fault(FaultCode.missingKey, key: 'packs')),
      );
    });

    for (final (label, pin) in [
      ('an unquoted double', '1.2'),
      ('a quoted two-part version', "'1.2'"),
      ('a pre-release tag', '1.2.0-beta'),
    ]) {
      test('$label pin is pack_version_invalid', () async {
        final root = await _withConfig('packs:\n  prd-core: $pin\n');

        expect(
          () => ProjectConfig.read(root),
          throwsA(_fault(FaultCode.packVersionInvalid, key: 'packs.prd-core')),
        );
      });
    }

    for (final (label, pin) in [
      ('an unquoted double', '1.2'),
      ('a quoted two-part version', "'1.2'"),
      ('a pre-release tag', '1.2.0-beta'),
    ]) {
      test('$label pin exits 78', () async {
        final root = await _withConfig('packs:\n  prd-core: $pin\n');

        expect(
          () => ProjectConfig.read(root),
          throwsA(
            _fault(
              FaultCode.packVersionInvalid,
              key: 'packs.prd-core',
            ).having((f) => f.code.exitStatus, 'exitStatus', 78),
          ),
        );
      });
    }

    test('non-UTF-8 config bytes are yaml_syntax', () async {
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

    test('a CRLF config reads its pins', () async {
      final root = await _withConfig(
        'packs:\r\n  prd-core: 1.0.0\r\n  software-tech: 2.1.0\r\n',
      );

      final config = ProjectConfig.read(root);

      expect(config.pins.keys, ['prd-core', 'software-tech']);
    });
  });

  group('readAgentFilesVersion', () {
    Future<AgentFilesStamp> stampOf(String text) async =>
        readAgentFilesVersion(await _withConfig(text));

    test('a Version reads as that Version', () async {
      final stamp = await stampOf(
        'packs:\n  prd-core: 1.0.0\nagent_files_version: 1.3.0\n',
      );

      expect(stamp, isA<AgentFilesStampVersion>());
      expect((stamp as AgentFilesStampVersion).version.toString(), '1.3.0');
    });

    test('no key reads as no stamp', () async {
      final stamp = await stampOf('packs:\n  prd-core: 1.0.0\n');

      expect(stamp, isA<AgentFilesStampAbsent>());
    });

    test('a null value reads as no stamp', () async {
      final stamp = await stampOf(
        'packs:\n  prd-core: 1.0.0\nagent_files_version:\n',
      );

      expect(stamp, isA<AgentFilesStampAbsent>());
    });

    test('reads the Version beside a broken agent_file_roots', () async {
      final stamp = await stampOf(
        'packs:\n  prd-core: 1.0.0\nagent_file_roots: 3\n'
        'agent_files_version: 1.3.0\n',
      );

      expect(stamp, isA<AgentFilesStampVersion>());
    });

    test(
      'reads the Version with no packs key and with an unknown key',
      () async {
        final stamp = await stampOf('bogus: 1\nagent_files_version: 2.0.0\n');

        expect(stamp, isA<AgentFilesStampVersion>());
      },
    );

    for (final (name, text) in [
      ('a two-field value', 'agent_files_version: 1.3\n'),
      ('a whole number', 'agent_files_version: 3\n'),
      ('a list', 'agent_files_version: [1.3.0]\n'),
      ('a YAML syntax error', 'agent_files_version: [1.3.0\n'),
      (
        'a duplicate key',
        'agent_files_version: 1.3.0\nagent_files_version: 1.4.0\n',
      ),
      ('a document that is no map', '- agent_files_version\n'),
    ]) {
      test('$name is unreadable and never throws', () async {
        final stamp = await stampOf(text);

        expect(stamp, isA<AgentFilesStampUnreadable>());
      });
    }

    test('a file that is not UTF-8 is unreadable', () async {
      final root = await writeTree({_configPath: ''});
      File.fromUri(root.uri.resolve(_configPath))
          .writeAsBytesSync([0xff, 0xfe, 0x41]);

      expect(readAgentFilesVersion(root), isA<AgentFilesStampUnreadable>());
    });

    test('a missing config file is unreadable', () async {
      final root = await writeTree({'other.txt': 'x'});

      expect(readAgentFilesVersion(root), isA<AgentFilesStampUnreadable>());
    });

    test('a .specstone that is a link is unreadable', () async {
      final other = await writeTree({
        '.specstone/config.yaml':
            'packs:\n  prd-core: 1.0.0\nagent_files_version: 1.3.0\n',
      });
      final root = await writeTree({'other.txt': 'x'});
      Link('${root.path}${Platform.pathSeparator}.specstone')
          .createSync('${other.path}${Platform.pathSeparator}.specstone');

      expect(readAgentFilesVersion(root), isA<AgentFilesStampUnreadable>());
    }, skip: _linksUnavailable);

    test('a config path that is a folder is unreadable', () async {
      final root = await writeTree({'$_configPath/inner': 'x'});

      expect(readAgentFilesVersion(root), isA<AgentFilesStampUnreadable>());
    });
  });

  group('readCleanupBounds', () {
    test('a bad key reads its default and a good key its value', () async {
      final root = await _withConfig(
        'packs:\n  prd-core: 1.0.0\n'
        'cleanup:\n  bundles_max_age_hours: 0\n  bundles_max_mb: 512\n',
      );

      final cleanup = readCleanupBounds(root);

      expect(cleanup.bundlesMaxAge, CleanupBounds.defaults.bundlesMaxAge);
      expect(cleanup.bundlesMaxBytes, 512 * 1000 * 1000);
      expect(cleanup.reportsMaxAge, CleanupBounds.defaults.reportsMaxAge);
    });

    test('reads a value beside a broken pack and an unknown key', () async {
      final root = await _withConfig(
        'bogus: 1\nagent_file_roots: 3\n'
        'cleanup:\n  tmp_days: 3\n  reports_max_age_days: 30\n',
      );

      expect(readCleanupBounds(root).reportsMaxAge, const Duration(days: 30));
    });

    for (final (name, text) in [
      ('a scalar cleanup', 'cleanup: 7\n'),
      ('a YAML syntax error', 'cleanup: [1\n'),
      ('a document that is no map', '- cleanup\n'),
      ('a duplicate key', 'cleanup: {bundles_max_mb: 1}\ncleanup: {}\n'),
    ]) {
      test('$name reads the defaults and never throws', () async {
        final root = await _withConfig(text);

        final cleanup = readCleanupBounds(root);

        expect(cleanup.bundlesMaxAge, CleanupBounds.defaults.bundlesMaxAge);
        expect(cleanup.bundlesMaxBytes, CleanupBounds.defaults.bundlesMaxBytes);
        expect(cleanup.reportsMaxAge, CleanupBounds.defaults.reportsMaxAge);
      });
    }

    test('a file that is not UTF-8 reads the defaults', () async {
      final root = await writeTree({_configPath: ''});
      File.fromUri(root.uri.resolve(_configPath))
          .writeAsBytesSync([0xff, 0xfe, 0x41]);

      expect(
        readCleanupBounds(root).bundlesMaxBytes,
        CleanupBounds.defaults.bundlesMaxBytes,
      );
    });

    test('a missing config file reads the defaults', () async {
      final root = await writeTree({'other.txt': 'x'});

      expect(
        readCleanupBounds(root).bundlesMaxAge,
        CleanupBounds.defaults.bundlesMaxAge,
      );
    });
  });

  group('findProjectRoot', () {
    test('finds the config in an ancestor folder', () async {
      final root = await writeTree({_configPath: 'packs: {}\n'});
      final start = Directory.fromUri(root.uri.resolve('docs/prds/'));
      await start.create(recursive: true);

      expect(_canonical(findProjectRoot(start)!), _canonical(root));
    });

    test(
      'no config in any ancestor gives null',
      () async {
        final root = await writeTree({});

        expect(findProjectRoot(root), isNull);
      },
      skip: _tempHasConfigAncestor()
          ? 'an ancestor of the system temp folder holds $_configPath'
          : false,
    );

    test('the nearest config wins', () async {
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

    test('a .specstone folder without config.yaml is skipped', () async {
      final root = await writeTree({
        _configPath: 'packs: {}\n',
        'a/.specstone/notes.txt': 'x',
      });
      final start = Directory.fromUri(root.uri.resolve('a/'));

      expect(_canonical(findProjectRoot(start)!), _canonical(root));
    });
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

    test('a docs link to a folder with no config, in a folder with none, '
        'walks on to the parent', () async {
      final tree = await writeTree({
        'ws/$_configPath': 'packs: {}\n',
        'ws/code/lib/keep.txt': '',
        'plain/docs/keep.txt': '',
      });
      if (!link(tree, '', '../../plain/docs')) return;

      final found = findProjectRoot(at(tree, 'ws/code'));

      expect(_canonical(found!), _canonical(at(tree, 'ws')));
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
