import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/feature_pattern_rules.dart'
    show isSkipSpan, skipLinesOf;
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/reference_rules.dart'
    show architectureTypeId, concernsSectionId, seeTargetIn;
import 'package:specstone_core/src/consistency_check/scenario_blocks.dart'
    show heldSectionIndex;
import 'package:specstone_core/src/index_query/cite_candidates.dart';
import 'package:specstone_core/src/index_query/cite_resolution.dart';
import 'package:specstone_core/src/index_query/held_sections.dart'
    show sectionBodyLines;
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// The link form a message names when the cite picks no one link.
const _linkForm = '[text](<path>)';

/// The tree each check run resolves cites against, built once per run.
final _trees = Expando<IndexCiteTree>();

/// Returns a `cite_unlinked` finding for each old cite form in the body of
/// the typed [doc] (consistency_check `report_old_cite_forms`).
///
/// Each stored cite candidate resolves against the index as the check runs,
/// so no doc text is read. One that names no doc is plain text, and a
/// Concerns `see` target is no cite.
Iterable<Finding> checkOldCites(CheckContext context, IndexedDoc doc) sync* {
  final candidates = context.contentOf(doc).lineFacts.citeCandidates;
  if (candidates.isEmpty) return;
  final tree = _trees[context] ??= IndexCiteTree(
    context.index,
    contentOf: context.contentOf,
  );
  final seeTargets = seeTargetsIn(context.contentOf(doc), context.typeOf(doc));
  final skips = skipLinesOf(context, doc);
  for (final candidate in candidates) {
    if (isSeeTargetCite(seeTargets[candidate.line], candidate)) continue;
    if (isSkipSpan(skips, candidate.line, candidate.written)) continue;
    final message = _messageOf(
      resolveCite(tree, doc.docPath, candidate),
      doc,
      candidate,
    );
    if (message == null) continue;
    yield context.finding(
      doc,
      FindingKind.citeUnlinked,
      line: candidate.line,
      message: message,
      keys: {'cite': candidate.written},
    );
  }
}

/// Returns the message of [resolved], the cite [candidate] of [doc], or null
/// when it names no doc.
String? _messageOf(
  CiteResolution resolved,
  IndexedDoc doc,
  CiteCandidate candidate,
) {
  final cite = 'cite ${candidate.written} is no link';
  return switch (resolved) {
    CiteNoDoc() => null,
    final CiteLink link => switch (citeLinkMarkdown(doc.docPath, link)) {
      [final one] => '$cite; write it as $one',
      final links => '$cite; write each item as its link: ${links.join(', ')}',
    },
    CiteAmbiguous(:final docPaths) =>
      '$cite and names ${countWord(docPaths.length)} docs; write a link to '
          'the one it means, $_linkForm',
    CiteMissingPart(:final docPath) =>
      '$cite, and $docPath lacks ${_partOf(candidate)}; write a link to '
          'the part it means, $_linkForm',
  };
}

/// Names the part [candidate] cites: its section, its items, or both.
String _partOf(CiteCandidate candidate) {
  final key = candidate.sectionKey;
  final ids = candidate.itemIds;
  if (ids.isEmpty) return 'section $key';
  final items = ids.length == 1
      ? 'item ${ids.single}'
      : 'one of items ${ids.join(', ')}';
  return key == null ? items : '$items in section $key';
}

/// Returns the `see` target of each Concerns line of [content], a doc of
/// [type], by file line; none unless [type] is or builds on the architecture
/// type.
///
/// The Concerns section is the held section [type] maps to it, so `check` and
/// the migrate cite pass skip the same targets.
Map<int, String> seeTargetsIn(DocContent content, MergedDocType? type) {
  if (type == null || !type.buildsOn(architectureTypeId)) return const {};
  final index = heldSectionIndex(content, type, concernsSectionId);
  if (index == null) return const {};
  return {
    for (final line in sectionBodyLines(
      content.sections,
      content.lineFacts,
      index,
    ))
      if (!line.fenced)
        if (seeTargetIn(line.text) case final see?) line.line: see.text,
  };
}

/// Whether [see], the `see` target of the candidate's line, is [candidate].
bool isSeeTargetCite(String? see, CiteCandidate candidate) =>
    see != null &&
    (see == candidate.written || see.startsWith('${candidate.written}#'));
