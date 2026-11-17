import 'package:specstone_core/src/consistency_check/agent_block_rules.dart';
import 'package:specstone_core/src/consistency_check/approval_rules.dart';
import 'package:specstone_core/src/consistency_check/banned_words.dart';
import 'package:specstone_core/src/consistency_check/bundle_size_rule.dart';
import 'package:specstone_core/src/consistency_check/catalog_rules.dart';
import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_scope.dart';
import 'package:specstone_core/src/consistency_check/cite_rules.dart';
import 'package:specstone_core/src/consistency_check/code_link_rules.dart';
import 'package:specstone_core/src/consistency_check/code_mention_rules.dart';
import 'package:specstone_core/src/consistency_check/code_rules.dart';
import 'package:specstone_core/src/consistency_check/cross_doc_rules.dart';
import 'package:specstone_core/src/consistency_check/diagram_rules.dart';
import 'package:specstone_core/src/consistency_check/feature_pattern_rules.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/format_rules.dart';
import 'package:specstone_core/src/consistency_check/frontmatter_rules.dart';
import 'package:specstone_core/src/consistency_check/goal_measurement_rules.dart';
import 'package:specstone_core/src/consistency_check/implements_rule.dart';
import 'package:specstone_core/src/consistency_check/item_field_rules.dart';
import 'package:specstone_core/src/consistency_check/item_id_rules.dart';
import 'package:specstone_core/src/consistency_check/journey_rules.dart';
import 'package:specstone_core/src/consistency_check/label_rules.dart';
import 'package:specstone_core/src/consistency_check/link_rules.dart';
import 'package:specstone_core/src/consistency_check/matrix_rules.dart';
import 'package:specstone_core/src/consistency_check/mermaid_node_run.dart';
import 'package:specstone_core/src/consistency_check/mermaid_parse_rules.dart';
import 'package:specstone_core/src/consistency_check/nesting_rules.dart';
import 'package:specstone_core/src/consistency_check/override_lines.dart';
import 'package:specstone_core/src/consistency_check/pattern_rules.dart';
import 'package:specstone_core/src/consistency_check/readability_rules.dart';
import 'package:specstone_core/src/consistency_check/record_rules.dart';
import 'package:specstone_core/src/consistency_check/reference_rules.dart';
import 'package:specstone_core/src/consistency_check/repeat_listing.dart';
import 'package:specstone_core/src/consistency_check/section_rules.dart';
import 'package:specstone_core/src/consistency_check/shape_count_rules.dart';
import 'package:specstone_core/src/consistency_check/task_ref_rules.dart';
import 'package:specstone_core/src/consistency_check/tbr_rules.dart';
import 'package:specstone_core/src/consistency_check/test_pointer_rule.dart';
import 'package:specstone_core/src/consistency_check/trace_rules.dart';
import 'package:specstone_core/src/consistency_check/tracked_links.dart';
import 'package:specstone_core/src/consistency_check/tree_rules.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_session.dart';

/// Runs every rule over the scope of [target], the one doc at [docPath], or
/// the whole project.
///
/// A [docPath] scope holds that doc's own findings and no project-level one;
/// on a feature or a story it also holds that feature's `bundle_over_limit`.
/// [codeTarget] names the one code target the run keeps; null keeps every
/// target. Throws an [ArgumentError] when both [target] and [docPath] are
/// given, an `IndexFault` for a name no doc carries or a [codeTarget] the
/// project does not name, and a `TemplateFault` for an unknown doc type; the
/// last three come from the index lookup.
///
/// The Mermaid parse runs last, over the typed docs the run checks;
/// [mermaidRunner] stands in for Node in tests, and null starts `node`.
Future<CheckReport> runCheck(
  ReadSession session, {
  String? target,
  String? docPath,
  String? codeTarget,
  MermaidNodeRun? mermaidRunner,
}) async {
  if (target != null && docPath != null) {
    throw ArgumentError('give either a target or a docPath, not both');
  }
  final context = CheckContext(session);
  final index = context.index;
  final scope = _scopeOf(context, target, docPath, codeTarget);
  final work = ImplementedWork(context, scope.targets);
  final findings = <Finding>[];
  final typedDocs = <IndexedDoc>[];
  for (final doc in index.docs) {
    if (!scope.contains(doc.docPath)) continue;
    if (!context.isChecked(doc)) continue;
    findings
      ..addAll(checkTree(context, doc))
      ..addAll(checkPathLength(context, doc));
    if (!doc.isTyped) {
      if (!context.isUnderOverDeep(doc)) {
        findings
          ..addAll(checkDocType(context, doc))
          ..addAll(checkDocLinks(context, doc));
      }
      continue;
    }
    typedDocs.add(doc);
    if (!context.hasNoParent(doc)) {
      findings
        ..addAll(checkTraces(context, doc))
        ..addAll(checkRolesAndGoals(context, doc))
        ..addAll(checkGoalMeasurements(context, doc))
        ..addAll(checkSpecAgainstPrd(context, work, doc))
        ..addAll(checkImplementedStatus(context, doc))
        ..addAll(checkRecordEntries(context, doc))
        ..addAll(checkTrackedLinks(context, doc))
        ..addAll(checkOverrideLines(context, doc))
        ..addAll(checkConfirmedEntries(context, doc))
        ..addAll(checkCrossDocGuideRules(context, doc));
    }
    findings
      ..addAll(checkFrontmatter(context, doc))
      ..addAll(staleApproval(context, doc))
      ..addAll(checkNesting(context, doc))
      ..addAll(checkSections(context, doc))
      ..addAll(checkShapeCounts(context, doc))
      ..addAll(checkReadability(context, doc))
      ..addAll(checkItemFields(context, doc))
      ..addAll(checkFormatDrift(context, doc))
      ..addAll(checkBannedWords(context, doc))
      ..addAll(checkPatterns(context, doc))
      ..addAll(checkItemIds(context, doc))
      ..addAll(checkImplements(context, doc))
      ..addAll(checkTestPointers(context, doc))
      ..addAll(checkMatrixRows(context, doc))
      ..addAll(checkUnprovenEdgeCases(context, doc))
      ..addAll(checkCoversAndCodeRoots(context, work, doc))
      ..addAll(checkCodeLinks(context, work, doc))
      ..addAll(checkDocLinks(context, doc))
      ..addAll(checkTaskRefs(context, doc))
      ..addAll(checkLeftoverTaskRefs(context, doc))
      ..addAll(checkFeaturePatterns(context, doc))
      ..addAll(checkJourneySteps(context, doc))
      ..addAll(checkNumberLabels(context, doc))
      ..addAll(checkOldCites(context, doc))
      ..addAll(checkOpenTbrs(context, doc))
      ..addAll(checkReferenceEntries(context, doc))
      ..addAll(checkDiagrams(context, doc));
  }
  for (final feature in _featuresReached(context, scope, docPath)) {
    findings.addAll(checkBundleSize(context, feature));
  }
  if (scope.isProject) {
    findings
      ..addAll(uncoveredCode(context, work))
      ..addAll(docNamesInCode(context, work))
      ..addAll(unresolvedTemplateReferences(context))
      ..addAll(staleAgentBlocks(context))
      ..addAll(
        missingSingularDocs(context)
            .where((finding) => scope.contains(finding.path)),
      );
  }
  findings
    ..addAll(
      checkErrorCatalogs(
        context,
        _namesOf(scope),
      ).where((finding) => scope.contains(finding.path)),
    )
    ..addAll(unreadableFindings(context, scope));
  final parse = await checkMermaidParses(
    session,
    context,
    typedDocs,
    runner: mermaidRunner,
  );
  return CheckReport(
    findings: [...findings, ...parse.findings],
    warnings: [...context.unstatedWarnings, ...parse.warnings],
  );
}

/// Returns the checked nesting-type docs [scope] holds, and for a [docPath]
/// scope on a story, that story's feature.
Iterable<IndexedDoc> _featuresReached(
  CheckContext context,
  CheckScope scope,
  String? docPath,
) sync* {
  final index = context.index;
  final nesting = index.set.nestingType;
  if (nesting == null) return;
  for (final doc in index.docs) {
    if (doc.docTypeId != nesting.id || !context.isChecked(doc)) continue;
    final holdsStory =
        docPath != null &&
        index
            .childrenOf(doc)
            .any(
              (child) =>
                  child.docPath == docPath &&
                  child.docTypeId != nesting.id &&
                  index.isChainDoc(child),
            );
    if (holdsStory || scope.contains(doc.docPath)) yield doc;
  }
}

/// Lists the repeat groups of the project, or of [target]'s docs, and no
/// finding.
///
/// [codeTarget] names the one code target the run keeps; null keeps every
/// target. Throws as [runCheck] does for a [target] or [codeTarget] it cannot
/// resolve.
RepeatReport runRepeats(
  ReadSession session, {
  String? target,
  String? codeTarget,
}) => RepeatReport(
  listRepeats(
    session,
    _scopeOf(CheckContext(session), target, null, codeTarget),
  ),
  warnings: session.warnings,
);

CheckScope _scopeOf(
  CheckContext context,
  String? target,
  String? docPath,
  String? codeTarget,
) => switch ((target, docPath)) {
  (final name?, _) => CheckScope.of(context, name, codeTarget: codeTarget),
  (_, final path?) => CheckScope.doc(context, path, codeTarget: codeTarget),
  _ => CheckScope.project(context, codeTarget: codeTarget),
};

/// Returns the names of [scope]'s code targets, the unnamed target as the
/// empty string.
Set<String> _namesOf(CheckScope scope) => {
  for (final target in scope.targets) target.name ?? '',
};
