import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:yaml/yaml.dart';

const _confirmedKey = 'confirmed';

/// The `confirmed` list of a doc that takes more entries as `  - ` lines.
final class ConfirmedList {
  const new(this.text, this.labels);

  /// The `confirmed` key block, every line ending in `\n`; `confirmed:\n` when
  /// the doc holds none.
  final String text;

  /// The first word of each entry the list holds.
  final Set<String> labels;
}

/// Reads the `confirmed` list of [doc].
///
/// Null when the list cannot take appended `  - ` lines: a flow list, a
/// scalar, or text that is not YAML.
ConfirmedList? readConfirmedList(Doc doc) {
  final block = doc.frontmatter
      ?.where((b) => b.name == _confirmedKey)
      .firstOrNull;
  if (block == null) return const ConfirmedList('$_confirmedKey:\n', {});
  final value = block.valueText;
  if (value.isNotEmpty && !value.startsWith('-')) return null;
  final Object? items;
  try {
    items = loadYaml(value);
  } on YamlException {
    return null;
  }
  return ConfirmedList(block.text, {
    if (items is YamlList)
      for (final item in items)
        if (item is String) item.split(' ').first,
  });
}

/// Returns [lfText] with [entries] added at the end of [list].
///
/// An absent `confirmed` key lands at its slot in [fieldOrder], as
/// [withKeyBlock] reads it.
String withConfirmedEntries(
  String lfText,
  ConfirmedList list,
  Iterable<String> entries, {
  List<String>? fieldOrder,
}) => withKeyBlock(
  lfText,
  _confirmedKey,
  '${list.text}${[for (final entry in entries) '  - $entry\n'].join()}',
  fieldOrder: fieldOrder,
);
