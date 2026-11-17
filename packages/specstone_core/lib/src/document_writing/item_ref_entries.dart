import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart' show withKeyBlock;
import 'package:specstone_core/src/doc_model/list_block_writer.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show linkIdentityOf;
import 'package:specstone_core/src/doc_model/task_ref.dart';
import 'package:specstone_core/src/document_writing/item_moves.dart';
import 'package:specstone_core/src/document_writing/move_item.dart'
    show ItemLanding, overrideCitesOf;
import 'package:specstone_core/src/document_writing/rewrite_labels.dart'
    show MovedFingerprints;
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
/// a moved item: an `overrides` entry that names it, re-stamped from
/// [fingerprints] when it matched, and a task ref that leaves its source doc
/// for the target doc.
///
/// Throws [RenderFault] `output_not_writable` for a task ref field that is
/// not valid YAML.
Map<String, String Function(String lfText)> itemEntryEdits(
  DocIndex index,
  ItemMoves moves, {
  required Map<ItemLanding, MovedFingerprints> fingerprints,
}) {
  final named = <String, Map<String, ItemLanding>>{};
  for (final doc in index.docs) {
    final landings = _namedLandings(index, doc, moves);
    if (landings.isNotEmpty) named[doc.docPath] = landings;
  }
  final tasks = _taskMoves(index, moves);
  return {
    for (final path in {...named.keys, ...tasks.keys})
      path: (lfText) {
        final landings = named[path];
        var text = landings == null
            ? lfText
            : _withEntriesFollowing(lfText, landings, fingerprints);
        if (index.at(path) case final doc?) {
          text = tasks[path]?.applyTo(text, index.typeOf(doc), path) ?? text;
        }
        return text;
      },
  };
}

/// Returns, by the identity of the label an `overrides` entry of [doc] holds,
/// the landing of the moved item it names.
Map<String, ItemLanding> _namedLandings(
  DocIndex index,
  IndexedDoc doc,
  ItemMoves moves,
) => {
  for (final cite in overrideCitesOf(index, doc))
    if (moves.landingOf(cite.upstream.docPath, cite.itemId) case final landing?
        when landing.to.docTypeId != null)
      linkIdentityOf(cite.entryLabel): landing,
};

/// Returns [lfText] with each `overrides` entry naming a landing of [landings]
/// re-stamped when it matched, then set to the label the item lands under.
String _withEntriesFollowing(
  String lfText,
  Map<String, ItemLanding> landings,
  Map<ItemLanding, MovedFingerprints> fingerprints,
) {
  var text = lfText;
  for (final MapEntry(key: identity, value: landing) in landings.entries) {
    text =
        fingerprints[landing]?.restampIn(
          text,
          _overridesKey,
          (label) => linkIdentityOf(label) == identity,
        ) ??
        text;
  }
  final renamed = {
    for (final MapEntry(key: identity, value: landing) in landings.entries)
      identity: '${landing.to.docTypeId}:${landing.to.name}#${landing.newId}',
  };
  return withBlockValues(
    text,
    _overridesKey,
    (value) => _renamedEntry(value, renamed),
  );
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
