import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
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
  for (var i = 0; i < held.length; i++) {
    final template = context.templateSectionAt(doc, i);
    final sectionKey = template?.id ?? held[i].key;
    final entries = bannedEntriesOf(type, template);
    for (final (:section, :line, :entry, :match) in content.bannedMatches) {
      if (section != i) continue;
      final banned = entries[entry];
      if (banned.scope == PatternScope.code && _namesFolders(context, match)) {
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
