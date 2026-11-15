import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/doc_model/list_block_writer.dart';
import 'package:yaml/yaml.dart';

const _confirmedKey = 'confirmed';
const _emptyList = ConfirmedList(KeyBlock(_confirmedKey, 'confirmed:\n'), {});

/// The `confirmed` list of a doc that takes more entries as item lines.
final class ConfirmedList {
  const new(this.block, this.labels);

  /// The `confirmed` key block as written, key spelling included;
  /// `confirmed:\n` when the doc holds none.
  final KeyBlock block;

  /// The first word of each entry the list holds.
  final Set<String> labels;
}

/// Reads the `confirmed` list of [doc].
///
/// Null when the list cannot take appended item lines: a flow list, a
/// scalar, or text that is not YAML.
ConfirmedList? readConfirmedList(Doc doc) {
  final block = doc.frontmatter
      ?.where((b) => b.name == _confirmedKey)
      .firstOrNull;
  if (block == null) return _emptyList;
  final value = block.valueText;
  if (value.isNotEmpty && !value.startsWith('-')) return null;
  final Object? items;
  try {
    items = loadYaml(value);
  } on YamlException {
    return null;
  }
  if (items != null && items is! YamlList) return null;
  return ConfirmedList(block, {
    if (items is YamlList)
      for (final item in items)
        if (item is String) item.split(' ').first,
  });
}

/// Returns [lfText] with [entries] added at the end of [list].
///
/// Each entry takes the indent and quotes of the list's first item, as the
/// list writer gives them.
///
/// An absent `confirmed` key lands at its slot in [fieldOrder], as
/// [withKeyBlock] reads it.
String withConfirmedEntries(
  String lfText,
  ConfirmedList list,
  Iterable<String> entries, {
  List<String>? fieldOrder,
}) {
  final held = listEntriesOf(list.block);
  if (held == null) {
    throw StateError('the confirmed block was read as a list of entries');
  }
  return withKeyBlock(
    lfText,
    _confirmedKey,
    listBlockOf(_confirmedKey, [...held, ...entries], onDisk: list.block),
    fieldOrder: fieldOrder,
  );
}
