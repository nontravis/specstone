import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/layer_source.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/template_fault.dart';

/// The layers the resolver folded for one doc type, lowest first.
typedef DocTypeLayers = List<({LoadedPack? pack, DocTypeLayer layer})>;

/// The top-most layer of [layers] for which [wrote] holds, or null.
///
/// The one scan that finds the layer which wrote a key; `extends` writers
/// use it through [wroteExtends].
DocTypeLayer? topMostWriter(
  DocTypeLayers layers,
  bool Function(DocTypeLayer layer) wrote,
) {
  for (var i = layers.length - 1; i >= 0; i--) {
    if (wrote(layers[i].layer)) return layers[i].layer;
  }
  return null;
}

/// Whether [layer] writes `extends`.
bool wroteExtends(DocTypeLayer layer) => layer.extendsId != null;

/// Checks the merged [docTypes] as one set, throwing the first fault.
///
/// [layerLists] holds, per doc type id, the folded layers, lowest first; a
/// fault's `file` names the top-most layer that wrote the key, climbed
/// through `extends` when no own layer wrote it. Runs after every merge
/// (INV-19, INV-21): two doc types may not share one `path`
/// (`doc_type_path_conflict`), a `parent` names a doc type id of the set
/// (`unknown_value`) and its links form no cycle (`parent_cycle`), and every
/// `doc_types` entry of a `doc_ref` field names a doc type id of the set
/// (`unknown_value`).
void checkMergedSet(
  List<MergedDocType> docTypes,
  Map<String, DocTypeLayers> layerLists,
) {
  final byId = {for (final docType in docTypes) docType.id: docType};
  final sorted = [...docTypes]..sort((a, b) => compareCodePoints(a.id, b.id));
  _checkPaths(sorted, layerLists);
  _checkParents(sorted, byId, layerLists);
  _checkFieldTargets(sorted, byId, layerLists);
}

/// Throws `doc_type_path_conflict` for a `path` two doc types share
/// (INV-19).
///
/// Doc types load in id code point order (INV-22), so `file` holds the
/// later doc type's `path` writer and `relatedFiles` the earlier ones'.
void _checkPaths(
  List<MergedDocType> docTypes,
  Map<String, DocTypeLayers> layerLists,
) {
  final byPath = <String, List<MergedDocType>>{};
  for (final docType in docTypes) {
    final path = docType.path;
    if (path != null) byPath.putIfAbsent(path, () => []).add(docType);
  }
  for (final MapEntry(key: path, value: holders) in byPath.entries) {
    if (holders.length < 2) continue;
    final others = holders
        .take(holders.length - 1)
        .map((holder) => _writerOf(holder.id, _wrotePath, layerLists));
    throw TemplateFault(
      FaultCode.docTypePathConflict,
      'two doc types write one path pattern: $path',
      file: _writerOf(holders.last.id, _wrotePath, layerLists),
      key: 'path',
      relatedFiles: [for (final related in others) ?related],
    );
  }
}

bool _wrotePath(DocTypeLayer layer) => layer.path != null;

/// Throws `unknown_value` for a `parent` naming no doc type of the set, then
/// `parent_cycle` for a `parent` chain that returns to its start (INV-21).
void _checkParents(
  List<MergedDocType> docTypes,
  Map<String, MergedDocType> byId,
  Map<String, DocTypeLayers> layerLists,
) {
  for (final docType in docTypes) {
    final parent = docType.parent;
    if (parent == null || byId.containsKey(parent)) continue;
    throw TemplateFault(
      FaultCode.unknownValue,
      'the key parent names no doc type in the merged set: $parent',
      file: _writerOf(docType.id, _wroteParent, layerLists),
      key: 'parent',
    );
  }
  for (final docType in docTypes) {
    final walked = <String>[docType.id];
    var target = docType.parent;
    while (target != null) {
      if (walked.contains(target)) {
        _throwParentCycle(walked.sublist(walked.indexOf(target)), layerLists);
      }
      final next = byId[target];
      if (next == null) break;
      walked.add(target);
      target = next.parent;
    }
  }
}

bool _wroteParent(DocTypeLayer layer) => layer.writesParent;

/// Throws the `parent_cycle` fault for [cycle], walked in chain order.
///
/// `file` holds the later-loaded file of the cycle in id order (INV-22);
/// `relatedFiles` holds the other cycle files in that order.
Never _throwParentCycle(
  List<String> cycle,
  Map<String, DocTypeLayers> layerLists,
) {
  final members = [...cycle]..sort(compareCodePoints);
  final others = members
      .where((member) => member != members.last)
      .map((member) => _writerOf(member, _wroteParent, layerLists));
  throw TemplateFault(
    FaultCode.parentCycle,
    'parent chain returns to its start: ${[...cycle, cycle.first].join(', ')}',
    file: _writerOf(members.last, _wroteParent, layerLists),
    key: 'parent',
    relatedFiles: [for (final related in others) ?related],
  );
}

/// Throws `unknown_value` for a `doc_types` entry naming no doc type of the
/// set (INV-21).
void _checkFieldTargets(
  List<MergedDocType> docTypes,
  Map<String, MergedDocType> byId,
  Map<String, DocTypeLayers> layerLists,
) {
  for (final docType in docTypes) {
    for (final field in docType.fields) {
      final targets = field.docTypes;
      if (targets == null) continue;
      for (final target in targets) {
        if (byId.containsKey(target)) continue;
        throw TemplateFault(
          FaultCode.unknownValue,
          'a doc_types entry names no doc type in the merged set: $target',
          file: _writerOf(docType.id, _wroteField(field.id), layerLists),
          key: 'fields.${field.id}.doc_types',
        );
      }
    }
  }
}

bool Function(DocTypeLayer) _wroteField(String fieldId) =>
    (layer) => layer.fields.any(
      (entry) => entry.id == fieldId && entry.docTypes != null,
    );

/// The file of the top-most layer of [startId] that [wrote] the key, or null
/// when none does.
///
/// When no own layer wrote it, climbs the doc type's `extends` chain and
/// searches each target's layers the same way, top-most first; the walk
/// stops at an id it already visited.
String? _writerOf(
  String startId,
  bool Function(DocTypeLayer layer) wrote,
  Map<String, DocTypeLayers> layerLists,
) {
  var id = startId;
  final visited = <String>{};
  while (visited.add(id)) {
    final layers = layerLists[id];
    if (layers == null) return null;
    final own = topMostWriter(layers, wrote);
    if (own != null) return own.file;
    final target = topMostWriter(layers, wroteExtends)?.extendsId;
    if (target == null) return null;
    id = target;
  }
  return null;
}
