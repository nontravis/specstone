import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart' show withKeyBlock;
import 'package:specstone_core/src/doc_model/list_block_writer.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show linkIdentityOf;
import 'package:specstone_core/src/doc_model/task_ref.dart';
import 'package:specstone_core/src/document_writing/item_moves.dart';
import 'package:specstone_core/src/document_writing/move_item.dart'
    show overrideCitesOf;
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/setup_migration/renumber_entries.dart'
    show withBlockValues;
import 'package:specstone_core/src/templates/doc_type_layer.dart'
    show FieldType;
import 'package:specstone_core/src/templates/merged_doc_type.dart';

const _overridesKey = 'overrides';

/// Returns, by DocPath, the edit of each doc's frontmatter entries that follow
/// a moved item: an `overrides` entry that names it, and a task ref that
/// leaves its source doc for the target doc.
///
/// Throws [RenderFault] `output_not_writable` for a task ref field that is
/// not valid YAML.
Map<String, String Function(String lfText)> itemEntryEdits(
  DocIndex index,
  ItemMoves moves,
) {
  final renames = <String, Map<String, String>>{};
  for (final doc in index.docs) {
    final renamed = _renamedEntries(index, doc, moves);
    if (renamed.isNotEmpty) renames[doc.docPath] = renamed;
  }
  final tasks = _taskMoves(index, moves);
  return {
    for (final path in {...renames.keys, ...tasks.keys})
      path: (lfText) {
        final renamed = renames[path];
        var text = renamed == null
            ? lfText
            : withBlockValues(
                lfText,
                _overridesKey,
                (value) => _renamedEntry(value, renamed),
              );
        if (index.at(path) case final doc?) {
          text = tasks[path]?.applyTo(text, index.typeOf(doc), path) ?? text;
        }
        return text;
      },
  };
}

/// Returns, by the identity of the label an `overrides` entry of [doc] holds,
/// the label of the moved item it names after the moves.
Map<String, String> _renamedEntries(
  DocIndex index,
  IndexedDoc doc,
  ItemMoves moves,
) {
  final renamed = <String, String>{};
  for (final cite in overrideCitesOf(index, doc)) {
    final landing = moves.landingOf(cite.upstream.docPath, cite.itemId);
    final typeId = landing?.to.docTypeId;
    if (landing == null || typeId == null) continue;
    renamed[linkIdentityOf(cite.entryLabel)] =
        '$typeId:${landing.to.name}#${landing.newId}';
  }
  return renamed;
}

String? _renamedEntry(String value, Map<String, String> renamed) {
  final space = value.indexOf(' ');
  final label = space < 0 ? value : value.substring(0, space);
  final to = renamed[linkIdentityOf(label)];
  if (to == null || to == label) return null;
  return space < 0 ? to : '$to${value.substring(space)}';
}

/// The task refs of one doc that leave it, and those it gains, by field.
final class _TaskMoves {
  final drops = <String, Set<String>>{};
  final adds = <String, List<String>>{};

  /// Returns [lfText] without the refs that leave and with those that join.
  String applyTo(String lfText, MergedDocType? type, String docPath) {
    var text = lfText;
    for (final field in {...drops.keys, ...adds.keys}) {
      text = _withTaskRefs(
        text,
        type,
        docPath,
        field,
        drops[field] ?? const {},
        adds[field] ?? const [],
      );
    }
    return text;
  }
}

Map<String, _TaskMoves> _taskMoves(DocIndex index, ItemMoves moves) {
  final byDoc = <String, _TaskMoves>{};
  for (final landing in moves.landings) {
    final source = landing.from.doc;
    final fields = [
      for (final field in index.typeOf(source)?.fields ?? const <MergedField>[])
        if (field.type == FieldType.taskRef) field.id,
    ];
    for (final field in fields) {
      if (!_holdsTaskField(index, landing.to, field)) continue;
      for (final entry in source.valuesOf(field)) {
        final ref = TaskRef.parse(entry);
        if (ref == null || ref.item != landing.from.id) continue;
        (byDoc[source.docPath] ??= _TaskMoves()).drops
            .putIfAbsent(field, () => {})
            .add(entry);
        (byDoc[landing.to.docPath] ??= _TaskMoves()).adds
            .putIfAbsent(field, () => [])
            .add('${landing.newId}:${ref.task}');
      }
    }
  }
  return byDoc;
}

bool _holdsTaskField(DocIndex index, IndexedDoc doc, String fieldId) =>
    index
        .typeOf(doc)
        ?.fields
        .any(
          (field) => field.id == fieldId && field.type == FieldType.taskRef,
        ) ??
    false;

String _withTaskRefs(
  String lfText,
  MergedDocType? type,
  String docPath,
  String field,
  Set<String> drop,
  List<String> add,
) {
  final block = (Doc.parse(lfText).frontmatter ?? const <KeyBlock>[])
      .where((candidate) => candidate.name == field)
      .firstOrNull;
  final held = block == null ? const <Object?>[] : listEntriesOf(block);
  if (held == null) {
    throw RenderFault(
      RenderFaultCode.outputNotWritable,
      'cannot write $docPath: its $field is not valid YAML',
    );
  }
  final kept = [
    for (final entry in held)
      if (!(entry is String && drop.contains(entry))) entry,
  ];
  final joined = [
    ...kept,
    for (final entry in add)
      if (!kept.contains(entry)) entry,
  ];
  if (joined.length == held.length && drop.isEmpty) return lfText;
  return withKeyBlock(
    lfText,
    field,
    joined.isEmpty ? null : listBlockOf(field, joined, onDisk: block),
    fieldOrder: [
      for (final field in type?.fields ?? const <MergedField>[]) field.id,
    ],
  );
}
