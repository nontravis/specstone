import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/feature_pattern_rules.dart'
    show isSkipSpan, skipLinesOf;
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/reference_rules.dart'
    show architectureTypeId, concernsSectionId, seeTargetIn;
import 'package:specstone_core/src/consistency_check/scenario_blocks.dart'
    show heldSectionIndex;
import 'package:specstone_core/src/doc_model/records_root.dart'
    show projectPathOfDocPath;
import 'package:specstone_core/src/index_query/cite_resolution.dart';
import 'package:specstone_core/src/index_query/held_sections.dart'
    show sectionBodyLines;
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/models/cite_candidate.dart';
import 'package:specstone_core/src/setup_migration/project_files.dart'
    show isSingularLayoutPath, singularLayoutPathsOf;
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// The link form a message names when the cite picks no one link.
const _linkForm = '[text](<path>)';

/// The tree each check run resolves cites against, built once per run.
final _trees = Expando<IndexCiteTree>();

/// The layout paths of the singular doc types each check run skips, built once
/// per run.
final _layoutPaths = Expando<Set<String>>();

/// Returns a `cite_unlinked` finding for each old cite form in the body of
/// the typed [doc] (consistency_check `report_old_cite_forms`).
///
/// Each stored cite candidate resolves against the index as the check runs,
/// so no doc text is read. One that names no doc is plain text, and a
/// Concerns `see` target or a singular type's layout path is no cite.
Iterable<Finding> checkOldCites(CheckContext context, IndexedDoc doc) sync* {
  final candidates = context.contentOf(doc).lineFacts.citeCandidates;
  if (candidates.isEmpty) return;
  final tree = _trees[context] ??= IndexCiteTree(
    context.index,
    contentOf: context.contentOf,
  );
  final layoutPaths = _layoutPaths[context] ??= singularLayoutPathsOf(
    context.index.set,
    twinNames: context.index.twinNames,
  );
  final seeTargets = seeTargetsIn(context.contentOf(doc), context.typeOf(doc));
  final skips = skipLinesOf(context, doc);
  for (final candidate in candidates) {
    if (isSeeTargetCite(seeTargets[candidate.line], candidate)) continue;
    if (isSkipSpan(skips, candidate.line, candidate.written)) continue;
    if (isSingularLayoutPath(candidate.written, layoutPaths)) continue;
    final report = _reportOf(
      resolveCite(tree, doc.docPath, candidate),
      doc,
      candidate,
    );
    if (report == null) continue;
    yield context.finding(
      doc,
      FindingKind.citeUnlinked,
      line: candidate.line,
      message: report.message,
      keys: {'value': candidate.written, ...report.keys},
    );
  }
}

/// The message of a `cite_unlinked` finding and the keys beyond its value.
final class _CiteReport {
  const new(this.message, [this.keys = const {}]);

  final String message;
  final Map<String, String> keys;
}

/// Returns the report of [resolved], the cite [candidate] of [doc], or null
/// when it names no doc.
_CiteReport? _reportOf(
  CiteResolution resolved,
  IndexedDoc doc,
  CiteCandidate candidate,
) {
  final cite = 'cite ${candidate.written} is no link';
  return switch (resolved) {
    CiteNoDoc() => null,
    final CiteLink link => _linkReport(
      cite,
      link,
      citeLinkMarkdown(doc.docPath, link),
    ),
    CiteAmbiguous(:final docPaths) => _CiteReport(
      '$cite and names ${countWord(docPaths.length)} docs; write a link to '
      'the one it means, $_linkForm',
    ),
    CiteMissingPart(:final docPath) => _missingPartReport(
      cite,
      docPath,
      candidate,
    ),
  };
}

_CiteReport _linkReport(String cite, CiteLink link, List<String> links) {
  final fix = links.join(', ');
  final message = links.length == 1
      ? '$cite; write it as $fix'
      : '$cite; write each item as its link: $fix';
  return _CiteReport(message, {
    'targetPath': projectPathOfDocPath(link.docPath),
    'fix': fix,
  });
}

_CiteReport _missingPartReport(
  String cite,
  String docPath,
  CiteCandidate candidate,
) {
  final path = projectPathOfDocPath(docPath);
  return _CiteReport(
    '$cite, and $path lacks ${_partOf(candidate)}; write a link to '
    'the part it means, $_linkForm',
    {'targetPath': path},
  );
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
/// The Concerns section is the held section [type] maps to it, so `check`
/// skips those targets.
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
