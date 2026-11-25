import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/rendering/formatter.dart' show headerKey;
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/models/migration_step.dart';

/// Whether [type] still defines the section [step] drops, by id or by
/// [headerKey], so the step leaves the docs of [type] as they are.
bool keepsDroppedSection(MergedDocType type, DropSection step) {
  final key = headerKey(step.sectionHeader);
  return type.sections.any(
    (section) =>
        section.id == step.sectionId || headerKey(section.header) == key,
  );
}

/// Returns [lf] without each `##` section whose header matches [header], or
/// [lf] when it holds none.
///
/// A section runs to the line before the next `##` header or to the end.
/// Matches the header as [headerKey] does; a removed last section leaves one
/// trailing newline.
String withSectionDropped(String lf, {required String header}) {
  final doc = Doc.parse(lf);
  final lines = doc.afterFrontmatter.split('\n');
  final dropped = _droppedLineIndexes(doc, lines.length, headerKey(header));
  if (dropped.isEmpty) return lf;
  final kept = [
    for (var i = 0; i < lines.length; i++)
      if (!dropped.contains(i)) lines[i],
  ];
  if (dropped.contains(lines.length - 1)) {
    while (kept.isNotEmpty && kept.last.trim().isEmpty) {
      kept.removeLast();
    }
    kept.add('');
  }
  return lf.substring(0, lf.length - doc.afterFrontmatter.length) +
      kept.join('\n');
}

/// Returns the indexes of the lines of [doc]'s sections whose header key is
/// [key], each from its header line to the line before the next section.
Set<int> _droppedLineIndexes(Doc doc, int lineCount, String key) {
  final dropped = <int>{};
  for (final (index, section) in doc.sections.indexed) {
    if (headerKey(section.headerText) != key) continue;
    final end = index + 1 < doc.sections.length
        ? doc.sectionLineIndexes[index + 1]
        : lineCount;
    for (var i = doc.sectionLineIndexes[index]; i < end; i++) {
      dropped.add(i);
    }
  }
  return dropped;
}
