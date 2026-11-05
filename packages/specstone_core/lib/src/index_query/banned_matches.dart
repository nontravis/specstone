import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/pattern_entry.dart';

/// One `banned_patterns` match on a line of a held section.
///
/// - `section`: the position of the held section.
/// - `line`: the 1-based file line.
/// - `entry`: the position of the entry in [bannedEntriesOf] for the section.
/// - `match`: the matched text; never empty and never excepted.
typedef BannedMatch = ({int section, int line, int entry, String match});

/// Returns the banned entries of a held section: [type]'s, then [template]'s.
List<PatternEntry> bannedEntriesOf(
  MergedDocType type,
  MergedSection? template,
) => [...?type.lint.bannedPatterns, ...?template?.bannedPatterns];

/// Returns the banned-pattern matches on the lines of the held [sections].
///
/// The doc-level entries search every line, a section's own only its
/// `linePrefix` lines; fenced code is skipped. A code-span match that names
/// doc-tree folders is kept, since that test reads the whole tree. Empty for
/// an untyped doc.
List<BannedMatch> bannedMatchesOf(
  List<IndexedSection> sections,
  LineFacts facts,
  MergedDocType? type,
) {
  if (type == null) return const [];
  final templates = heldTemplatesOf(sections, type);
  final docCount = type.lint.bannedPatterns?.length ?? 0;
  final matches = <BannedMatch>[];
  for (var i = 0; i < sections.length; i++) {
    final entries = bannedEntriesOf(type, templates[i]);
    if (entries.isEmpty) continue;
    final prefix = templates[i]?.linePrefix;
    for (final searched in searchLinesOf(sections, facts, i)) {
      final onPrefix = prefix == null || searched.raw.startsWith(prefix);
      final searchedCount = onPrefix ? entries.length : docCount;
      for (var k = 0; k < searchedCount; k++) {
        for (final match in _matchesOf(entries[k], searched)) {
          matches.add((
            section: i,
            line: searched.line,
            entry: k,
            match: match,
          ));
        }
      }
    }
  }
  return matches;
}

/// Returns [matches] as the JSON lists the index stores.
List<Object?> bannedMatchesToJson(List<BannedMatch> matches) => [
  for (final m in matches) [m.section, m.line, m.entry, m.match],
];

/// Reads the matches [bannedMatchesToJson] wrote.
List<BannedMatch> bannedMatchesFromJson(List<Object?> json) => [
  for (final m in json.cast<List<Object?>>())
    (
      section: m[0]! as int,
      line: m[1]! as int,
      entry: m[2]! as int,
      match: m[3]! as String,
    ),
];

/// Returns the header line and the unfenced body lines of held section
/// [index], the lines the patterns search.
List<SearchLine> searchLinesOf(
  List<IndexedSection> sections,
  LineFacts facts,
  int index,
) => [
  SearchLine(sections[index].headerLine, facts.sectionLines[index]),
  for (final (:text, :line, :fenced) in sectionBodyLines(
    sections,
    facts,
    index,
  ))
    if (!fenced) SearchLine(text, line),
];

Iterable<String> _matchesOf(PatternEntry entry, SearchLine line) sync* {
  final searched = switch (entry.scope) {
    PatternScope.text => [line.prose],
    PatternScope.code => line.code,
    PatternScope.all => [line.raw],
  };
  for (final haystack in searched) {
    for (final match in entry.regExp.allMatches(haystack)) {
      final matched = match.group(0)!;
      if (matched.isEmpty || entry.isExcepted(matched)) continue;
      yield matched;
    }
  }
}

/// One unfenced line the patterns search, split at its inline code spans once.
///
/// A span opens on a run of backticks and closes on the next run of the same
/// length, as CommonMark counts it; a run that finds no closer is plain text.
final class SearchLine {
  new(this.raw, this.line);

  /// The line as written; it holds no line end.
  final String raw;

  /// The 1-based file line.
  final int line;

  /// [raw] with each code span, backticks included, blanked to spaces of
  /// equal length, so match positions and neighbours stay put.
  late final String prose = _blankSpans();

  /// The text inside each code span, backticks dropped.
  late final List<String> code = [
    for (final (:start, :end, :ticks) in _spans)
      raw.substring(start + ticks, end - ticks),
  ];

  late final List<CodeSpan> _spans = codeSpansOf(raw);

  String _blankSpans() {
    if (_spans.isEmpty) return raw;
    final blanked = StringBuffer();
    var from = 0;
    for (final (:start, :end, ticks: _) in _spans) {
      blanked
        ..write(raw.substring(from, start))
        ..write(' ' * (end - start));
      from = end;
    }
    return (blanked..write(raw.substring(from))).toString();
  }
}

/// One code span of a line: the offsets of its first and one past its last
/// backtick, and the length of the backtick run that opens and closes it.
typedef CodeSpan = ({int start, int end, int ticks});

/// Returns each code span of [line], in order.
List<CodeSpan> codeSpansOf(String line) {
  // indexOf, not a RegExp: the regex engine tries every offset of a pattern
  // that opens with one character.
  final spans = <CodeSpan>[];
  var open = line.indexOf('`');
  while (open >= 0) {
    final ticks = _runLengthAt(line, open);
    final close = _closerOf(line, open + ticks, ticks);
    if (close < 0) {
      open = line.indexOf('`', open + ticks);
      continue;
    }
    spans.add((start: open, end: close + ticks, ticks: ticks));
    open = line.indexOf('`', close + ticks);
  }
  return spans;
}

/// Returns the offset of the first run of exactly [ticks] backticks in [line]
/// at or after [from], or -1.
int _closerOf(String line, int from, int ticks) {
  var at = line.indexOf('`', from);
  while (at >= 0) {
    final run = _runLengthAt(line, at);
    if (run == ticks) return at;
    at = line.indexOf('`', at + run);
  }
  return -1;
}

/// Returns the length of the backtick run that starts at [at] in [line].
int _runLengthAt(String line, int at) {
  var end = at;
  while (end < line.length && line.codeUnitAt(end) == 0x60) {
    end++;
  }
  return end - at;
}
