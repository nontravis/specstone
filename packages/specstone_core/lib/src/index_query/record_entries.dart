import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// One entry of a target's `implementation` record: the story or FR it
/// records, named relative to the record's feature (empty for the feature
/// itself), its status, and its code paths.
final class RecordEntry {
  const new({
    required this.item,
    this.status,
    this.reason,
    this.codePaths = const [],
  });

  /// The item's name relative to the record's feature; empty for the feature
  /// itself, which an entry names only to skip it.
  final String item;

  /// The status the item's `statuses` line gives; null with no line or one
  /// that names no RecordStatus.
  final RecordStatus? status;

  /// The one-line reason of a `skipped` entry.
  final String? reason;

  /// The `path[:Symbol]` text of each of the item's `implements` lines, in
  /// file order.
  final List<String> codePaths;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is RecordEntry &&
      other.item == item &&
      other.status == status &&
      other.reason == reason &&
      _samePaths(other);

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(item, status, reason, codePaths.length);

  bool _samePaths(RecordEntry other) {
    if (codePaths.length != other.codePaths.length) return false;
    for (final (i, path) in codePaths.indexed) {
      if (other.codePaths[i] != path) return false;
    }
    return true;
  }

  @override
  String toString() =>
      'RecordEntry(item: $item, status: $status, reason: $reason, '
      'codePaths: $codePaths)';
}

/// Returns the entries of [record], its fields found on [recordType] by type
/// (INV-31): the `record_status` field's lines give each item, its status,
/// and, for `skipped`, its reason; the `item_exact` `output_ref` field's lines
/// give each item's code paths.
///
/// An entry appears for every item either field names, in the `statuses`
/// order; a line that names no item yields none. Invalid YAML frontmatter
/// holds no values, so it holds no entries.
List<RecordEntry> recordEntriesOf(IndexedDoc record, MergedDocType recordType) {
  final statusField = recordType.fields
      .where((f) => f.type == FieldType.recordStatus)
      .firstOrNull;
  final codeField = recordType.fields
      .where(
        (f) =>
            f.type == FieldType.outputRef && f.pointer == PointerKind.itemExact,
      )
      .firstOrNull;
  final byItem = <String, RecordEntry>{};
  RecordEntry baseOf(String item) => byItem[item] ?? RecordEntry(item: item);
  if (statusField != null) {
    for (final line in record.valuesOf(statusField.id)) {
      final split = line.indexOf(':');
      // No `:` names no item; a leading `:` names the feature itself.
      if (split < 0) continue;
      final item = line.substring(0, split);
      final rest = line.substring(split + 1);
      final statusWord = switch (rest.indexOf(':')) {
        -1 => rest,
        final mark => rest.substring(0, mark),
      };
      final status = RecordStatus.byWire(statusWord);
      final reasonMark = rest.indexOf(':');
      final reason = status == RecordStatus.skipped && reasonMark >= 0
          ? rest.substring(reasonMark + 1)
          : null;
      byItem[item] = RecordEntry(
        item: item,
        status: status,
        reason: reason,
        codePaths: byItem[item]?.codePaths ?? const [],
      );
    }
  }
  if (codeField != null) {
    for (final (:item, :code) in recordCodeLinesOf(record, codeField)) {
      final current = baseOf(item);
      byItem[item] = RecordEntry(
        item: item,
        status: current.status,
        reason: current.reason,
        codePaths: [...current.codePaths, code],
      );
    }
  }
  return [for (final entry in byItem.values) entry];
}

/// Returns the `item:path[:Symbol]` lines of [record]'s [codeField] as item
/// and code path, in line order; a line with no item names none.
List<({String item, String code})> recordCodeLinesOf(
  IndexedDoc record,
  MergedField codeField,
) {
  final lines = <({String item, String code})>[];
  for (final line in record.valuesOf(codeField.id)) {
    final split = line.indexOf(':');
    if (split < 1) continue;
    lines.add((
      item: line.substring(0, split),
      code: line.substring(split + 1),
    ));
  }
  return lines;
}
