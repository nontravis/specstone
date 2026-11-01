import 'dart:io';

import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/git_process.dart';

/// Returns the hash a dry run prints on its `plan <hash>` line.
///
/// It is the [baseHashOf] of [planText], followed by `head <sha>` when
/// [folder] lies in a git work tree with a commit, so a commit made between
/// the dry run and `--yes` changes it. Outside a git work tree, or when `git`
/// cannot start, it covers [planText] alone.
String planHashOf(String planText, Directory folder, RunGit runGit) {
  final head = _headOf(folder, runGit);
  return baseHashOf(head == null ? planText : '${planText}head $head\n');
}

/// Returns the HEAD commit of the work tree holding [folder], or null.
String? _headOf(Directory folder, RunGit runGit) {
  final ProcessResult result;
  try {
    result = runGit([
      'rev-parse',
      '--verify',
      '--quiet',
      'HEAD',
    ], workingDirectory: folder.path);
  } on ProcessException {
    return null;
  }
  if (result.exitCode != 0) return null;
  final sha = (result.stdout as String).trim();
  return sha.isEmpty ? null : sha;
}
