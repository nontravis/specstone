import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/template_text_rules.dart'
    show sectionsKeepingTemplateText;
import 'package:specstone_core/src/doc_model/models/section_item.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/index_query/banned_matches.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/models/banned_match.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// Returns the pattern findings of a typed [doc]; an untyped doc has none.
///
/// A banned entry reports each match the refresh stored; a required entry
/// reports a section, or with `per_subsection` a `###` subsection, with no
/// line it matches. A section that keeps a template line gets no required
/// finding, `template_text_left` alone.
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
  late final keepingTemplateText = sectionsKeepingTemplateText(context, doc);
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
        : const <_Heading>[];
    final missing = [
      for (final entry in required)
        ...entry.perSubsection
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
              ),
    ];
    if (missing.isNotEmpty && !keepingTemplateText.contains(sectionKey)) {
      yield* missing;
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
  if (lines.any((line) => _matches(entry, line))) return;
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
  List<_Heading> headings,
  List<SearchLine> lines,
) sync* {
  for (var k = 0; k < headings.length; k++) {
    final _Heading(:line, :text) = headings[k];
    final end = k + 1 < headings.length ? headings[k + 1].line : null;
    final held = lines.where(
      (searched) =>
          searched.line >= line && (end == null || searched.line < end),
    );
    if (held.any((searched) => _matches(entry, searched))) continue;
    yield context.finding(
      doc,
      FindingKind.patternMissing,
      line: line,
      message: entry.message,
      keys: {'pattern': entry.id, 'section': sectionKey, 'subsection': text},
    );
  }
}

/// Whether [entry] matches [line] as its `in` scope reads it.
bool _matches(PatternEntry entry, SearchLine line) =>
    line.readAs(entry.scope).any(entry.regExp.hasMatch);

/// Returns the line and text of each top-level `###` heading of [items].
List<_Heading> _subsectionHeadings(List<SectionItem> items) => [
  for (final item in items)
    if (item.kind == SectionItemKind.heading && !item.nested)
      _Heading(line: item.line, text: item.head),
];

/// A top-level `###` heading: its file line and its text.
final class _Heading {
  const new({required this.line, required this.text});

  final int line;
  final String text;
}

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
