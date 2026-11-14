import 'package:specstone_core/src/doc_model/body_line.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/rendering/formatter.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

export 'package:specstone_core/src/doc_model/body_line.dart';

/// Returns the template section each of the held [sections] maps to.
///
/// Both headers compare by `headerKey`, as the doc formatter matches them. An
/// entry is null for a header [type] lacks, and every entry is null when
/// [type] is null.
List<MergedSection?> heldTemplatesOf(
  List<IndexedSection> sections,
  MergedDocType? type,
) {
  final byHeader = <String, MergedSection>{};
  for (final section in type?.sections ?? const <MergedSection>[]) {
    byHeader.putIfAbsent(headerKey(section.header), () => section);
  }
  return [
    for (final section in sections) byHeader[headerKey(_headerText(section))],
  ];
}

/// Returns the body lines of the held section at [index] of [sections].
///
/// [facts] are the line facts of the same doc.
List<BodyLine> sectionBodyLines(
  List<IndexedSection> sections,
  LineFacts facts,
  int index,
) {
  final first = facts.sectionLines[index] + 1;
  final body = sections[index].body.split('\n');
  return [
    for (var k = 0; k < body.length; k++)
      (text: body[k], line: first + k, fenced: facts.isFenced(first + k)),
  ];
}

String _headerText(IndexedSection section) =>
    section.headerLine.trimLeft().substring(2).trim();
