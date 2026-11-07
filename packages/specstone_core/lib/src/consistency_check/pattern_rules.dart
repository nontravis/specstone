import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/index_query/banned_matches.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/pattern_entry.dart';

/// Returns the pattern findings of a typed [doc]; an untyped doc has none.
///
/// A `banned_patterns` entry holds one finding per match the refresh stored
/// for a line of a held section, fenced code excluded; the doc-level entries
/// apply on every line, a section's own on its `linePrefix` lines. A
/// `required_patterns` entry with no matching line in its held section holds
/// one finding at the header.
Iterable<Finding> checkPatterns(CheckContext context, IndexedDoc doc) sync* {
  final type = context.typeOf(doc);
  if (type == null) return;
  final content = context.contentOf(doc);
  final held = content.sections;
  final matchesBySection = <int, List<BannedMatch>>{};
  for (final match in content.bannedMatches) {
    (matchesBySection[match.section] ??= []).add(match);
  }
  for (var i = 0; i < held.length; i++) {
    final template = context.templateSectionAt(doc, i);
    final sectionKey = template?.id ?? held[i].key;
    final entries = bannedEntriesOf(type, template);
    for (final (:line, :entry, :match, section: _)
        in matchesBySection[i] ?? const <BannedMatch>[]) {
      final banned = entries[entry];
      if (banned.scope == PatternScope.code &&
          (_namesFolders(context, match) ||
              _inReferenceSpan(context, doc, line, match))) {
        continue;
      }
      yield context.finding(
        doc,
        FindingKind.patternBanned,
        line: line,
        message: '${banned.message}: $match',
        keys: {'pattern': banned.id, 'section': sectionKey, 'match': match},
      );
    }
    final required = template?.requiredPatterns ?? const <PatternEntry>[];
    if (required.isEmpty) continue;
    final lines = searchLinesOf(held, content.lineFacts, i);
    for (final entry in required) {
      final regExp = entry.regExp;
      if (lines.any((line) => regExp.hasMatch(line.prose))) continue;
      yield context.finding(
        doc,
        FindingKind.patternMissing,
        line: content.lineFacts.sectionLines[i],
        message: entry.message,
        keys: {'pattern': entry.id, 'section': sectionKey},
      );
    }
  }
}

/// Whether [matched], a code-span match, names a doc-tree folder or a
/// `/`-joined run of them: it names a place in the doc tree, so no hit.
///
/// Other scopes read prose, where a folder name is ordinary text.
bool _namesFolders(CheckContext context, String matched) =>
    matched.split('/').every(context.folderNames.contains);

/// Whether every code span of the 1-based [line] that holds [matched] is one
/// the reference grammar reads as a doc address with no lookup (R62).
///
/// A stored match names no span, so a match two spans hold stays a hit unless
/// both are references.
bool _inReferenceSpan(
  CheckContext context,
  IndexedDoc doc,
  int line,
  String matched,
) {
  final holding = SearchLine(
    context.linesOf(doc).lines[line - 1],
    line,
  ).code.where((span) => span.contains(matched));
  return holding.isNotEmpty &&
      holding.every((span) => readDocAddress(span).isReferenceWithoutLookup);
}
