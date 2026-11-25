import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/rendering/formatter.dart' show headerKey;

/// Returns [lf] with `- ` before each line of the `##` section whose header
/// matches [header] that opens with one of [prefixes], or [lf] without such a
/// section.
///
/// Matches the header as [headerKey] does; a fenced line counts like any other.
String withLinesBulleted(
  String lf, {
  required String header,
  required List<String> prefixes,
}) {
  final doc = Doc.parse(lf);
  final key = headerKey(header);
  final index = doc.sections.indexWhere((s) => headerKey(s.headerText) == key);
  if (index < 0) return lf;
  final lines = doc.afterFrontmatter.split('\n');
  final end = index + 1 < doc.sections.length
      ? doc.sectionLineIndexes[index + 1]
      : lines.length;
  for (var i = doc.sectionLineIndexes[index] + 1; i < end; i++) {
    if (prefixes.any(lines[i].startsWith)) lines[i] = '- ${lines[i]}';
  }
  final frontmatterLength = lf.length - doc.afterFrontmatter.length;
  return lf.substring(0, frontmatterLength) + lines.join('\n');
}
