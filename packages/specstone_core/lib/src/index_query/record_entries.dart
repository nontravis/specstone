import 'dart:convert';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:yaml/yaml.dart';

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
  final statusField = recordStatusFieldOf(recordType);
  final codeField = recordCodeFieldOf(recordType);
  final byItem = <String, RecordEntry>{};
  RecordEntry baseOf(String item) => byItem[item] ?? RecordEntry(item: item);
  if (statusField != null) {
    for (final line in record.valuesOf(statusField.id)) {
      // No `:` names no item; a leading `:` names the feature itself.
      final parsed = recordStatusLineOf(line);
      if (parsed == null) continue;
      byItem[parsed.item] = RecordEntry(
        item: parsed.item,
        status: parsed.status,
        reason: parsed.reason,
        codePaths: byItem[parsed.item]?.codePaths ?? const [],
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

/// Returns the item, status, and `skipped` reason of an `item:status[:reason]`
/// line of a `record_status` field; null when the line holds no `:`.
///
/// The status is null when the word after the first `:` names none.
({String item, RecordStatus? status, String? reason})? recordStatusLineOf(
  String line,
) {
  final split = line.indexOf(':');
  if (split < 0) return null;
  final rest = line.substring(split + 1);
  final reasonMark = rest.indexOf(':');
  final status = RecordStatus.byWire(
    reasonMark < 0 ? rest : rest.substring(0, reasonMark),
  );
  return (
    item: line.substring(0, split),
    status: status,
    reason: status == RecordStatus.skipped && reasonMark >= 0
        ? rest.substring(reasonMark + 1)
        : null,
  );
}

/// Returns the item and code path of an `item:path[:Symbol]` line of an
/// `item_exact` field; null when the line holds no `:`.
///
/// The item is empty for a leading `:`, which names the feature itself.
({String item, String code})? recordCodeLineOf(String line) {
  final split = line.indexOf(':');
  if (split < 0) return null;
  return (item: line.substring(0, split), code: line.substring(split + 1));
}

/// Returns the `item:path[:Symbol]` lines of [record]'s [codeField] as item
/// and code path, in line order; a line with no item names none.
List<({String item, String code})> recordCodeLinesOf(
  IndexedDoc record,
  MergedField codeField,
) {
  final lines = <({String item, String code})>[];
  for (final line in record.valuesOf(codeField.id)) {
    final parsed = recordCodeLineOf(line);
    if (parsed == null || parsed.item.isEmpty) continue;
    lines.add(parsed);
  }
  return lines;
}

/// Returns the `record_status` field of [recordType], found by type (INV-31).
MergedField? recordStatusFieldOf(MergedDocType recordType) => recordType.fields
    .where((f) => f.type == FieldType.recordStatus)
    .firstOrNull;

/// Returns the `item_exact` `output_ref` field of [recordType], found by type.
MergedField? recordCodeFieldOf(MergedDocType recordType) => recordType.fields
    .where(
      (f) =>
          f.type == FieldType.outputRef && f.pointer == PointerKind.itemExact,
    )
    .firstOrNull;

/// Returns the stories under [feature] and the FRs of those stories, each by
/// its name relative to [feature]: the items a record of it may name besides
/// the feature itself. [childrenOf] gives the docs under a doc.
Map<String, IndexedDoc> recordItemsOf(
  IndexedDoc feature,
  Iterable<IndexedDoc> Function(IndexedDoc) childrenOf,
) {
  final prefix = '${feature.name}/';
  String relative(IndexedDoc doc) => doc.name.startsWith(prefix)
      ? doc.name.substring(prefix.length)
      : doc.name;
  return {
    for (final story in childrenOf(feature))
      if (story.docTypeId == storyType) ...{
        relative(story): story,
        for (final fr in childrenOf(story))
          if (fr.docTypeId == frType) relative(fr): fr,
      },
  };
}

/// Returns [lfText], the text of a record of [recordType], with the item of
/// each line of its `record_status` and `item_exact` fields set to what
/// [rewrite] returns; null when no line changes.
///
/// [rewrite] takes a line's item, empty for the feature itself, and returns
/// the item to write in its place, the same item to leave the line, or null to
/// drop the line. A line that names no item stays. A field that changes is
/// written back as a block list, one quoted line each, or removed when no line
/// is left; every other key, and a field that does not change, stays as
/// written. It marks no draft.
String? rewriteRecordItems(
  String lfText,
  MergedDocType recordType,
  String? Function(String item) rewrite,
) {
  var text = lfText;
  for (final field in [
    recordStatusFieldOf(recordType),
    recordCodeFieldOf(recordType),
  ]) {
    if (field != null) text = _rewriteField(text, field, rewrite);
  }
  return text == lfText ? null : text;
}

String _rewriteField(
  String lfText,
  MergedField field,
  String? Function(String item) rewrite,
) {
  final block = (Doc.parse(lfText).frontmatter ?? const <KeyBlock>[])
      .where((b) => b.name == field.id)
      .firstOrNull;
  if (block == null) return lfText;
  final Object? parsed;
  try {
    parsed = loadYaml(block.text);
  } on YamlException {
    return lfText;
  }
  final value = parsed is YamlMap ? parsed[field.id] : null;
  final lines = switch (value) {
    null => const <Object?>[],
    YamlList() => [...value],
    _ => [value],
  };
  final itemOf = field.type == FieldType.recordStatus
      ? _statusItemOf
      : _codeItemOf;
  final kept = <Object?>[];
  var changed = false;
  for (final line in lines) {
    final next = line is String ? _rewrittenLine(line, itemOf, rewrite) : line;
    if (next != line) changed = true;
    if (next != null) kept.add(next);
  }
  if (!changed) return lfText;
  final listed = [for (final line in kept) '  - ${_yamlOf(line)}\n'].join();
  return withKeyBlock(
    lfText,
    field.id,
    kept.isEmpty ? null : '${block.key}:\n$listed',
  );
}

/// Returns [line] with the item [itemOf] reads from it set by [rewrite], or
/// null to drop it; [line] itself when it names no item.
String? _rewrittenLine(
  String line,
  String? Function(String line) itemOf,
  String? Function(String item) rewrite,
) {
  final item = itemOf(line);
  if (item == null) return line;
  final next = rewrite(item);
  return next == null ? null : '$next${line.substring(item.length)}';
}

String? _statusItemOf(String line) => recordStatusLineOf(line)?.item;

/// Returns the item of a code line, null for no item, as
/// [recordCodeLinesOf] skips a line whose item is empty.
String? _codeItemOf(String line) {
  final item = recordCodeLineOf(line)?.item;
  return item == null || item.isEmpty ? null : item;
}

/// Returns [value] as one YAML flow or single-quoted scalar, which reads back
/// as it was.
String _yamlOf(Object? value) => value is String && !value.contains('\n')
    ? "'${value.replaceAll("'", "''")}'"
    : jsonEncode(_plain(value));

Object? _plain(Object? yaml) => switch (yaml) {
  YamlMap() => {for (final e in yaml.entries) '${e.key}': _plain(e.value)},
  YamlList() => [for (final e in yaml) _plain(e)],
  _ => yaml,
};
