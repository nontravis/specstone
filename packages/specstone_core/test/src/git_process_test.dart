import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/git_process.dart';
import 'package:test/test.dart';

import '../helpers/git_repo.dart';
import '../helpers/package_root.dart';
import '../helpers/temp_tree.dart';

const _listed = [
  'GIT_DIR',
  'GIT_WORK_TREE',
  'GIT_INDEX_FILE',
  'GIT_COMMON_DIR',
  'GIT_CONFIG_PARAMETERS',
  'GIT_CONFIG_COUNT',
];

void main() {
  group('f06/us01/fr02/e15: gitChildEnvironment', () {
    test('drops each listed variable but the two config ones', () {
      final child = gitChildEnvironment(
        inherited: {
          'GIT_DIR': '/b/.git',
          'GIT_WORK_TREE': '/b',
          'GIT_INDEX_FILE': '/b/.git/index',
          'GIT_COMMON_DIR': '/b/.git',
          'GIT_CONFIG_PARAMETERS': "'safe.directory=*'",
          'GIT_CONFIG_COUNT': '1',
          'GIT_CONFIG_KEY_0': 'safe.directory',
          'GIT_CONFIG_VALUE_0': '*',
          'GIT_SSH': 'ssh',
          'GIT_CONFIG_GLOBAL': '/g',
          'GIT_CEILING_DIRECTORIES': '/c',
          'PATH': '/bin',
        },
        localVariables: _listed,
        ignoresCase: false,
      );

      expect(child, {
        'GIT_CONFIG_PARAMETERS': "'safe.directory=*'",
        'GIT_CONFIG_COUNT': '1',
        'GIT_CONFIG_KEY_0': 'safe.directory',
        'GIT_CONFIG_VALUE_0': '*',
        'GIT_SSH': 'ssh',
        'GIT_CONFIG_GLOBAL': '/g',
        'GIT_CEILING_DIRECTORIES': '/c',
        'PATH': '/bin',
      });
    });

    test("the caller's own variables win over a removed inherited one", () {
      final child = gitChildEnvironment(
        inherited: {'GIT_INDEX_FILE': '/b/.git/index', 'PATH': '/bin'},
        localVariables: _listed,
        own: {'GIT_INDEX_FILE': '/tmp/i', 'GIT_LITERAL_PATHSPECS': '1'},
        ignoresCase: false,
      );

      expect(child, {
        'GIT_INDEX_FILE': '/tmp/i',
        'GIT_LITERAL_PATHSPECS': '1',
        'PATH': '/bin',
      });
    });

    test('a name differing in case is removed where names ignore case', () {
      final child = gitChildEnvironment(
        inherited: {'Git_Dir': '/b/.git', 'PATH': '/bin'},
        localVariables: _listed,
        ignoresCase: true,
      );

      expect(child, {'PATH': '/bin'});
    });

    test('a name differing in case stays where names keep their case', () {
      final child = gitChildEnvironment(
        inherited: {'Git_Dir': '/b/.git', 'PATH': '/bin'},
        localVariables: _listed,
        ignoresCase: false,
      );

      expect(child, {'Git_Dir': '/b/.git', 'PATH': '/bin'});
    });

    test('the two config variables stay when names ignore case', () {
      final child = gitChildEnvironment(
        inherited: {'Git_Config_Count': '1', 'Git_Config_Parameters': 'x'},
        localVariables: _listed,
        ignoresCase: true,
      );

      expect(child, {'Git_Config_Count': '1', 'Git_Config_Parameters': 'x'});
    });

    test('an own variable replaces an inherited one differing in case where '
        'names ignore case', () {
      final child = gitChildEnvironment(
        inherited: {'git_literal_pathspecs': '0', 'PATH': '/bin'},
        localVariables: _listed,
        own: {'GIT_LITERAL_PATHSPECS': '1'},
        ignoresCase: true,
      );

      expect(child, {'GIT_LITERAL_PATHSPECS': '1', 'PATH': '/bin'});
    });
  });

  group('f06/us01/fr02/e15: localEnvVarsFrom', () {
    test('reads one name per line, with no CR and no empty name', () {
      final names = localEnvVarsFrom(
        ProcessResult(0, 0, 'GIT_DIR\r\nGIT_WORK_TREE\n\n', ''),
      );

      expect(names, ['GIT_DIR', 'GIT_WORK_TREE']);
    });

    test('a non-zero exit throws ProcessException', () {
      expect(
        () => localEnvVarsFrom(ProcessResult(0, 128, '', 'fatal: x')),
        throwsA(isA<ProcessException>()),
      );
    });

    test('a lone CR separates two names', () {
      final names = localEnvVarsFrom(
        ProcessResult(0, 0, 'GIT_DIR\rGIT_WORK_TREE', ''),
      );

      expect(names, ['GIT_DIR', 'GIT_WORK_TREE']);
    });

    test('an exit 0 that lists no name throws ProcessException', () {
      for (final printed in ['', '\n\r\n  \n']) {
        expect(
          () => localEnvVarsFrom(ProcessResult(0, 0, printed, '')),
          throwsA(isA<ProcessException>()),
          reason: 'printed ${jsonEncode(printed)}',
        );
      }
    });

    test(
      'git lists GIT_DIR and GIT_CONFIG_COUNT and no GIT_CONFIG_KEY_ name',
      () {
        final result = Process.runSync(
          'git',
          [
            '-c',
            'safe.bareRepository=explicit',
            'rev-parse',
            '--local-env-vars',
          ],
          environment: cleanGitEnvironment(),
          includeParentEnvironment: false,
        );

        final names = localEnvVarsFrom(result);

        expect(names, containsAll(['GIT_DIR', 'GIT_CONFIG_COUNT']));
        expect(names.where((n) => n.startsWith('GIT_CONFIG_KEY_')), isEmpty);
      },
      skip: hasGit ? null : 'git is not available',
    );
  });

  group('f06/us01/fr02/e15: through the real git launch', () {
    Future<List<Map<String, Object?>>> runIn(
      List<Directory> folders,
      List<String> gitArguments, {
      Map<String, String> inherited = const {},
    }) async {
      final probe = packageRoot().uri
          .resolve('test/helpers/run_real_git.dart')
          .toFilePath();
      final shown = await Process.run(
        Platform.resolvedExecutable,
        [probe, ...folders.map((f) => f.path), '--', ...gitArguments],
        environment: cleanGitEnvironment({
          ...Platform.environment,
          ...inherited,
        }),
        includeParentEnvironment: false,
      );
      expect(shown.exitCode, 0, reason: '${shown.stdout}\n${shown.stderr}');
      return (jsonDecode('${shown.stdout}') as List<Object?>)
          .cast<Map<String, Object?>>()
          .toList();
    }

    Future<Directory> repo() async {
      final root = await writeTree({});
      expect(git(root, ['init', '-q']).exitCode, 0);
      return root;
    }

    test(
      'a folder that does not exist does not make a later folder fail',
      () async {
        final root = await repo();
        final missing = Directory('${root.path}/missing');

        final outcomes = await runIn(
          [missing, root],
          ['rev-parse', '--show-toplevel'],
        );

        expect(outcomes.first, contains('threw'));
        expect(outcomes.last, {
          'exit': 0,
          'stdout': git(root, ['rev-parse', '--show-toplevel']).stdout,
        });
      },
      skip: hasGit ? null : 'git is not available',
    );

    test('a PATH with no absolute entry is a git that cannot start', () async {
      final root = await repo();

      final outcomes = await runIn(
        [root],
        ['--version'],
        inherited: {'PATH': ':.:bin'},
      );

      expect(outcomes.single['threw'], contains('ProcessException'));
    }, skip: hasGit ? null : 'git is not available');

    test('an inherited GIT_CONFIG_COUNT pair still reaches git', () async {
      final root = await repo();

      final outcomes = await runIn(
        [root],
        ['config', '--get', 'foo.bar'],
        inherited: {
          'GIT_CONFIG_COUNT': '1',
          'GIT_CONFIG_KEY_0': 'foo.bar',
          'GIT_CONFIG_VALUE_0': 'baz',
        },
      );

      expect(outcomes, [
        {'exit': 0, 'stdout': 'baz\n'},
      ]);
    }, skip: hasGit ? null : 'git is not available');

    for (final (form, inherited) in [
      (
        'GIT_CONFIG_COUNT',
        {
          'GIT_CONFIG_COUNT': '1',
          'GIT_CONFIG_KEY_0': 'safe.bareRepository',
          'GIT_CONFIG_VALUE_0': 'all',
        },
      ),
      (
        'GIT_CONFIG_PARAMETERS',
        {'GIT_CONFIG_PARAMETERS': "'safe.bareRepository=all'"},
      ),
    ]) {
      test('an inherited safe.bareRepository=all in $form loses to '
          "Specstone's explicit setting", () async {
        final bare = await writeTree({});
        expect(git(bare, ['init', '-q', '--bare']).exitCode, 0);

        final outcomes = await runIn(
          [bare],
          ['rev-parse', '--git-dir'],
          inherited: inherited,
        );

        expect(outcomes, hasLength(1));
        expect(outcomes.single['exit'], 128, reason: '${outcomes.single}');
      }, skip: hasGit ? null : 'git is not available');
    }
  });
}
