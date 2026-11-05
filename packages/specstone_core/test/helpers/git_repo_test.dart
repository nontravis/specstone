import 'dart:io';

import 'package:test/test.dart';

import 'git_repo.dart';
import 'legacy_fixture.dart';
import 'temp_tree.dart';

const _probeDirKey = 'GIT_REPO_TEST_PROBE_DIR';

void main() {
  final isProbe = Platform.environment.containsKey(_probeDirKey);

  test(
    'probe: builds the fixture in the child process',
    () => commitRepo(Directory(Platform.environment[_probeDirKey]!)),
    skip: isProbe ? false : 'runs only as the child of the next test',
  );

  test(
    'a fixture never writes the repository a GIT_DIR points at',
    () async {
      final outer = await writeTree({});
      expect(git(outer, ['init', '-q']).exitCode, 0);
      final config = File('${outer.path}/.git/config');
      final head = File('${outer.path}/.git/HEAD');
      final configBefore = config.readAsBytesSync();
      final headBefore = head.readAsBytesSync();
      final fixture = await writeTree({'a.txt': 'a\n'});

      final child = await Process.run(
        Platform.resolvedExecutable,
        [
          'test',
          'test/helpers/git_repo_test.dart',
          '--plain-name',
          'probe: builds the fixture',
        ],
        environment: {
          'GIT_DIR': '${outer.path}/.git',
          _probeDirKey: fixture.path,
        },
      );

      expect(child.exitCode, 0, reason: '${child.stdout}${child.stderr}');
      expect(config.readAsBytesSync(), configBefore);
      expect(head.readAsBytesSync(), headBefore);
      expect(Directory('${fixture.path}/.git').existsSync(), isTrue);
    },
    skip: isProbe
        ? 'the child skips the parent'
        : (hasGit ? false : 'git missing'),
  );
}
