import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/doc_model/doc.dart';
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
  const new(this.text);

  /// The text of the copy as committed.
  final String text;
}

/// A history in which no committed copy is free of `draft`.
final class NoApprovedCopy extends ApprovalLookup {
  const new();
}

/// A history git could not report: no repository, or git missing.
final class UnknownHistory extends ApprovalLookup {
  const new();
}

/// Runs `git` with [arguments] in [workingDirectory].
typedef RunGit = ProcessResult Function(
  List<String> arguments, {
  required String workingDirectory,
});

ProcessResult _runRealGit(
  List<String> arguments, {
  required String workingDirectory,
}) => Process.runSync(
  'git',
  arguments,
  workingDirectory: workingDirectory,
  stdoutEncoding: utf8,
);

/// Finds the last approved copy of a doc in git; the only code that starts git.
final class ApprovalHistory {
  /// [runGit] replaces the real `git` process, for tests.
  const new({RunGit? runGit}) : _runGit = runGit ?? _runRealGit;

  final RunGit _runGit;

  /// Returns the newest committed copy of [projectPath] without `draft`.
  ///
  /// [projectPath] is relative to [projectRoot], the repository root; the
  /// history follows renames.
  ApprovalLookup lastApproved(Directory projectRoot, String projectPath) {
    try {
      final log = _runGit([
        'log',
        '--follow',
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
        if (!Doc.parse(toLf(copy)).isDraft) return ApprovedCopy(copy);
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

final _sha = RegExp(r'^[0-9a-f]{40}$');

/// Pairs each commit of a `--format=%H --name-only` log with its listed path.
Iterable<(String, String)> _commitsOf(String log) sync* {
  String? sha;
  for (final line in const LineSplitter().convert(log)) {
    if (_sha.hasMatch(line)) {
      sha = line;
    } else if (line.isNotEmpty && sha != null) {
      yield (sha, line);
      sha = null;
    }
  }
}

/// Returns the zero-context line diff of [oldText] and [newText].
///
/// Both texts are read as LF. Each hunk is `@@ -<a>[,<n>] +<b>[,<m>] @@`,
/// then its `-` lines, then its `+` lines; a count of 1 is left out and a zero
/// count names the line before the change. Equal texts give `''`.
String changedHunks(String oldText, String newText) {
  final before = _linesOf(oldText);
  final after = _linesOf(newText);
  final common = _lcsTable(before, after);
  final out = StringBuffer();
  var i = 0;
  var j = 0;
  while (i < before.length || j < after.length) {
    if (i < before.length && j < after.length && before[i] == after[j]) {
      i++;
      j++;
      continue;
    }
    final startI = i;
    final startJ = j;
    while ((i < before.length || j < after.length) &&
        !(i < before.length && j < after.length && before[i] == after[j])) {
      if (j >= after.length ||
          (i < before.length && common[i + 1][j] >= common[i][j + 1])) {
        i++;
      } else {
        j++;
      }
    }
    out
      ..write('@@ -${_range(startI, i - startI)} ')
      ..write('+${_range(startJ, j - startJ)} @@\n');
    for (final line in before.sublist(startI, i)) {
      out.write('-$line\n');
    }
    for (final line in after.sublist(startJ, j)) {
      out.write('+$line\n');
    }
  }
  return out.toString();
}

List<String> _linesOf(String text) {
  final lf = toLf(text);
  if (lf.isEmpty) return const [];
  final lines = lf.split('\n');
  if (lines.last.isEmpty) lines.removeLast();
  return lines;
}

/// `table[i][j]` is the LCS length of `a[i..]` and `b[j..]`.
List<List<int>> _lcsTable(List<String> a, List<String> b) {
  final table = [
    for (var i = 0; i <= a.length; i++) List.filled(b.length + 1, 0),
  ];
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      table[i][j] = a[i] == b[j]
          ? table[i + 1][j + 1] + 1
          : (table[i + 1][j] >= table[i][j + 1]
                ? table[i + 1][j]
                : table[i][j + 1]);
    }
  }
  return table;
}

/// The hunk range for [count] lines after zero-based index [start].
String _range(int start, int count) {
  if (count == 0) return '$start,0';
  return count == 1 ? '${start + 1}' : '${start + 1},$count';
}
