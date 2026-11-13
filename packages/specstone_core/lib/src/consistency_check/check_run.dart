import 'package:specstone_core/src/consistency_check/agent_block_rules.dart';
import 'package:specstone_core/src/consistency_check/approval_rules.dart';
import 'package:specstone_core/src/consistency_check/banned_words.dart';
import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_scope.dart';
import 'package:specstone_core/src/consistency_check/code_rules.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/format_rules.dart';
import 'package:specstone_core/src/consistency_check/frontmatter_rules.dart';
import 'package:specstone_core/src/consistency_check/implements_rule.dart';
import 'package:specstone_core/src/consistency_check/item_id_rules.dart';
import 'package:specstone_core/src/consistency_check/journey_rules.dart';
import 'package:specstone_core/src/consistency_check/label_rules.dart';
import 'package:specstone_core/src/consistency_check/link_rules.dart';
import 'package:specstone_core/src/consistency_check/nesting_rules.dart';
import 'package:specstone_core/src/consistency_check/pattern_rules.dart';
import 'package:specstone_core/src/consistency_check/record_rules.dart';
import 'package:specstone_core/src/consistency_check/reference_rules.dart';
import 'package:specstone_core/src/consistency_check/section_rules.dart';
import 'package:specstone_core/src/consistency_check/tbr_rules.dart';
import 'package:specstone_core/src/consistency_check/trace_rules.dart';
import 'package:specstone_core/src/consistency_check/tracked_links.dart';
import 'package:specstone_core/src/consistency_check/tree_rules.dart';
import 'package:specstone_core/src/index_query/read_session.dart';

/// Runs every rule over the scope of [target], the one doc at [docPath], or
/// the whole project.
///
/// A [docPath] scope holds that doc's own findings and no project-level one.
/// [codeTarget] names the one code target the run keeps; null keeps every
/// target. Throws an [ArgumentError] when both [target] and [docPath] are
/// given, an `IndexFault` for a name no doc carries or a [codeTarget] the
/// project does not name, and a `TemplateFault` for an unknown doc type; the
/// last three come from the index lookup.
CheckReport runCheck(
  ReadSession session, {
  String? target,
  String? docPath,
  String? codeTarget,
}) {
  if (target != null && docPath != null) {
    throw ArgumentError('give either a target or a docPath, not both');
  }
  final context = CheckContext(session);
  final index = context.index;
  final scope = switch ((target, docPath)) {
    (final name?, _) => CheckScope.of(context, name, codeTarget: codeTarget),
    (_, final path?) => CheckScope.doc(context, path, codeTarget: codeTarget),
    _ => CheckScope.project(context, codeTarget: codeTarget),
  };
  final work = ImplementedWork(context, scope.targets);
  final findings = <Finding>[];
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
    if (!context.hasNoParent(doc)) {
      findings
        ..addAll(checkTraces(context, doc))
        ..addAll(checkRolesAndGoals(context, doc))
        ..addAll(checkSpecAgainstPrd(context, doc))
        ..addAll(checkImplementedStatus(context, doc))
        ..addAll(checkRecordEntries(context, doc))
        ..addAll(checkTrackedLinks(context, doc))
        ..addAll(checkConfirmedEntries(context, doc));
    }
    findings
      ..addAll(checkFrontmatter(context, doc))
      ..addAll(staleApproval(context, doc))
      ..addAll(checkNesting(context, doc))
      ..addAll(checkSections(context, doc))
      ..addAll(checkFormatDrift(context, doc))
      ..addAll(checkBannedWords(context, doc))
      ..addAll(checkPatterns(context, doc))
      ..addAll(checkItemIds(context, doc))
      ..addAll(checkImplements(context, doc))
      ..addAll(checkCoversAndCodeRoots(context, work, doc))
      ..addAll(checkDocLinks(context, doc))
      ..addAll(checkJourneySteps(context, doc))
      ..addAll(checkNumberLabels(context, doc))
      ..addAll(checkOpenTbrs(context, doc))
      ..addAll(checkReferenceEntries(context, doc));
  }
  if (scope.isProject) {
    findings
      ..addAll(uncoveredCode(context, work))
      ..addAll(unresolvedTemplateReferences(context))
      ..addAll(staleAgentBlocks(context));
  }
  findings.addAll(unreadableFindings(context, scope));
  return CheckReport(findings: findings, warnings: context.unstatedWarnings);
}
