@TestOn('windows')
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../../specstone_core/test/helpers/git_repo.dart'
    show cleanGitEnvironment, git;
import '../helpers/install_local_repo.dart';
import '../helpers/script_sandbox.dart';

const _fr =
    'install_update/machine_install/install_local_build/'
    'build_and_place_branch';

void main() {
  late String tool;

  setUpAll(() async => tool = await compileInstallLocal());

  test(
    '$_fr E02: Windows exits non-zero; snapshot() and the worktree list stay',
    () async {
      final sandbox = await createScriptSandbox();
      final separator = Platform.pathSeparator;
      File(
          '${sandbox.home.path}$separator.specstone${separator}bin'
          '${separator}specstone.exe',
        )
        ..createSync(recursive: true)
        ..writeAsStringSync('old');
      final fixture = await Directory.systemTemp.createTemp(
        'specstone_install_local_windows_',
      );
      addTearDown(() => fixture.delete(recursive: true));
      expect(git(fixture, ['init', '-q']).exitCode, 0);
      final before = sandbox.snapshot();

      final result = await Process.run(
        tool,
        const [],
        workingDirectory: fixture.path,
        environment: {
          ...cleanGitEnvironment(),
          'HOME': sandbox.home.path,
          'USERPROFILE': sandbox.home.path,
        },
        includeParentEnvironment: false,
      );

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('installs on macOS and Linux only'));
      expect(sandbox.snapshot(), before);
      final listed = git(fixture, ['worktree', 'list', '--porcelain']);
      expect(
        (listed.stdout as String)
            .split('\n')
            .where((line) => line.startsWith('worktree ')),
        hasLength(1),
      );
    },
  );
}
