import 'dart:io';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:yaml/yaml.dart';

/// Whether a doc was ever approved.
enum Approval {
  /// A draft whose `approved` key does not hold YAML `true`.
  neverApproved,

  /// Not a draft, or a draft whose `approved` key holds YAML `true`.
  approved,
}

/// Returns the [Approval] the frontmatter of [doc] states.
Approval approvalOf(Doc doc) =>
    doc.isDraft && !holdsApproved(doc) ? .neverApproved : .approved;

/// Whether the frontmatter `approved` key of [doc] holds YAML `true`.
bool holdsApproved(Doc doc) {
  final block = doc.frontmatter?.where((b) => b.name == 'approved').firstOrNull;
  if (block == null) return false;
  try {
    return loadYaml(block.valueText) == true;
  } on YamlException {
    return false;
  }
}

/// What the git history says about the last approved copy of a doc.
sealed class ApprovalLookup {
  const new();
}

/// The newest committed copy that is not a draft.
final class ApprovedCopy extends ApprovalLookup {
  const new(this.text, {required this.commit, required this.path});

  /// The text of the copy as committed.
  final String text;

  /// The full hash of the commit that holds the copy.
  final String commit;

  /// The project path of the doc at [commit], its old path after a rename.
  final String path;
}

/// A history in which no committed copy is free of `draft`.
final class NoApprovedCopy extends ApprovalLookup {
  const new();
}

/// A history git could not report: no repository, or git missing.
final class UnknownHistory extends ApprovalLookup {
  const new();
}

/// Finds the last approved copy of a doc in git.
final class ApprovalHistory {
  /// [runGit] replaces the real `git` process, for tests.
  const new({RunGit? runGit}) : _runGit = runGit ?? runRealGit;

  final RunGit _runGit;

  /// Returns the newest committed copy of [projectPath] without `draft`.
  ///
  /// [projectPath] is relative to [projectRoot], the repository root; the
  /// history follows renames and skips the commits that deleted the file.
  ApprovalLookup lastApproved(Directory projectRoot, String projectPath) {
    try {
      final log = _runGit([
        'log',
        '--follow',
        '--diff-filter=d',
        '-z',
        '--format=%H',
        '--name-only',
        '--',
        projectPath,
      ], workingDirectory: projectRoot.path);
      if (log.exitCode != 0) return const UnknownHistory();
      for (final (sha, path) in _commitsOf(log.stdout as String)) {
        final show = _runGit([
          'show',
          '$sha:$path',
        ], workingDirectory: projectRoot.path);
        if (show.exitCode != 0) return const UnknownHistory();
        final copy = show.stdout as String;
        if (!Doc.parse(toLf(copy)).isDraft) {
          return ApprovedCopy(copy, commit: sha, path: path);
        }
      }
      return const NoApprovedCopy();
    } on ProcessException {
      return const UnknownHistory();
    } on FormatException {
      // git printed bytes that are not UTF-8, so its history cannot be read.
      return const UnknownHistory();
    }
  }
}

final _sha = RegExp(r'^(?:[0-9a-f]{40}|[0-9a-f]{64})$');

/// Pairs each commit of a `-z --format=%H --name-only` log with its listed
/// path.
///
/// A hash is 40 or 64 hex, git's SHA-1 or SHA-256 object format (FM1). `-z`
/// ends each field with NUL and leaves a path unquoted whatever its bytes; git
/// puts a newline between a commit's hash and its path.
Iterable<(String, String)> _commitsOf(String log) sync* {
  String? sha;
  for (final field in log.split('\x00')) {
    if (_sha.hasMatch(field)) {
      sha = field;
    } else if (field.isNotEmpty && sha != null) {
      yield (sha, field.startsWith('\n') ? field.substring(1) : field);
      sha = null;
    }
  }
}
