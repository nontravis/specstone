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

/// [source] (default: the process environment) without git's location
/// variables, matched case-insensitively.
///
/// A `git bisect run` or a git hook exports them; a fixture that inherited
/// them would write the enclosing repository instead of its own.
Map<String, String> cleanGitEnvironment([Map<String, String>? source]) => {
  for (final MapEntry(:key, :value) in (source ?? Platform.environment).entries)
    if (!_gitLocationKeys.contains(key.toUpperCase())) key: value,
};

/// Git settings that keep `git commit` from detaching auto-maintenance.
///
/// That background run holds `.git/objects/maintenance.lock` for a moment
/// after the commit returns, so a test that lists `.git` sees a file come
/// and go.
const _noBackgroundMaintenance = [
  '-c',
  'maintenance.auto=false',
  '-c',
  'gc.auto=0',
];

/// Runs `git` with [args] in [dir] as a fixed test author, with no background
/// maintenance.
ProcessResult git(Directory dir, List<String> args) => Process.runSync(
  'git',
  [
    '-c',
    'user.name=t',
    '-c',
    'user.email=t@t',
    ..._noBackgroundMaintenance,
    ...args,
  ],
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
