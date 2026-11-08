import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/number_label.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';

/// Returns one `number_label` finding per number label in the body of [doc],
/// a typed doc.
///
/// The body is the text after the frontmatter; prose, code spans, and
/// `mermaid` blocks are read, other fenced code is not (R82).
Iterable<Finding> checkNumberLabels(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  final lf = toLf(context.contentOf(doc).text);
  final body = Doc.parse(lf).afterFrontmatter;
  var line = _newlinesBetween(lf, 0, lf.length - body.length) + 1;
  var from = 0;
  for (final label in numberLabelsInMarkdown(body)) {
    line += _newlinesBetween(body, from, label.start);
    from = label.start;
    yield context.finding(
      doc,
      FindingKind.numberLabel,
      line: line,
      message:
          '${label.written} is a number label; cite the doc by its name, '
          'such as `<feature>/<story>`',
      keys: {'label': label.written},
    );
  }
}

/// Returns the number of `\n` in [text] from offset [from] up to [to].
int _newlinesBetween(String text, int from, int to) {
  var count = 0;
  for (var i = from; i < to; i++) {
    if (text.codeUnitAt(i) == 0x0A) count++;
  }
  return count;
}
