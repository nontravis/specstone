import 'package:specstone_core/src/consistency_check/banned_words.dart';
import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/code_rules.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/frontmatter_rules.dart';
import 'package:specstone_core/src/consistency_check/implements_rule.dart';
import 'package:specstone_core/src/consistency_check/section_rules.dart';
import 'package:specstone_core/src/consistency_check/tree_rules.dart';
import 'package:specstone_core/src/index_query/read_session.dart';

/// Runs every rule over [target] and the docs under it, or the whole project.
///
/// Throws an `IndexFault` for a name no doc carries and a `TemplateFault` for
/// an unknown doc type; both come from the index lookup.
CheckReport runCheck(ReadSession session, {String? target}) {
  final context = CheckContext(session);
  final index = context.index;
  final inScope = target == null
      ? null
      : {for (final doc in index.under(target)) doc.docPath};
  final findings = <Finding>[];
  for (final doc in index.docs) {
    if (inScope != null && !inScope.contains(doc.docPath)) continue;
    if (!context.isChecked(doc)) continue;
    findings.addAll(checkTree(context, doc));
    if (!doc.isTyped) {
      findings.addAll(checkDocType(context, doc));
      continue;
    }
    findings
      ..addAll(checkFrontmatter(context, doc))
      ..addAll(checkSections(context, doc))
      ..addAll(checkBannedWords(context, doc))
      ..addAll(checkImplements(context, doc))
      ..addAll(checkCoversAndCodeRoots(context, doc));
  }
  if (target == null) findings.addAll(uncoveredCode(context));
  findings.addAll(unreadableFindings(context, inScope));
  return CheckReport(findings: findings, warnings: context.unstatedWarnings);
}
