import 'dart:io';

import 'package:test/test.dart';

/// Git variables that point `git` at a repository other than the fixture.
const _gitLocationKeys = {
  'GIT_DIR',
  'GIT_WORK_TREE',
  'GIT_INDEX_FILE',
  'GIT_COMMON_DIR',
  'GIT_OBJECT_DIRECTORY',
  'GIT_ALTERNATE_OBJECT_DIRECTORIES',
  'GIT_CEILING_DIRECTORIES',
};

/// The process environment without git's location variables.
///
/// A `git bisect run` or a git hook exports them; a fixture that inherited
/// them would write the enclosing repository instead of its own.
Map<String, String> cleanGitEnvironment() => {
  for (final MapEntry(:key, :value) in Platform.environment.entries)
    if (!_gitLocationKeys.contains(key.toUpperCase())) key: value,
};

/// Runs `git` with [args] in [dir] as a fixed test author.
ProcessResult git(Directory dir, List<String> args) => Process.runSync(
  'git',
  ['-c', 'user.name=t', '-c', 'user.email=t@t', ...args],
  workingDirectory: dir.path,
  environment: cleanGitEnvironment(),
  includeParentEnvironment: false,
);

/// Whether a `git` program runs on this machine.
final bool hasGit = () {
  try {
    return Process.runSync(
          'git',
          ['--version'],
          environment: cleanGitEnvironment(),
          includeParentEnvironment: false,
        ).exitCode ==
        0;
  } on ProcessException {
    return false;
  }
}();

/// Commits every change under [root] with [message].
void commitAll(Directory root, String message) {
  expect(git(root, ['add', '-A']).exitCode, 0);
  expect(git(root, ['commit', '-q', '-m', message]).exitCode, 0);
}
