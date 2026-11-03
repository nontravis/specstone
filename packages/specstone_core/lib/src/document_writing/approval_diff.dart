import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';

/// Returns the line diff of [oldText] and [newText] as unified hunks.
///
/// Both texts are read as LF. With [context] null, each hunk widens to the
/// whole of every unit (the frontmatter block, the head, or one `##` section)
/// that holds a changed line, in either text. With [context] `n`, it widens by
/// `n` lines, as `git diff -U<n>`. Hunks whose lines touch merge into one.
///
/// Each hunk is `@@ -<a>[,<n>] +<b>[,<m>] @@` then its lines prefixed by a
/// space, `-`, or `+`; a count of 1 is left out and a zero count names the
/// line before the change. Equal texts give `''`.
String approvalDiff(String oldText, String newText, {int? context}) {
  if (context != null) RangeError.checkNotNegative(context, 'context');
  final before = _linesOf(oldText);
  final after = _linesOf(newText);
  final ops = _opsOf(before, after);
  final shown = context == null
      ? _shownByUnit(ops, _unitStarts(oldText), _unitStarts(newText))
      : _shownByDistance(ops, context);

  final out = StringBuffer();
  var runStart = -1;
  for (var k = 0; k <= ops.length; k++) {
    final inRun = k < ops.length && shown[k];
    if (inRun && runStart < 0) runStart = k;
    if (!inRun && runStart >= 0) {
      _writeHunk(out, ops.sublist(runStart, k));
      runStart = -1;
    }
  }
  return out.toString();
}

/// Returns the `changes` rows naming each unit that differs in [oldText] and
/// [newText].
///
/// Both texts are read as LF. A unit is one frontmatter key (by name), the
/// frontmatter lines no key owns, the title, the lead (the head without its
/// title line), or one `##` section (by header text). A row names the unit as
/// ``field `key` ``, `frontmatter`, `title`, `lead`, or `` `## header` ``, with
/// ` (new)` or ` (removed)` when only one text has the unit. Rows follow the
/// new text; a removed unit follows the row of the unit before it in the old
/// text, or comes first when none precedes it.
List<String> changedUnits(String oldText, String newText) {
  final before = _unitsOf(oldText);
  final after = _unitsOf(newText);
  final oldById = {for (final unit in before) unit.id: unit};
  final newById = {for (final unit in after) unit.id: unit};

  final merged = [...after];
  String? previousId;
  for (final unit in before) {
    if (!newById.containsKey(unit.id)) {
      final at = previousId == null
          ? 0
          : merged.indexWhere((m) => m.id == previousId) + 1;
      merged.insert(at, unit);
    }
    previousId = unit.id;
  }

  return [
    for (final unit in merged)
      ?_rowOf(unit.label, oldById[unit.id], newById[unit.id]),
  ];
}

// MARK: - Lines and ops

enum _Kind { equal, delete, insert }

/// One step of the diff: [line] kept, removed, or added.
///
/// [oldAt] and [newAt] count the lines of each text consumed before this step.
final class _Op {
  const new(this.kind, this.line, this.oldAt, this.newAt);

  final _Kind kind;
  final String line;
  final int oldAt;
  final int newAt;

  bool get isChange => kind != .equal;
}

List<String> _linesOf(String text) {
  final lf = toLf(text);
  if (lf.isEmpty) return const [];
  final lines = lf.split('\n');
  if (lines.last.isEmpty) lines.removeLast();
  return lines;
}

/// Returns the LCS diff of [a] and [b]; per change block, deletes come first.
List<_Op> _opsOf(List<String> a, List<String> b) {
  final common = _lcsTable(a, b);
  final ops = <_Op>[];
  var i = 0;
  var j = 0;
  bool matches() => i < a.length && j < b.length && a[i] == b[j];
  while (i < a.length || j < b.length) {
    if (matches()) {
      ops.add(_Op(.equal, a[i], i, j));
      i++;
      j++;
      continue;
    }
    final inserts = <_Op>[];
    while ((i < a.length || j < b.length) && !matches()) {
      if (j >= b.length ||
          (i < a.length && common[i + 1][j] >= common[i][j + 1])) {
        ops.add(_Op(.delete, a[i], i, j));
        i++;
      } else {
        inserts.add(_Op(.insert, b[j], i, j));
        j++;
      }
    }
    ops.addAll(inserts);
  }
  return ops;
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

// MARK: - Which ops show

/// Whether each op shows: a change always, an equal line within [context] ops
/// of a change.
List<bool> _shownByDistance(List<_Op> ops, int context) {
  final shown = List.filled(ops.length, false);
  for (var k = 0; k < ops.length; k++) {
    if (!ops[k].isChange) continue;
    final from = k - context < 0 ? 0 : k - context;
    final to = k + context >= ops.length ? ops.length - 1 : k + context;
    for (var near = from; near <= to; near++) {
      shown[near] = true;
    }
  }
  return shown;
}

/// Whether each op shows: a change always, an equal line when its old line
/// sits in an old unit with a deleted line or its new line in a new unit with
/// an inserted line.
List<bool> _shownByUnit(
  List<_Op> ops,
  List<int> oldStarts,
  List<int> newStarts,
) {
  final markedOld = {
    for (final op in ops)
      if (op.kind == .delete) _unitIndex(oldStarts, op.oldAt),
  };
  final markedNew = {
    for (final op in ops)
      if (op.kind == .insert) _unitIndex(newStarts, op.newAt),
  };
  return [
    for (final op in ops)
      op.isChange ||
          markedOld.contains(_unitIndex(oldStarts, op.oldAt)) ||
          markedNew.contains(_unitIndex(newStarts, op.newAt)),
  ];
}

/// Returns the index of the unit holding [line] among units beginning at
/// [starts] (sorted).
int _unitIndex(List<int> starts, int line) {
  var index = 0;
  while (index + 1 < starts.length && starts[index + 1] <= line) {
    index++;
  }
  return index;
}

/// Returns the line index where each unit of [text] begins, ascending.
///
/// A unit starts at line 0, at the line after the closing `---` of the
/// frontmatter, and at each `##` header line outside a code fence.
List<int> _unitStarts(String text) {
  final lf = toLf(text);
  final doc = Doc.parse(lf);
  final frontmatterLines = _lineCount(
    lf.substring(0, lf.length - doc.afterFrontmatter.length),
  );
  return {
    0,
    if (frontmatterLines > 0) frontmatterLines,
    for (final at in doc.sectionLineIndexes) frontmatterLines + at,
  }.toList()..sort();
}

int _lineCount(String text) {
  if (text.isEmpty) return 0;
  final breaks = '\n'.allMatches(text).length;
  return text.endsWith('\n') ? breaks : breaks + 1;
}

// MARK: - Hunk text

void _writeHunk(StringBuffer out, List<_Op> run) {
  final oldCount = run.where((op) => op.kind != .insert).length;
  final newCount = run.where((op) => op.kind != .delete).length;
  out
    ..write('@@ -${_range(run.first.oldAt, oldCount)} ')
    ..write('+${_range(run.first.newAt, newCount)} @@\n');
  for (final op in run) {
    final prefix = switch (op.kind) {
      .equal => ' ',
      .delete => '-',
      .insert => '+',
    };
    out.write('$prefix${op.line}\n');
  }
}

/// Returns the range of [count] lines after [start] lines: the 1-based first
/// line alone for one line, `<first>,<count>` for more, and for none the line
/// before.
String _range(int start, int count) {
  if (count == 0) return '$start,0';
  return count == 1 ? '${start + 1}' : '${start + 1},$count';
}

// MARK: - Units

/// One comparable part of a doc.
///
/// `present` is false for a unit that is always listed but may hold no text,
/// the lead.
typedef _Unit = ({String id, String label, String content, bool present});

List<_Unit> _unitsOf(String text) {
  final doc = Doc.parse(toLf(text));
  final lines = doc.afterFrontmatter.split('\n');
  final firstSection = doc.sectionLineIndexes.firstOrNull ?? lines.length;
  final headLines = lines.sublist(0, firstSection);
  final title = doc.title;
  final titleAt = doc.titleLineIndex;
  if (titleAt != null) headLines.removeAt(titleAt);
  final lead = headLines.join('\n');

  final seen = <String, int>{};
  String idOf(String base) {
    final n = seen.update(base, (n) => n + 1, ifAbsent: () => 0);
    return '$base#$n';
  }

  return [
    for (final block in doc.frontmatter ?? const <KeyBlock>[])
      (
        id: block.key.isEmpty ? 'frontmatter#0' : idOf('field:${block.name}'),
        label: block.key.isEmpty ? 'frontmatter' : 'field `${block.name}`',
        content: block.text,
        present: true,
      ),
    if (title != null)
      (id: 'title#0', label: 'title', content: title, present: true),
    (
      id: 'lead#0',
      label: 'lead',
      content: lead,
      present: lead.trim().isNotEmpty,
    ),
    for (var s = 0; s < doc.sections.length; s++)
      (
        id: idOf('section:${doc.sections[s].headerText}'),
        label: '`## ${doc.sections[s].headerText}`',
        content: lines
            .sublist(
              doc.sectionLineIndexes[s],
              s + 1 < doc.sections.length
                  ? doc.sectionLineIndexes[s + 1]
                  : lines.length,
            )
            .join('\n'),
        present: true,
      ),
  ];
}

/// Returns the row for a unit that differs between [before] and [after], else
/// null.
String? _rowOf(String label, _Unit? before, _Unit? after) {
  final had = before != null && before.present;
  final has = after != null && after.present;
  if (has && !had) return '$label (new)';
  if (had && !has) return '$label (removed)';
  if (before != null && after != null && before.content != after.content) {
    return label;
  }
  return null;
}
