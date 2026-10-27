import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/frontmatter_rules.dart';
import 'package:specstone_core/src/consistency_check/section_rules.dart';
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
    findings
      ..addAll(checkFrontmatter(context, doc))
      ..addAll(checkSections(context, doc));
  }
  return CheckReport(findings: findings, warnings: context.unstatedWarnings);
}
