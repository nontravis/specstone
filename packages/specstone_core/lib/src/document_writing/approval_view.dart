import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/document_writing/approval_diff.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';

/// One draft as the approval view shows it.
final class DraftView {
  const new({
    required this.name,
    required this.docType,
    this.title,
    this.status,
    required this.projectPath,
    required this.text,
    required this.lookup,
  });

  /// The doc name, which heads the view when [title] is null.
  final String name;

  /// The doc type the index gives.
  final String docType;

  /// The title line of the doc, or null when it has none.
  final String? title;

  /// The status the index gives, or null when it gives none.
  final String? status;

  /// The path of the doc relative to the project root.
  final String projectPath;

  /// The bytes of the draft on disk, decoded; any line ending.
  final String text;

  /// What git says about the last approved copy.
  final ApprovalLookup lookup;
}

/// Returns [lfText] without its `draft` and `approved` frontmatter key blocks.
///
/// The marks differ between a draft and its approved copy by design, so the
/// view compares the texts without them.
String withoutApprovalMarks(String lfText) =>
    withKeyBlock(withKeyBlock(lfText, 'draft', null), 'approved', null);

/// Returns the approval view of [draft]: heading, path, field table, and the
/// fenced diff from its last approved copy, ending in `\n`.
///
/// [position] of [count] numbers the draft in the heading. [context] sets the
/// lines of context per hunk, else every changed unit shows whole. With
/// [color], diff lines carry ANSI colour and nothing else does. A draft with
/// no approved copy shows whole. The `hash` row is the base of the draft as LF,
/// marks included.
String renderApprovalView(
  DraftView draft, {
  required int position,
  required int count,
  int? context,
  bool color = false,
}) {
  final lookup = draft.lookup;
  final newText = withoutApprovalMarks(toLf(draft.text));
  final oldText = switch (lookup) {
    ApprovedCopy(:final text) => withoutApprovalMarks(toLf(text)),
    NoApprovedCopy() || UnknownHistory() => null,
  };
  final diff = approvalDiff(oldText ?? '', newText, context: context);
  final hasDiff = oldText == null || diff.isNotEmpty;
  final changes = switch (oldText) {
    null => const ['whole doc'],
    _ when !hasDiff => const ['none'],
    final old => changedUnits(old, newText),
  };

  final out = StringBuffer()
    ..writeln('### Draft $position/$count · ${draft.title ?? draft.name}')
    ..writeln('`${draft.projectPath}`');
  if (lookup case ApprovedCopy(:final path) when path != draft.projectPath) {
    out.writeln('renamed from `$path`');
  }
  out
    ..writeln()
    ..writeln(_row('field', 'value'))
    ..writeln('|---------|-------|')
    ..writeln(_row('doc', '`${draft.name}` (${draft.docType})'));
  if (draft.status case final status?) {
    out.writeln(_row('status', '`$status`'));
  }
  out
    ..writeln(_row('hash', '`${baseHashOf(toLf(draft.text))}`'))
    ..writeln(_row('old', _oldCell(lookup)));
  for (final (at, change) in changes.indexed) {
    out.writeln(_row(at == 0 ? 'changes' : '', change));
  }
  out.writeln();
  if (hasDiff) {
    out.write(_fenced(color ? _colored(diff) : diff, _fenceFor(diff)));
  } else {
    out.writeln(_noChange);
  }
  return out.toString();
}

const _noChange = 'no change since the approved copy';

// MARK: - Table

String _row(String field, String value) => '| ${field.padRight(7)} | $value |';

String _oldCell(ApprovalLookup lookup) => switch (lookup) {
  ApprovedCopy(:final commit) =>
    'approved copy in commit `${commit.substring(0, 7)}`',
  NoApprovedCopy() => 'none: never approved',
  UnknownHistory() => 'unknown: git cannot answer',
};

// MARK: - Diff block

/// Returns the fence for [diff]: backticks, one more than its longest backtick
/// run, at least three.
String _fenceFor(String diff) {
  var length = 3;
  for (final run in RegExp('`+').allMatches(diff)) {
    final needed = run.end - run.start + 1;
    if (needed > length) length = needed;
  }
  return '`' * length;
}

String _fenced(String body, String fence) => '${fence}diff\n$body$fence\n';

const _red = '\x1b[31m';
const _green = '\x1b[32m';
const _cyan = '\x1b[36m';
const _reset = '\x1b[0m';

/// Returns [diff] with each `@@`, `-`, and `+` line wrapped in its colour.
String _colored(String diff) {
  final out = StringBuffer();
  for (final line in diff.split('\n')) {
    if (line.isEmpty) continue;
    final code = switch (line[0]) {
      '@' => _cyan,
      '-' => _red,
      '+' => _green,
      _ => null,
    };
    out.writeln(code == null ? line : '$code$line$_reset');
  }
  return out.toString();
}
