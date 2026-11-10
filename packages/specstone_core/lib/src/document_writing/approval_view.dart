import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/document_writing/approval_diff.dart';
import 'package:specstone_core/src/document_writing/sentence_changes.dart';
import 'package:specstone_core/src/rendering/formatter.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// One draft as the approval view shows it.
final class DraftView {
  const new({
    required this.name,
    required this.docType,
    this.mergedType,
    this.title,
    this.status,
    required this.projectPath,
    required this.text,
    required this.lookup,
    required this.sentences,
  });

  /// The doc name, which heads the view when [title] is null.
  final String name;

  /// The doc type the index gives.
  final String docType;

  /// The merged doc type that lays out both copies, or null to compare as
  /// written.
  final MergedDocType? mergedType;

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

  /// The sentences the draft dropped since that copy and the ones it added.
  final SentenceChanges sentences;
}

/// Returns [lfText] without its `draft` and `approved` frontmatter key blocks.
///
/// The marks differ between a draft and its approved copy by design, so the
/// view compares the texts without them.
String withoutApprovalMarks(String lfText) =>
    withKeyBlock(withKeyBlock(lfText, 'draft', null), 'approved', null);

/// Returns the approval view of [draft]: heading, path, field table, and the
/// fenced diff from its last approved copy, then each sentence dropped and each
/// sentence new, ending in `\n`.
///
/// [position] of [count] numbers the draft in the heading. [context] sets the
/// lines of context per hunk, else every changed unit shows whole. With
/// [color], diff lines carry ANSI colour and nothing else does. A draft with
/// no approved copy shows whole. Both copies are laid out first, so a
/// layout-only change shows as none. The `hash` row is the base of the draft as
/// LF, marks included.
String renderApprovalView(
  DraftView draft, {
  required int position,
  required int count,
  int? context,
  bool color = false,
}) {
  final lookup = draft.lookup;
  final newText = comparableTextOf(draft.text, draft.mergedType);
  final oldText = switch (lookup) {
    ApprovedCopy(:final text) => comparableTextOf(text, draft.mergedType),
    NoApprovedCopy() || UnknownHistory() => null,
  };
  final diff = approvalDiff(oldText ?? '', newText, context: context);
  final hasDiff = oldText == null || diff.isNotEmpty;
  final changes = switch (oldText) {
    null => const ['whole doc'],
    _ when !hasDiff => const ['none'],
    final old => [
      for (final unit in changedUnits(old, newText)) _changeCell(unit),
    ],
  };

  final out = StringBuffer()
    ..writeln('### Draft $position/$count · ${draft.title ?? draft.name}')
    ..writeln(_codeSpan(draft.projectPath));
  if (lookup case ApprovedCopy(:final path) when path != draft.projectPath) {
    out.writeln('renamed from ${_codeSpan(path)}');
  }
  out
    ..writeln()
    ..writeln(_row('field', 'value'))
    ..writeln('|---------|-------|')
    ..writeln(_row('doc', '${_codeSpan(draft.name)} (${draft.docType})'));
  if (draft.status case final status?) {
    out.writeln(_row('status', _codeSpan(status)));
  }
  out
    ..writeln(_row('hash', _codeSpan(baseHashOf(toLf(draft.text)))))
    ..writeln(_row('old', _oldCell(lookup)));
  for (final (at, change) in changes.indexed) {
    out.writeln(_row(at == 0 ? 'changes' : '', change));
  }
  final (:dropped, :added) = draft.sentences;
  out
    ..writeln(_row('dropped', _count(dropped.length, 'dropped')))
    ..writeln(_row('new', _count(added.length, 'new')))
    ..writeln();
  if (hasDiff) {
    out.write(_fenced(color ? _colored(diff) : diff, _fenceFor(diff)));
  } else {
    out.writeln(_noChange);
  }
  _writeList(out, 'Dropped sentences:', dropped);
  _writeList(out, 'New sentences:', added);
  return out.toString();
}

/// Returns [text] as LF, laid out by [docType], without the approval marks:
/// the text the view compares and reads sentences from.
String comparableTextOf(String text, MergedDocType? docType) =>
    withoutApprovalMarks(layOutDoc(toLf(text), docType));

const _noChange = 'no change since the approved copy';

// MARK: - Sentences

/// Returns the `dropped` or `new` cell: `1 sentence new`, `0 sentences new`.
String _count(int count, String kind) =>
    '$count ${count == 1 ? 'sentence' : 'sentences'} $kind';

/// Writes a blank line, [heading], and one `- ` line per sentence of
/// [sentences]; nothing for none.
void _writeList(StringBuffer out, String heading, List<String> sentences) {
  if (sentences.isEmpty) return;
  out
    ..writeln()
    ..writeln(heading);
  for (final sentence in sentences) {
    out.writeln('- $sentence');
  }
}

// MARK: - Table

/// Returns one table row; a `|` in either cell is escaped so it splits none.
String _row(String field, String value) =>
    '| ${_escapePipes(field.padRight(7))} | ${_escapePipes(value)} |';

String _escapePipes(String cell) => cell.replaceAll('|', r'\|');

String _oldCell(ApprovalLookup lookup) => switch (lookup) {
  ApprovedCopy(:final commit) =>
    'approved copy in commit ${_codeSpan(commit.substring(0, 7))}',
  NoApprovedCopy() => 'none: never approved',
  UnknownHistory() => 'unknown: git cannot answer',
};

/// Returns the `changes` cell naming [unit], a suffix marking a one-side unit.
String _changeCell(ChangedUnit unit) {
  final label = switch (unit.kind) {
    .frontmatter => 'frontmatter',
    .field => 'field ${_codeSpan(unit.name)}',
    .title => 'title',
    .lead => 'lead',
    .section => _codeSpan('## ${unit.name}'),
  };
  return switch (unit.side) {
    .both => label,
    .added => '$label (new)',
    .removed => '$label (removed)',
  };
}

// MARK: - Markdown

/// Returns [text] as a markdown code span that no backtick inside it closes.
///
/// The span's backtick run is one longer than the longest run in [text]; a
/// space pads each side when [text] starts or ends with a backtick, as
/// CommonMark strips one such space from each side.
String _codeSpan(String text) {
  final fence = '`' * (_longestBacktickRun(text) + 1);
  final pad = text.startsWith('`') || text.endsWith('`') ? ' ' : '';
  return '$fence$pad$text$pad$fence';
}

int _longestBacktickRun(String text) {
  var longest = 0;
  for (final run in RegExp('`+').allMatches(text)) {
    if (run.end - run.start > longest) longest = run.end - run.start;
  }
  return longest;
}

// MARK: - Diff block

/// Returns the fence for [diff]: backticks, one more than its longest backtick
/// run, at least three.
String _fenceFor(String diff) {
  final length = _longestBacktickRun(diff) + 1;
  return '`' * (length < 3 ? 3 : length);
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
