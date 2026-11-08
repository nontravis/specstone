import 'dart:io';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/rendering/formatter.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/setup_migration/agent_targets.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/pack_version.dart';

const _approvedKey = 'approved';
const _hashLength = 12;

/// Whether the approval stamps have run: any pin at or above its
/// [agentFilesSince] entry, `prd-core` 1.7.0 or `software-tech` 1.4.0 (R82).
bool stampsHaveRun(Map<String, PackVersion> pins) =>
    agentFilesSince.entries.any(
      (since) => switch (pins[since.key]) {
        final PackVersion pin => pin.compareTo(since.value) >= 0,
        null => false,
      },
    );

/// Returns the ApprovalHash of [lfText] laid out as [docType] lays it out,
/// less its `approved:`, `draft:`, and `output_ref` key blocks and the text of
/// its generated blocks.
///
/// A frontmatter left empty hashes as an absent one, so the doc hashes the
/// same before and after [withApprovalHash] adds a fence.
String approvalHashOf(String lfText, MergedDocType? docType) {
  var covered = _withoutGeneratedBlocks(
    lfText,
    docType?.listedGenerators.toSet() ?? const {},
  );
  for (final key in [
    _approvedKey,
    'draft',
    for (final field in docType?.fields ?? const <MergedField>[])
      if (field.type == FieldType.outputRef) field.id,
  ]) {
    covered = withKeyBlock(covered, key, null);
  }
  covered = layOutDoc(_withoutEmptyFrontmatter(covered), docType);
  return baseHashOf(covered).substring(0, _hashLength);
}

// Strips before the layout, so a block a `format` run inserts leaves no
// layout whitespace behind.
String _withoutGeneratedBlocks(String text, Set<String> kinds) {
  if (kinds.isEmpty) return text;
  final lines = text.split('\n');
  final generated = generatedBlockLines(lines, kinds);
  return [
    for (final (i, line) in lines.indexed)
      if (!generated[i]) line,
  ].join('\n');
}

// A doc with no frontmatter gains `---\n---\n` and a blank line from
// `withApprovalHash`; both leave the hash, with any leading blank lines.
String _withoutEmptyFrontmatter(String text) {
  final doc = Doc.parse(text);
  final blocks = doc.frontmatter;
  if (blocks != null && blocks.any((b) => b.text.trim().isNotEmpty)) {
    return text;
  }
  final body = blocks == null ? text : doc.afterFrontmatter;
  return body.replaceFirst(_leadingBlankLines, '');
}

final _leadingBlankLines = RegExp(r'^\n+');

/// Returns [lfText] with `approved: "<approvalHashOf>"` in place of any
/// `approved:` value, at its slot in the field order of [docType].
///
/// The one writer of the mark (R84).
String withApprovalHash(String lfText, MergedDocType? docType) => withKeyBlock(
  lfText,
  _approvedKey,
  'approved: "${approvalHashOf(lfText, docType)}"\n',
  fieldOrder: docType == null
      ? null
      : [for (final field in docType.fields) field.id],
);

/// Whether a doc was ever approved.
enum Approval {
  /// A draft with no `approved:` value.
  neverApproved,

  /// Neither `draft` nor `approved:`, once the stamps have run: a file made
  /// outside the commands.
  unmarked,

  /// Carries an `approved:` value, or neither key below the pins.
  approved,
}

/// The two frontmatter values the approval rules read.
///
/// The one place a frontmatter `approved:` value is read (R85).
final class ApprovalFields {
  const new({required this.isDraft, required this.approvedValue});

  /// Reads the fields from the frontmatter of [doc] as the index reads it.
  ///
  /// A frontmatter that is not valid YAML as a whole holds neither value.
  factory of(Doc doc) {
    final values = frontmatterValuesOf(doc);
    return ApprovalFields(
      isDraft: values['draft'] == true,
      approvedValue: values[_approvedKey],
    );
  }

  /// Reads the fields from the stored frontmatter of [doc].
  factory ofIndexed(IndexedDoc doc) => ApprovalFields(
    isDraft: doc.isDraft,
    approvedValue: doc.frontmatter[_approvedKey],
  );

  /// Whether `draft` holds YAML `true`.
  final bool isDraft;

  /// The YAML value of `approved:`; null when absent or empty.
  final Object? approvedValue;
}

/// Returns the [Approval] [fields] state.
Approval approvalOf(ApprovalFields fields, {required bool stampsHaveRun}) {
  if (fields.approvedValue != null) return .approved;
  if (fields.isDraft) return .neverApproved;
  return stampsHaveRun ? .unmarked : .approved;
}

/// Whether the doc of [fields] awaits the Owner's approval (INV-5), given
/// [hash], its current ApprovalHash.
bool awaitsApproval(
  ApprovalFields fields,
  String hash, {
  required bool stampsHaveRun,
}) {
  if (fields.isDraft) return true;
  return switch (fields.approvedValue) {
    null => stampsHaveRun,
    true => stampsHaveRun,
    final String value => value != hash,
    _ => true,
  };
}

/// Whether only the Owner may delete the doc of [fields]: any `approved:`
/// value, or no `draft: true` (INV-7).
bool isGuarded(ApprovalFields fields) =>
    fields.approvedValue != null || !fields.isDraft;

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
  ///
  /// An old path outside the project root stays relative to the repository
  /// top-level.
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

/// Whether a committed copy counts as approved (R85, R86): no `draft: true`,
/// and an `approved:` value that is the ApprovalHash of the copy's own
/// content, or `approved: true`.
bool countsAsApprovedCopy(String lfCopy, MergedDocType? docType) {
  final fields = ApprovalFields.of(Doc.parse(lfCopy));
  if (fields.isDraft) return false;
  return switch (fields.approvedValue) {
    true => true,
    final String value => value == approvalHashOf(lfCopy, docType),
    _ => false,
  };
}

/// Finds the last approved copy of a doc in git.
final class ApprovalHistory {
  /// [runGit] replaces the real `git` process, for tests.
  const new({RunGit? runGit}) : _runGit = runGit ?? runRealGit;

  final RunGit _runGit;

  /// Returns the newest committed copy of [projectPath] that counts as
  /// approved for [docType] (see [countsAsApprovedCopy]).
  ///
  /// [projectPath] is relative to [projectRoot], which may sit below the
  /// repository top-level; the history follows renames and skips the commits
  /// that deleted the file. A path no commit holds is looked up at the path
  /// the doc held before an uncommitted move.
  ApprovalLookup lastApproved(
    Directory projectRoot,
    String projectPath, {
    required MergedDocType? docType,
  }) {
    try {
      final prefix = _prefixOf(
        _git(projectRoot, ['rev-parse', '--show-prefix']),
      );
      var commits = _commitsFollowing(projectRoot, projectPath);
      if (commits.isEmpty) {
        final before = _pathBeforeMove(projectRoot, projectPath, prefix);
        if (before != null) {
          commits = _commitsFollowing(projectRoot, ':(top)$before');
        }
      }
      for (final (sha, path) in commits) {
        final copy = _git(projectRoot, ['show', '$sha:$path']);
        if (countsAsApprovedCopy(toLf(copy), docType)) {
          return ApprovedCopy(
            copy,
            commit: sha,
            path: _belowPrefix(path, prefix),
          );
        }
      }
      return const NoApprovedCopy();
    } on _GitCannotAnswer {
      return const UnknownHistory();
    } on ProcessException {
      return const UnknownHistory();
    } on FormatException {
      // git printed bytes that are not UTF-8, so its history cannot be read.
      return const UnknownHistory();
    }
  }

  List<(String, String)> _commitsFollowing(Directory root, String path) =>
      _commitsOf(
        _git(root, [
          'log',
          '--follow',
          '--diff-filter=d',
          '-z',
          '--format=%H',
          '--name-only',
          '--',
          path,
        ]),
      ).toList();

  /// Returns the top-level path [projectPath] held in `HEAD` before an
  /// uncommitted move, or null when git pairs it with no deleted path.
  ///
  /// Git detects the rename in a temporary copy of the index, so the user's
  /// index is never written.
  String? _pathBeforeMove(Directory root, String projectPath, String prefix) {
    final index = _git(root, ['rev-parse', '--git-path', 'index']).trim();
    final named = File(index);
    final source = named.isAbsolute ? named : File('${root.path}/$index');
    if (!source.existsSync()) return null;
    final scratch = Directory.systemTemp.createTempSync('specstone_index_');
    try {
      final copy = source.copySync('${scratch.path}/index');
      final env = {'GIT_INDEX_FILE': copy.path};
      final docsRoot = projectPath.split('/').first;
      _git(root, ['add', '-A', '--', docsRoot], environment: env);
      final status = _git(root, [
        'diff',
        '--cached',
        '-M',
        '-z',
        '--name-status',
        'HEAD',
      ], environment: env);
      return _renamedFrom(status, '$prefix$projectPath');
    } finally {
      scratch.deleteSync(recursive: true);
    }
  }

  String _git(
    Directory root,
    List<String> arguments, {
    Map<String, String>? environment,
  }) {
    final result = _runGit(
      arguments,
      workingDirectory: root.path,
      environment: environment,
    );
    if (result.exitCode != 0) throw const _GitCannotAnswer();
    return result.stdout as String;
  }
}

/// A git command that exited non-zero.
final class _GitCannotAnswer implements Exception {
  const new();
}

/// Returns the old path of the rename to [topLevelPath] in a
/// `diff -z --name-status` [status], or null when it lists none.
String? _renamedFrom(String status, String topLevelPath) {
  final fields = status.split('\x00');
  for (var i = 0; i + 2 < fields.length; i++) {
    if (fields[i].startsWith('R') && fields[i + 2] == topLevelPath) {
      return fields[i + 1];
    }
  }
  return null;
}

/// Returns the folder `git rev-parse --show-prefix` printed in [output].
///
/// The prefix is the project root's path below the top-level, ending in `/`,
/// or empty at the top-level; git ends the line with a newline.
String _prefixOf(String output) => output.replaceFirst(RegExp(r'\r?\n$'), '');

/// Returns [topLevelPath] relative to [prefix], or as given outside it.
String _belowPrefix(String topLevelPath, String prefix) =>
    topLevelPath.startsWith(prefix)
    ? topLevelPath.substring(prefix.length)
    : topLevelPath;

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
