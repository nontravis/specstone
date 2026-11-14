import 'dart:convert';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/path_tail.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:yaml/yaml.dart';

/// One entry of a target's `implementation` record: the story or FR it
/// records, named relative to the record's feature (empty for the feature
/// itself), its status, its code paths, and its test paths.
final class RecordEntry {
  const new({
    required this.item,
    this.status,
    this.reason,
    this.codePaths = const [],
    this.testPaths = const [],
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

  /// The path part of each of the item's `tests` lines, in file order; a
  /// line's test name stays out, since only `check` reads names.
  final List<String> testPaths;

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
    if (testPaths.length != other.testPaths.length) return false;
    for (final (i, path) in testPaths.indexed) {
      if (other.testPaths[i] != path) return false;
    }
    return true;
  }

  @override
  String toString() =>
      'RecordEntry(item: $item, status: $status, reason: $reason, '
      'codePaths: $codePaths, testPaths: $testPaths)';
}

/// Returns the entries of [record], its fields found on [recordType] by type
/// (INV-31): the `record_status` field's lines give each item, its status,
/// and, for `skipped`, its reason; the `item_exact` `output_ref` field's lines
/// give each item's code paths; the `tests` field's lines give each item's
/// test paths, their path part alone.
///
/// An entry appears for every item either field names, in the `statuses`
/// order; a line that names no item yields none. Invalid YAML frontmatter
/// holds no values, so it holds no entries.
List<RecordEntry> recordEntriesOf(IndexedDoc record, MergedDocType recordType) {
  final statusField = recordStatusFieldOf(recordType);
  final codeField = recordCodeFieldOf(recordType);
  final testField = recordTestFieldOf(recordType);
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
        testPaths: byItem[parsed.item]?.testPaths ?? const [],
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
        testPaths: current.testPaths,
      );
    }
  }
  if (testField != null) {
    for (final (:item, :path) in recordTestLinesOf(record, testField)) {
      final current = baseOf(item);
      byItem[item] = RecordEntry(
        item: item,
        status: current.status,
        reason: current.reason,
        codePaths: current.codePaths,
        testPaths: [...current.testPaths, path],
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

/// Returns the `item_test` `output_ref` field of [recordType], found by
/// pointer kind.
MergedField? recordTestFieldOf(MergedDocType recordType) => recordType.fields
    .where(
      (f) => f.type == FieldType.outputRef && f.pointer == PointerKind.itemTest,
    )
    .firstOrNull;

/// Returns the item and path of an `item:<test path>[:<test name>]` line of a
/// `tests` field; null when the line holds no `:`.
///
/// The path stops at the first `:`, so a test name keeps its colons; the
/// index keeps the path alone, since only `check` reads names.
({String item, String path})? recordTestLineOf(String line) {
  final split = line.indexOf(':');
  if (split < 0) return null;
  return (
    item: line.substring(0, split),
    path: splitPathTail(line.substring(split + 1)).path,
  );
}

/// Returns the `item:<test path>` lines of [record]'s [testField] as item and
/// path, in line order; a line with no item names none.
List<({String item, String path})> recordTestLinesOf(
  IndexedDoc record,
  MergedField testField,
) {
  final lines = <({String item, String path})>[];
  for (final line in record.valuesOf(testField.id)) {
    final parsed = recordTestLineOf(line);
    if (parsed == null || parsed.item.isEmpty) continue;
    lines.add(parsed);
  }
  return lines;
}

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

/// The `record_status`, `item_exact`, and `item_test` lines of a record, each
/// as written in its field.
typedef RecordLines = ({
  List<String> statuses,
  List<String> code,
  List<String> tests,
});

/// Thrown when a record field block a write reads is not valid YAML, so the
/// write cannot tell which lines it holds and refuses rather than drop any.
final class RecordFieldUnreadable implements Exception {
  const new(this.field);

  /// The field's key as the block spells it.
  final String field;

  @override
  String toString() => 'the $field block is not valid YAML';
}

/// Returns [lfText], the text of a record of [recordType], with the item of
/// each line of its `record_status`, `item_exact`, and `item_test` fields set
/// to what [rewrite] returns; null when no line changes.
///
/// [rewrite] takes a line's item, empty for the feature itself, and returns
/// the item to write in its place, the same item to leave the line, or null to
/// drop the line. A line that names no item stays. A field that changes is
/// written back as a block list, one quoted line each, or removed when no line
/// is left; every other key, and a field that does not change, stays as
/// written. It marks no draft. Throws [RecordFieldUnreadable] when a field's
/// block is not valid YAML.
String? rewriteRecordItems(
  String lfText,
  MergedDocType recordType,
  String? Function(String item) rewrite,
) {
  var text = lfText;
  for (final field in _recordFieldsOf(recordType)) {
    text = _rewriteField(text, field, rewrite);
  }
  return text == lfText ? null : text;
}

/// Returns the lines of [lfText]'s `record_status`, `item_exact`, and
/// `item_test` fields whose item [carry] gives a name, each with that name in
/// place of its item and the rest of the line as written.
///
/// [carry] takes a line's item and returns the name to carry it under, or null
/// to leave the line out. A line that names no item is left out. Throws
/// [RecordFieldUnreadable] when a field's block is not valid YAML.
RecordLines recordLinesCarried(
  String lfText,
  MergedDocType recordType,
  String? Function(String item) carry,
) {
  List<String> carried(MergedField? field) {
    if (field == null) return const [];
    final itemOf = _itemReaderOf(field);
    final lines = <String>[];
    for (final line in _fieldLinesOf(lfText, field)?.lines ?? const []) {
      if (line is! String) continue;
      final item = itemOf(line);
      final name = item == null ? null : carry(item);
      if (item != null && name != null) lines.add(_withItem(line, item, name));
    }
    return lines;
  }

  return (
    statuses: carried(recordStatusFieldOf(recordType)),
    code: carried(recordCodeFieldOf(recordType)),
    tests: carried(recordTestFieldOf(recordType)),
  );
}

/// Returns [lfText] with [lines] added at the end of its `record_status`,
/// `item_exact`, and `item_test` fields, a field that holds none yet gaining
/// its key; null when [lines] holds none.
///
/// A field that gains lines is written back as a block list, one quoted line
/// each, as [rewriteRecordItems] writes it. It marks no draft. Throws
/// [RecordFieldUnreadable] when the block of a field that gains lines is not
/// valid YAML, since writing it back would drop the lines it holds.
String? addRecordLines(
  String lfText,
  MergedDocType recordType,
  RecordLines lines,
) {
  var text = lfText;
  for (final (field, added) in [
    (recordStatusFieldOf(recordType), lines.statuses),
    (recordCodeFieldOf(recordType), lines.code),
    (recordTestFieldOf(recordType), lines.tests),
  ]) {
    if (field == null || added.isEmpty) continue;
    final held = _fieldLinesOf(text, field);
    text = _withFieldLines(text, field, held?.key ?? field.id, [
      ...?held?.lines,
      ...added,
    ]);
  }
  return text == lfText ? null : text;
}

List<MergedField> _recordFieldsOf(MergedDocType recordType) => [
  ?recordStatusFieldOf(recordType),
  ?recordCodeFieldOf(recordType),
  ?recordTestFieldOf(recordType),
];

/// Returns the key as spelled in the block of [field] in [lfText] and the
/// lines it lists, one value alone as one line; null when the key is absent.
///
/// Throws [RecordFieldUnreadable] for a block that is no valid YAML.
({String key, List<Object?> lines})? _fieldLinesOf(
  String lfText,
  MergedField field,
) {
  final block = (Doc.parse(lfText).frontmatter ?? const <KeyBlock>[])
      .where((b) => b.name == field.id)
      .firstOrNull;
  if (block == null) return null;
  final Object? parsed;
  try {
    parsed = loadYaml(block.text);
  } on YamlException {
    throw RecordFieldUnreadable(block.key);
  }
  final value = parsed is YamlMap ? parsed[field.id] : null;
  return (
    key: block.key,
    lines: switch (value) {
      null => const <Object?>[],
      YamlList() => [...value],
      _ => [value],
    },
  );
}

/// Returns [lfText] with the block of [field] listing [lines], one quoted
/// line each, under [key]; the block is removed when [lines] is empty.
String _withFieldLines(
  String lfText,
  MergedField field,
  String key,
  List<Object?> lines,
) {
  final listed = [for (final line in lines) '  - ${_yamlOf(line)}\n'].join();
  return withKeyBlock(
    lfText,
    field.id,
    lines.isEmpty ? null : '$key:\n$listed',
  );
}

String _rewriteField(
  String lfText,
  MergedField field,
  String? Function(String item) rewrite,
) {
  final held = _fieldLinesOf(lfText, field);
  if (held == null) return lfText;
  final itemOf = _itemReaderOf(field);
  final kept = <Object?>[];
  var changed = false;
  for (final line in held.lines) {
    final next = line is String ? _rewrittenLine(line, itemOf, rewrite) : line;
    if (next != line) changed = true;
    if (next != null) kept.add(next);
  }
  return changed ? _withFieldLines(lfText, field, held.key, kept) : lfText;
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
  return next == null ? null : _withItem(line, item, next);
}

/// Returns [line] with [name] in place of its leading [item].
String _withItem(String line, String item, String name) =>
    '$name${line.substring(item.length)}';

/// Returns the reader of the item of a line of [field]: null for a line that
/// names none.
String? Function(String line) _itemReaderOf(MergedField field) {
  if (field.type == FieldType.recordStatus) return _statusItemOf;
  return field.pointer == PointerKind.itemTest ? _testItemOf : _codeItemOf;
}

String? _statusItemOf(String line) => recordStatusLineOf(line)?.item;

/// Returns the item of a code line, null for no item, as
/// [recordCodeLinesOf] skips a line whose item is empty.
String? _codeItemOf(String line) {
  final item = recordCodeLineOf(line)?.item;
  return item == null || item.isEmpty ? null : item;
}

/// Returns the item of a test line, null for no item, as
/// [recordTestLinesOf] skips a line whose item is empty.
String? _testItemOf(String line) {
  final item = recordTestLineOf(line)?.item;
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
