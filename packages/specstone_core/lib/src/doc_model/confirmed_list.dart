import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/doc_model/list_block_writer.dart';

const _confirmedKey = 'confirmed';
final _dashItem = RegExp(r'^-(\s|$)');
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
  if (!_isListOrEmpty(block.valueText)) return null;
  final items = listEntriesOf(block);
  if (items == null) return null;
  return ConfirmedList(block, {
    for (final item in items)
      if (item is String) item.split(' ').first,
  });
}

bool _isListOrEmpty(String value) => value.isEmpty || _dashItem.hasMatch(value);

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
