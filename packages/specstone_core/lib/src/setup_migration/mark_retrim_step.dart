import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart' show withKeyBlock;
import 'package:specstone_core/src/doc_model/list_block_writer.dart';
import 'package:specstone_core/src/rendering/formatter.dart' show headerKey;
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:yaml/yaml.dart';

const _retrimKey = 'retrim';

/// Returns [lf] with each id of [sections] whose section the doc holds with
/// content, that the merged type of [docType] enables, appended once to its
/// `retrim` list, in list order, or [lf] when none joins.
///
/// A section matches by [headerKey]; held entries keep their quotes and form
/// byte for byte, and a `retrim` value that is no list stays as written, so
/// its frontmatter finding names it. Decided on the text the step reads, so a
/// second run changes nothing.
String withRetrimMarked(
  String lf, {
  required MergedDocType docType,
  required List<String> sections,
}) {
  final doc = Doc.parse(lf);
  final block = doc.frontmatter
      ?.where((block) => block.name == _retrimKey)
      .firstOrNull;
  final held = block == null ? const <Object?>[] : _listEntriesOf(block);
  if (held == null) return lf;
  final listed = {
    for (final entry in held)
      if (entry is String) entry,
  };
  final headers = {
    for (final section in doc.sections)
      if (section.body.isNotEmpty) headerKey(section.headerText),
  };
  final enabled = _enabledHeadersOf(docType);
  final joined = [
    ...held,
    for (final id in sections)
      if (enabled[id] case final header?)
        if (!listed.contains(id) && headers.contains(header)) id,
  ];
  if (joined.length == held.length) return lf;
  return withKeyBlock(
    lf,
    _retrimKey,
    listBlockOf(_retrimKey, joined, onDisk: block),
    fieldOrder: [for (final field in docType.fields) field.id],
  );
}

/// The list the `retrim` block holds, or null when its value is no list.
List<Object?>? _listEntriesOf(KeyBlock block) {
  final Object? parsed;
  try {
    parsed = loadYaml(block.text);
  } on YamlException {
    return null;
  }
  final value = parsed is YamlMap ? parsed[block.name] : null;
  return value is YamlList ? [...value] : null;
}

/// The header key of each enabled section id of [docType] the step may mark.
Map<String, String> _enabledHeadersOf(MergedDocType docType) => {
  for (final section in docType.sections)
    if (!docType.disabledSectionIds.contains(section.id))
      section.id: headerKey(section.header),
};
