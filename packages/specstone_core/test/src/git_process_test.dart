import 'dart:io';

import 'package:specstone_core/src/git_process.dart';
import 'package:test/test.dart';

import '../helpers/git_repo.dart';

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
}
