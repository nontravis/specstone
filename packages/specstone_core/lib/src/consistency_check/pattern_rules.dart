import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/doc_items.dart'
    show SectionItem, SectionItemKind;
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/index_query/banned_matches.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/pattern_entry.dart';

/// Returns the pattern findings of a typed [doc]; an untyped doc has none.
///
/// A `banned_patterns` entry holds one finding per match the refresh stored
/// for a line of a held section, fenced code excluded; the doc-level entries
/// apply on every line, a section's own on its `linePrefix` lines. A prose
/// field's value takes the doc-level entries alone, its finding on the key's
/// line under the key `field`. A
/// `required_patterns` entry with no matching line in its held section holds
/// one finding at the header; with `per_subsection`, one finding at each `###`
/// heading whose subsection has no matching line.
Iterable<Finding> checkPatterns(CheckContext context, IndexedDoc doc) sync* {
  final type = context.typeOf(doc);
  if (type == null) return;
  final content = context.contentOf(doc);
  final held = content.sections;
  final matchesBySection = <int, List<BannedMatch>>{};
  final fieldMatches = <BannedMatch>[];
  for (final match in content.bannedMatches) {
    if (match.section case final section?) {
      (matchesBySection[section] ??= []).add(match);
    } else {
      fieldMatches.add(match);
    }
  }
  yield* _fieldFindings(context, doc, type, fieldMatches);
  for (var i = 0; i < held.length; i++) {
    final template = context.templateSectionAt(doc, i);
    final sectionKey = template?.id ?? held[i].key;
    final entries = bannedEntriesOf(type, template);
    for (final found in matchesBySection[i] ?? const <BannedMatch>[]) {
      final banned = entries[found.entry];
      if (banned.scope == PatternScope.code &&
          (_namesFolders(context, found.match) ||
              _inReferenceSpan(found.match, [
                context.linesOf(doc).lines[found.line - 1],
              ]))) {
        continue;
      }
      yield context.finding(
        doc,
        FindingKind.patternBanned,
        line: found.line,
        message: '${banned.message}: ${found.match}',
        keys: {
          'pattern': banned.id,
          'section': sectionKey,
          'match': found.match,
        },
      );
    }
    final required = template?.requiredPatterns ?? const <PatternEntry>[];
    if (required.isEmpty) continue;
    final lines = searchLinesOf(held, content.lineFacts, i);
    final headings = required.any((entry) => entry.perSubsection)
        ? _subsectionHeadings(context.itemsIn(doc, i))
        : const <({int line, String text})>[];
    for (final entry in required) {
      yield* entry.perSubsection
          ? _missingPerSubsection(
              context,
              doc,
              entry,
              sectionKey,
              headings,
              lines,
            )
          : _missingInSection(
              context,
              doc,
              entry,
              sectionKey,
              content.lineFacts.sectionLines[i],
              lines,
            );
    }
  }
}

/// Returns one finding per stored match on a prose field value, the doc-level
/// entry it names read as a section's.
Iterable<Finding> _fieldFindings(
  CheckContext context,
  IndexedDoc doc,
  MergedDocType type,
  List<BannedMatch> matches,
) sync* {
  final entries = type.lint.bannedPatterns ?? const <PatternEntry>[];
  final docLines = context.linesOf(doc);
  for (final found in matches) {
    final banned = entries[found.entry];
    final field = found.field!;
    if (banned.scope == PatternScope.code &&
        (_namesFolders(context, found.match) ||
            _inReferenceSpan(
              found.match,
              docLines.writtenValueOf(field)?.split('\n') ?? const [],
            ))) {
      continue;
    }
    yield context.finding(
      doc,
      FindingKind.patternBanned,
      line: found.line,
      message: '${banned.message}: ${found.match}',
      keys: {'pattern': banned.id, 'field': field, 'match': found.match},
    );
  }
}

Iterable<Finding> _missingInSection(
  CheckContext context,
  IndexedDoc doc,
  PatternEntry entry,
  String sectionKey,
  int headerLine,
  List<SearchLine> lines,
) sync* {
  if (lines.any((line) => entry.regExp.hasMatch(line.prose))) return;
  yield context.finding(
    doc,
    FindingKind.patternMissing,
    line: headerLine,
    message: entry.message,
    keys: {'pattern': entry.id, 'section': sectionKey},
  );
}

/// Returns one finding per `###` subsection in [headings] that no line of its
/// own matches [entry].
Iterable<Finding> _missingPerSubsection(
  CheckContext context,
  IndexedDoc doc,
  PatternEntry entry,
  String sectionKey,
  List<({int line, String text})> headings,
  List<SearchLine> lines,
) sync* {
  for (var k = 0; k < headings.length; k++) {
    final (:line, :text) = headings[k];
    final end = k + 1 < headings.length ? headings[k + 1].line : null;
    final held = lines.where(
      (searched) =>
          searched.line >= line && (end == null || searched.line < end),
    );
    if (held.any((searched) => entry.regExp.hasMatch(searched.prose))) continue;
    yield context.finding(
      doc,
      FindingKind.patternMissing,
      line: line,
      message: entry.message,
      keys: {'pattern': entry.id, 'section': sectionKey, 'subsection': text},
    );
  }
}

/// Returns the line and text of each top-level `###` heading of [items].
List<({int line, String text})> _subsectionHeadings(List<SectionItem> items) =>
    [
      for (final item in items)
        if (item.kind == SectionItemKind.heading && !item.nested)
          (line: item.line, text: item.head),
    ];

/// Whether [matched], a code-span match, names a doc-tree folder or a
/// `/`-joined run of them: it names a place in the doc tree, so no hit.
///
/// Other scopes read prose, where a folder name is ordinary text.
bool _namesFolders(CheckContext context, String matched) =>
    matched.split('/').every(context.folderNames.contains);

/// Whether every code span of [lines] that holds [matched] is one the
/// reference grammar reads as a doc address with no lookup.
///
/// A stored match names no span, so a match two spans hold stays a hit unless
/// both are references.
bool _inReferenceSpan(String matched, Iterable<String> lines) {
  final holding = [
    for (final line in lines)
      ...SearchLine(line, 0).code.where((span) => span.contains(matched)),
  ];
  return holding.isNotEmpty &&
      holding.every((span) => readDocAddress(span).isReferenceWithoutLookup);
}
