import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';

/// Returns one `number_label` finding per number label in the body of [doc],
/// a typed doc.
///
/// The body is the text after the frontmatter; prose, code spans, and
/// `mermaid` blocks are read, other fenced code is not (R82). The labels are
/// the ones the index found when it parsed the doc, so no text is read here.
Iterable<Finding> checkNumberLabels(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  for (final (:line, :written) in context.linesOf(doc).numberLabels) {
    yield context.finding(
      doc,
      FindingKind.numberLabel,
      line: line,
      message:
          '$written is a number label; cite the doc by its name, '
          'such as `<feature>/<story>`',
      keys: {'label': written},
    );
  }
}
