import 'dart:io';

import 'package:test/test.dart';

import 'git_repo.dart';
import 'temp_tree.dart';

void main() {
  test('cleanGitEnvironment drops git location variables only', () {
    final cleaned = cleanGitEnvironment({
      'GIT_DIR': '/x/.git',
      'Git_Dir': '/y/.git',
      'GIT_WORK_TREE': '/x',
      'GIT_INDEX_FILE': '/x/.git/index',
      'PATH': '/bin',
      'HOME': '/home/t',
    });

    expect(cleaned, {'PATH': '/bin', 'HOME': '/home/t'});
  });

  test('a fixture git never starts background maintenance', () async {
    final root = await writeTree({'a.txt': 'a\n'});
    expect(git(root, ['init', '-q']).exitCode, 0);

    // `git commit` detaches `git maintenance run --auto`, which holds
    // .git/objects/maintenance.lock for a moment after the commit returns.
    expect(
      git(root, ['config', '--get', 'maintenance.auto']).stdout,
      'false\n',
    );
    expect(git(root, ['config', '--get', 'gc.auto']).stdout, '0\n');
  }, skip: hasGit ? false : 'git missing');

  test('a fixture never writes the repository a GIT_DIR points at', () async {
    final outer = await writeTree({});
    expect(git(outer, ['init', '-q']).exitCode, 0);
    final config = File('${outer.path}/.git/config');
    final head = File('${outer.path}/.git/HEAD');
    final configBefore = config.readAsBytesSync();
    final headBefore = head.readAsBytesSync();
    final fixture = await writeTree({'a.txt': 'a\n'});
    final environment = cleanGitEnvironment({
      ...Platform.environment,
      'GIT_DIR': '${outer.path}/.git',
    });

    // The same sequence commitRepo runs, under the exported GIT_DIR.
    for (final args in [
      ['init', '-q'],
      ['config', 'user.name', 't'],
      ['config', 'user.email', 't@t'],
      ['add', '-A'],
      ['commit', '-q', '-m', 'legacy'],
    ]) {
      final result = Process.runSync(
        'git',
        args,
        workingDirectory: fixture.path,
        environment: environment,
        includeParentEnvironment: false,
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }

    expect(config.readAsBytesSync(), configBefore);
    expect(head.readAsBytesSync(), headBefore);
    expect(Directory('${fixture.path}/.git').existsSync(), isTrue);
  }, skip: hasGit ? false : 'git missing');
}
