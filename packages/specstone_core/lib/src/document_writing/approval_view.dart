import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/document_writing/approval_diff.dart';
import 'package:specstone_core/src/document_writing/sentence_changes.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart'
    show sectionKeyOf;
import 'package:specstone_core/src/rendering/formatter.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// One draft as the approval view shows it.
final class DraftView {
  new({
    required this.name,
    required this.docType,
    this.mergedType,
    this.title,
    this.status,
    this.statusByTarget = const {},
    required this.docPath,
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

  /// Each code target's status, in config order; empty unless [status] is
  /// null and the project names two or more targets.
  final Map<String, String?> statusByTarget;

  /// The DocPath of the doc, relative to the docs root.
  final String docPath;

  /// The path of the doc relative to the project root.
  final String projectPath;

  /// The bytes of the draft on disk, decoded; any line ending.
  final String text;

  /// What git says about the last approved copy.
  final ApprovalLookup lookup;

  /// The sentences the draft dropped since that copy and the ones it added.
  final SentenceChanges sentences;

  /// What the draft changed since its approved copy, found on first use and
  /// shared by [renderApprovalView] and [draftViewJson].
  late final DraftComparison comparison = DraftComparison.of(this);
}

/// The texts of a draft and its approved copy as the view compares them, their
/// line diff, and the units that differ.
final class DraftComparison {
  const new _(this.newText, this.oldText, this.diff, this.units);

  factory of(DraftView draft) {
    final newText = comparableTextOf(draft.text, draft.mergedType);
    final oldText = _approvedTextOf(draft);
    final diff = LineDiff(oldText ?? '', newText);
    return DraftComparison._(
      newText,
      oldText,
      diff,
      oldText == null || diff.isEmpty
          ? const <ChangedUnit>[]
          : changedUnits(oldText, newText),
    );
  }

  /// The draft, laid out, without its approval marks.
  final String newText;

  /// The approved copy, laid out, or null when git found none.
  final String? oldText;

  /// The diff from [oldText], an empty text when there is none, to [newText].
  final LineDiff diff;

  /// The units that differ; none when [oldText] is null or [hasDiff] is false.
  final List<ChangedUnit> units;

  /// Whether the view shows a diff: a draft with no approved copy shows
  /// whole, any other only when [diff] holds a hunk.
  bool get hasDiff => oldText == null || !diff.isEmpty;
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
  final compared = draft.comparison;
  final diff = compared.diff.hunks(context: context);
  final hasDiff = compared.hasDiff;
  final changes = _changeCells(
    compared,
    plain: false,
    docType: draft.mergedType,
  );

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
  if (draft.statusByTarget.isNotEmpty) {
    out.writeln(_row('status', _codeSpan(_statusSpan(draft.statusByTarget))));
  } else if (draft.status case final status?) {
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

/// Returns the draft as one JSON object: the cells of its view, as plain text.
///
/// The keys are `name` (`<doc type>:<name>`), `docPath`, `title`, and `status`
/// or `statusByTarget` (each target's status, in config order) when [draft] has
/// them, `hash`, `lookup` (`found`, `none`, or `unknown`),
/// `renamedFrom` when the approved copy sits under another path (relative to
/// the docs root, as `docPath` is), `changes`
/// (the view's `changes` cells in order, joined by `, `, a section by its key),
/// and `dropped` and `new`.
Map<String, Object> draftViewJson(DraftView draft) {
  final lookup = draft.lookup;
  final changes = _changeCells(
    draft.comparison,
    plain: true,
    docType: draft.mergedType,
  );
  return {
    'name': '${draft.docType}:${draft.name}',
    'docPath': draft.docPath,
    'title': ?draft.title,
    if (draft.statusByTarget.isNotEmpty)
      'statusByTarget': draft.statusByTarget
    else
      'status': ?draft.status,
    'hash': baseHashOf(toLf(draft.text)),
    'lookup': switch (lookup) {
      ApprovedCopy() => 'found',
      NoApprovedCopy() => 'none',
      UnknownHistory() => 'unknown',
    },
    if (lookup case ApprovedCopy(:final path) when path != draft.projectPath)
      'renamedFrom': _onDocPathBase(path, draft),
    'changes': changes.join(', '),
    'dropped': draft.sentences.dropped,
    'new': draft.sentences.added,
  };
}

/// Returns [text] as LF, laid out by [docType], without the approval marks:
/// the text the view compares and reads sentences from.
String comparableTextOf(String text, MergedDocType? docType) =>
    withoutApprovalMarks(layOutDoc(toLf(text), docType));

/// Returns [projectPath], a path of [draft]'s approved copy, relative to the
/// docs root as `docPath` is.
///
/// A path outside the docs root, as git reports one left of the project,
/// stays as it is.
String _onDocPathBase(String projectPath, DraftView draft) {
  final docsPrefix = draft.projectPath.substring(
    0,
    draft.projectPath.length - draft.docPath.length,
  );
  return projectPath.startsWith(docsPrefix)
      ? projectPath.substring(docsPrefix.length)
      : projectPath;
}

/// Returns the laid-out approved copy of [draft], or null when git found none.
String? _approvedTextOf(DraftView draft) => switch (draft.lookup) {
  ApprovedCopy(:final text) => comparableTextOf(text, draft.mergedType),
  NoApprovedCopy() || UnknownHistory() => null,
};

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

/// Returns the `status` cell for [byTarget]: each `'<target> <status>'` pair
/// in map order joined by ` · `, a null status as `planned`.
String _statusSpan(Map<String, String?> byTarget) => [
  for (final entry in byTarget.entries)
    '${entry.key} ${entry.value ?? 'planned'}',
].join(' · ');

String _oldCell(ApprovalLookup lookup) => switch (lookup) {
  ApprovedCopy(:final commit) =>
    'approved copy in commit ${_codeSpan(commit.substring(0, 7))}',
  NoApprovedCopy() => 'none: never approved',
  UnknownHistory() => 'unknown: git cannot answer',
};

/// Returns the `changes` cells: `whole doc` for a draft with no approved copy,
/// `none` when [compared] holds no diff, else one cell per changed unit.
///
/// [plain] names each unit as text with no code span, a section by its key.
List<String> _changeCells(
  DraftComparison compared, {
  required bool plain,
  required MergedDocType? docType,
}) {
  if (compared.oldText == null) return const ['whole doc'];
  if (!compared.hasDiff) return const ['none'];
  return [
    for (final unit in compared.units)
      _changeCell(unit, plain: plain, docType: docType),
  ];
}

/// Returns the `changes` cell naming [unit], a suffix marking a one-side unit.
String _changeCell(
  ChangedUnit unit, {
  required bool plain,
  required MergedDocType? docType,
}) {
  final label = switch (unit.kind) {
    .frontmatter => 'frontmatter',
    .field => 'field ${plain ? unit.name : _codeSpan(unit.name)}',
    .title => 'title',
    .lead => 'lead',
    .section =>
      plain ? _sectionKeyOf(unit.name, docType) : _codeSpan('## ${unit.name}'),
  };
  return switch (unit.side) {
    .both => label,
    .added => '$label (new)',
    .removed => '$label (removed)',
  };
}

/// Returns the key of the section headed [header]: the template section id
/// whose header matches, else the key the header derives.
String _sectionKeyOf(String header, MergedDocType? docType) {
  for (final section in docType?.sections ?? const <MergedSection>[]) {
    if (headerKey(section.header) == headerKey(header)) return section.id;
  }
  return sectionKeyOf(header);
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
