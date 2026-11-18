import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/models/code_span.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/pattern_entry.dart';

/// One `banned_patterns` match on a line of a held section or on a prose field
/// value.
///
/// Exactly one of [section] and [field] is set.
final class BannedMatch {
  const new({
    this.section,
    this.field,
    required this.line,
    required this.entry,
    required this.match,
  }) : assert(
         (section == null) != (field == null),
         'a match names a section or a field, never both',
       );

  /// The position of the held section; null for a field match.
  final int? section;

  /// The id of the prose field; null for a section match.
  final String? field;

  /// The 1-based file line; a field match sits on its key's line.
  final int line;

  /// The position of the entry in [bannedEntriesOf] for the section; for a
  /// field match, in the doc-level entries.
  final int entry;

  /// The matched text; never empty and never excepted.
  final String match;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is BannedMatch &&
      other.section == section &&
      other.field == field &&
      other.line == line &&
      other.entry == entry &&
      other.match == match;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(section, field, line, entry, match);
}

/// Returns the banned entries of a held section: [type]'s, then [template]'s.
List<PatternEntry> bannedEntriesOf(
  MergedDocType type,
  MergedSection? template,
) => [...?type.lint.bannedPatterns, ...?template?.bannedPatterns];

/// Returns the banned-pattern matches on the lines of the held [sections] and
/// on the string values of the prose fields in [frontmatter].
///
/// The doc-level entries search every line, a section's own only its
/// `linePrefix` lines; fenced code and a line [isGenerated] marks are skipped.
/// A prose field takes the doc-level entries alone, each match on the key's
/// line from [keyLines]. A code-span match that names doc-tree folders is
/// kept, since that test reads the whole tree. Empty for an untyped doc.
List<BannedMatch> bannedMatchesOf(
  List<IndexedSection> sections,
  LineFacts facts,
  MergedDocType? type, {
  required Map<String, Object?> frontmatter,
  required Map<String, int> keyLines,
  required bool Function(int line) isGenerated,
}) {
  if (type == null) return const [];
  final templates = heldTemplatesOf(sections, type);
  final docCount = type.lint.bannedPatterns?.length ?? 0;
  final matches = <BannedMatch>[];
  for (var i = 0; i < sections.length; i++) {
    final entries = bannedEntriesOf(type, templates[i]);
    if (entries.isEmpty) continue;
    final prefix = templates[i]?.linePrefix;
    for (final searched in searchLinesOf(sections, facts, i)) {
      if (isGenerated(searched.line)) continue;
      final onPrefix = prefix == null || searched.raw.startsWith(prefix);
      final searchedCount = onPrefix ? entries.length : docCount;
      for (var k = 0; k < searchedCount; k++) {
        for (final match in _matchesOf(entries[k], searched)) {
          matches.add(
            BannedMatch(
              section: i,
              line: searched.line,
              entry: k,
              match: match,
            ),
          );
        }
      }
    }
  }
  return [...matches, ..._fieldMatchesOf(type, frontmatter, keyLines)];
}

List<BannedMatch> _fieldMatchesOf(
  MergedDocType type,
  Map<String, Object?> frontmatter,
  Map<String, int> keyLines,
) {
  final entries = type.lint.bannedPatterns ?? const <PatternEntry>[];
  final matches = <BannedMatch>[];
  for (final field in type.fields) {
    final value = frontmatter[field.id];
    final line = keyLines[field.id];
    if (!field.isProse || value is! String || line == null) continue;
    for (final text in value.split('\n')) {
      for (var k = 0; k < entries.length; k++) {
        for (final match in _matchesOf(entries[k], SearchLine(text, line))) {
          matches.add(
            BannedMatch(field: field.id, line: line, entry: k, match: match),
          );
        }
      }
    }
  }
  return matches;
}

/// Returns [matches] as the JSON lists the index stores.
List<Object?> bannedMatchesToJson(List<BannedMatch> matches) => [
  for (final m in matches) [m.section, m.field, m.line, m.entry, m.match],
];

/// Reads the matches [bannedMatchesToJson] wrote.
List<BannedMatch> bannedMatchesFromJson(List<Object?> json) => [
  for (final m in json.cast<List<Object?>>())
    BannedMatch(
      section: m[0] as int?,
      field: m[1] as String?,
      line: m[2]! as int,
      entry: m[3]! as int,
      match: m[4]! as String,
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
  for (final BodyLine(:text, :line, :fenced) in sectionBodyLines(
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
    for (final CodeSpan(:start, :end, :ticks) in _spans)
      raw.substring(start + ticks, end - ticks),
  ];

  late final List<CodeSpan> _spans = codeSpansOf(raw);

  String _blankSpans() {
    if (_spans.isEmpty) return raw;
    final blanked = StringBuffer();
    var from = 0;
    for (final CodeSpan(:start, :end) in _spans) {
      blanked
        ..write(raw.substring(from, start))
        ..write(' ' * (end - start));
      from = end;
    }
    return (blanked..write(raw.substring(from))).toString();
  }
}
