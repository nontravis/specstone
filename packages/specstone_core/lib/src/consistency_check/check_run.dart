import 'package:specstone_core/src/consistency_check/banned_words.dart';
import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_scope.dart';
import 'package:specstone_core/src/consistency_check/code_rules.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/frontmatter_rules.dart';
import 'package:specstone_core/src/consistency_check/implements_rule.dart';
import 'package:specstone_core/src/consistency_check/journey_rules.dart';
import 'package:specstone_core/src/consistency_check/link_rules.dart';
import 'package:specstone_core/src/consistency_check/pattern_rules.dart';
import 'package:specstone_core/src/consistency_check/reference_rules.dart';
import 'package:specstone_core/src/consistency_check/section_rules.dart';
import 'package:specstone_core/src/consistency_check/trace_rules.dart';
import 'package:specstone_core/src/consistency_check/tracked_links.dart';
import 'package:specstone_core/src/consistency_check/tree_rules.dart';
import 'package:specstone_core/src/index_query/read_session.dart';

/// Runs every rule over the scope of [target], the one doc at [docPath], or
/// the whole project.
///
/// A [docPath] scope holds that doc's own findings and no project-level one.
/// Throws an [ArgumentError] when both [target] and [docPath] are given, an
/// `IndexFault` for a name no doc carries and a `TemplateFault` for an unknown
/// doc type; the last two come from the index lookup.
CheckReport runCheck(ReadSession session, {String? target, String? docPath}) {
  if (target != null && docPath != null) {
    throw ArgumentError('give either a target or a docPath, not both');
  }
  final context = CheckContext(session);
  final index = context.index;
  final scope = switch ((target, docPath)) {
    (final name?, _) => CheckScope.of(context, name),
    (_, final path?) => CheckScope.doc(path),
    _ => CheckScope.project(),
  };
  final findings = <Finding>[];
  for (final doc in index.docs) {
    if (!scope.containsDoc(doc)) continue;
    if (!context.isChecked(doc)) continue;
    findings.addAll(checkTree(context, doc));
    if (!doc.isTyped) {
      findings
        ..addAll(checkDocType(context, doc))
        ..addAll(checkDocLinks(context, doc));
      continue;
    }
    if (!context.hasNoParent(doc)) {
      findings
        ..addAll(checkTraces(context, doc))
        ..addAll(checkRolesAndGoals(context, doc))
        ..addAll(checkSpecAgainstPrd(context, doc))
        ..addAll(checkImplementedStatus(context, doc))
        ..addAll(checkTrackedLinks(context, doc))
        ..addAll(checkConfirmedEntries(context, doc));
    }
    findings
      ..addAll(checkFrontmatter(context, doc))
      ..addAll(checkSections(context, doc))
      ..addAll(checkBannedWords(context, doc))
      ..addAll(checkPatterns(context, doc))
      ..addAll(checkImplements(context, doc))
      ..addAll(checkCoversAndCodeRoots(context, doc))
      ..addAll(checkDocLinks(context, doc))
      ..addAll(checkJourneySteps(context, doc))
      ..addAll(checkReferenceEntries(context, doc));
  }
  if (scope.isProject) {
    findings
      ..addAll(uncoveredCode(context))
      ..addAll(unresolvedTemplateReferences(context));
  }
  findings.addAll(unreadableFindings(context, scope));
  return CheckReport(findings: findings, warnings: context.unstatedWarnings);
}
