import 'dart:io';

import 'package:test/test.dart';

/// Runs `git` with [args] in [dir] as a fixed test author.
ProcessResult git(Directory dir, List<String> args) => Process.runSync('git', [
  '-c',
  'user.name=t',
  '-c',
  'user.email=t@t',
  ...args,
], workingDirectory: dir.path);

/// Whether a `git` program runs on this machine.
final bool hasGit = () {
  try {
    return Process.runSync('git', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}();

/// Commits every change under [root] with [message].
void commitAll(Directory root, String message) {
  expect(git(root, ['add', '-A']).exitCode, 0);
  expect(git(root, ['commit', '-q', '-m', message]).exitCode, 0);
}
