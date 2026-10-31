import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/layer_source.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/template_fault.dart';

/// The layers the resolver folded for one doc type, lowest first.
typedef DocTypeLayers = List<({LoadedPack? pack, DocTypeLayer layer})>;

/// One pack with the doc type layers its folder parsed, by doc type id.
typedef ParsedPack = ({LoadedPack pack, Map<String, DocTypeLayer> layers});

/// The load index of every layer file: its place in the load sequence.
///
/// The load sequence runs the packs in `orderPacks` order, each pack's layers
/// in parse order, then the project layers (INV-22). A later layer has the
/// higher index, so layer rank and file order need no second rule.
typedef LoadIndex = Map<String, int>;

/// The [LoadIndex] of the layers in [loadOrder].
LoadIndex loadIndexOf(Iterable<DocTypeLayer> loadOrder) => {
  for (final (index, layer) in loadOrder.indexed) layer.file: index,
};

/// Splits the [files] a fault names into the one `file` and the
/// `relatedFiles` (the fault envelope rule).
///
/// `file` is the file with the highest [index], the upper layer's or the
/// later-loaded one; `relatedFiles` holds the rest, ascending. A null file is
/// dropped and a repeated file counts once. Every file comes from a layer of
/// the load sequence, so [index] holds it.
({String? file, List<String> related}) rankFaultFiles(
  Iterable<String?> files,
  LoadIndex index,
) {
  final ranked = <String>{for (final file in files) ?file}.toList()
    ..sort((a, b) => index[a]!.compareTo(index[b]!));
  if (ranked.isEmpty) return (file: null, related: const []);
  return (file: ranked.last, related: ranked.sublist(0, ranked.length - 1));
}

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
/// through `extends` when no own layer wrote it. A fault that names several
/// files ranks them by [loadIndex]. Runs after every merge
/// (INV-19, INV-21): two doc types may not share one `path`
/// (`doc_type_path_conflict`), a `parent` names a doc type id of the set
/// (`unknown_value`) and its links form no cycle (`parent_cycle`), every
/// `doc_types` entry of a `doc_ref` field names a doc type id of the set
/// (`unknown_value`), and every `lint.required_field_groups` entry names a
/// field of its doc type (`unknown_value`).
void checkMergedSet(
  List<MergedDocType> docTypes,
  Map<String, DocTypeLayers> layerLists, {
  required LoadIndex loadIndex,
}) {
  final byId = {for (final docType in docTypes) docType.id: docType};
  final sorted = [...docTypes]..sort((a, b) => compareCodePoints(a.id, b.id));
  _checkPaths(sorted, layerLists, loadIndex);
  _checkParents(sorted, byId, layerLists, loadIndex);
  _checkFieldTargets(sorted, byId, layerLists);
  _checkFieldGroups(sorted, layerLists);
}

/// Throws `doc_type_path_conflict` for a `path` two doc types share
/// (INV-19).
///
/// `file` holds the `path` writer that loads last by [loadIndex], and
/// `relatedFiles` the other holders' writers, ascending. The message names the
/// holders in that same load order.
void _checkPaths(
  List<MergedDocType> docTypes,
  Map<String, DocTypeLayers> layerLists,
  LoadIndex loadIndex,
) {
  final byPath = <String, List<MergedDocType>>{};
  for (final docType in docTypes) {
    final path = docType.path;
    if (path != null) byPath.putIfAbsent(path, () => []).add(docType);
  }
  for (final MapEntry(key: path, value: holders) in byPath.entries) {
    if (holders.length < 2) continue;
    final writers =
        [
          for (final holder in holders)
            (id: holder.id, file: _writerOf(holder.id, _wrotePath, layerLists)),
        ]..sort(
          (a, b) => _loadRank(a.file, loadIndex) - _loadRank(b.file, loadIndex),
        );
    final (:file, :related) = rankFaultFiles([
      for (final writer in writers) writer.file,
    ], loadIndex);
    throw TemplateFault(
      FaultCode.docTypePathConflict,
      'doc types ${_joinIds([for (final writer in writers) writer.id])} '
      'share the path $path',
      file: file,
      key: 'path',
      relatedFiles: related,
    );
  }
}

bool _wrotePath(DocTypeLayer layer) => layer.path != null;

/// The load position of [file], before every file when null.
int _loadRank(String? file, LoadIndex loadIndex) =>
    file == null ? -1 : loadIndex[file]!;

/// [ids] joined for a sentence: `a`, `a and b`, `a, b and c`.
String _joinIds(List<String> ids) => ids.length < 2
    ? ids.join()
    : '${ids.sublist(0, ids.length - 1).join(', ')} and ${ids.last}';

/// Throws `unknown_value` for a `parent` naming no doc type of the set, then
/// `parent_cycle` for a `parent` chain that returns to its start (INV-21).
void _checkParents(
  List<MergedDocType> docTypes,
  Map<String, MergedDocType> byId,
  Map<String, DocTypeLayers> layerLists,
  LoadIndex loadIndex,
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
        _throwParentCycle(
          walked.sublist(walked.indexOf(target)),
          layerLists,
          loadIndex,
        );
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
/// `file` holds the cycle file that loads last by [loadIndex];
/// `relatedFiles` holds the other cycle files, ascending.
Never _throwParentCycle(
  List<String> cycle,
  Map<String, DocTypeLayers> layerLists,
  LoadIndex loadIndex,
) {
  final (:file, :related) = rankFaultFiles([
    for (final member in cycle) _writerOf(member, _wroteParent, layerLists),
  ], loadIndex);
  throw TemplateFault(
    FaultCode.parentCycle,
    'parent chain returns to its start: ${[...cycle, cycle.first].join(', ')}',
    file: file,
    key: 'parent',
    relatedFiles: related,
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

/// Throws `unknown_value` for a `lint.required_field_groups` id naming no field
/// of its merged doc type.
void _checkFieldGroups(
  List<MergedDocType> docTypes,
  Map<String, DocTypeLayers> layerLists,
) {
  for (final docType in docTypes) {
    final groups = docType.lint.requiredFieldGroups;
    if (groups == null) continue;
    final fieldIds = {for (final field in docType.fields) field.id};
    for (final id in [for (final group in groups) ...group]) {
      if (fieldIds.contains(id)) continue;
      throw TemplateFault(
        FaultCode.unknownValue,
        'a required_field_groups entry names no field of the doc type: $id',
        file: _writerOf(docType.id, _wroteFieldGroups, layerLists),
        key: 'lint.required_field_groups',
      );
    }
  }
}

bool _wroteFieldGroups(DocTypeLayer layer) =>
    layer.lint?.requiredFieldGroups != null;

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
