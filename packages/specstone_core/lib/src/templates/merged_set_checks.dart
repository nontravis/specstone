import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/layer_source.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/nested_paths.dart';
import 'package:specstone_core/src/templates/project_config.dart';
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
/// files ranks them by [loadIndex]. [targetNames] holds the config's target
/// names, empty when the config reads no `targets:` key; a named-target
/// config needs the record doc type (INV-29). Runs after every merge
/// (INV-19, INV-21): two doc types may not share one `path`
/// (`doc_type_path_conflict`), a `parent` names a doc type id of the set
/// (`unknown_value`) and its links form no cycle (`parent_cycle`), every
/// `doc_types` entry of a `doc_ref` field names a doc type id of the set
/// (`unknown_value`), every `lint.required_field_groups` entry names a
/// field of its doc type (`unknown_value`), every section `required_when`
/// names a section of its doc type (`unknown_value`), at most one doc type
/// holds a `record_status` field and its merged `per_target` is `true`, and
/// a `targets:` config without the record doc type is refused.
void checkMergedSet(
  List<MergedDocType> docTypes,
  Map<String, DocTypeLayers> layerLists, {
  required LoadIndex loadIndex,
  List<String> targetNames = const [],
}) {
  final byId = {for (final docType in docTypes) docType.id: docType};
  final sorted = [...docTypes]..sort((a, b) => compareCodePoints(a.id, b.id));
  _checkNesting(sorted, layerLists, loadIndex);
  _checkPaths(sorted, layerLists, loadIndex);
  _checkParents(sorted, byId, layerLists, loadIndex);
  _checkFieldTargets(sorted, byId, layerLists);
  _checkFieldGroups(sorted, layerLists);
  _checkRequiredWhen(sorted, layerLists);
  _checkRecords(sorted, layerLists, loadIndex, targetNames);
}

/// Throws `unknown_value` for a `max_depth` that breaks INV-28 (SF-R11).
void _checkNesting(
  List<MergedDocType> docTypes,
  Map<String, DocTypeLayers> layerLists,
  LoadIndex loadIndex,
) {
  final carriers = [
    for (final docType in docTypes)
      if (docType.maxDepth != null) docType,
  ];
  if (carriers.length > 1) {
    _throwSecondCarrier(carriers, layerLists, loadIndex);
  }
  for (final carrier in carriers) {
    final message = _carrierFault(carrier);
    if (message != null) {
      throw _maxDepthFault(message, carrier, layerLists);
    }
  }
}

/// Throws the fault for more than one doc type writing `max_depth`.
///
/// The message names the carriers in the order of [carriers].
Never _throwSecondCarrier(
  List<MergedDocType> carriers,
  Map<String, DocTypeLayers> layerLists,
  LoadIndex loadIndex,
) {
  final (:file, :related) = rankFaultFiles([
    for (final carrier in carriers)
      _writerOf(carrier.id, _wroteMaxDepth, layerLists),
  ], loadIndex);
  throw TemplateFault(
    FaultCode.unknownValue,
    'only one doc type takes max_depth: '
    '${_joinIds([for (final c in carriers) c.id])} write it',
    file: file,
    key: 'max_depth',
    relatedFiles: related,
  );
}

/// The fault message for the lone [carrier], or null when it is valid.
String? _carrierFault(MergedDocType carrier) {
  if (carrier.parent != null) {
    return 'a doc type with a parent takes no max_depth';
  }
  if (carrier.nests && !_lastFolderHoldsSlug(carrier.path)) {
    return 'max_depth needs a path whose last folder holds {slug}';
  }
  return null;
}

TemplateFault _maxDepthFault(
  String message,
  MergedDocType carrier,
  Map<String, DocTypeLayers> layerLists,
) => TemplateFault(
  FaultCode.unknownValue,
  message,
  file: _writerOf(carrier.id, _wroteMaxDepth, layerLists),
  key: 'max_depth',
);

bool _wroteMaxDepth(DocTypeLayer layer) => layer.maxDepth != null;

/// Whether the last folder segment of [path] holds `{slug}`.
bool _lastFolderHoldsSlug(String? path) {
  final segments = path?.split('/') ?? const <String>[];
  return segments.length > 1 &&
      segments[segments.length - 2].contains('{slug}');
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
  for (final docType in withNestedPaths(docTypes)) {
    for (final path in docType.paths) {
      byPath.putIfAbsent(path, () => []).add(docType);
    }
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

/// Throws `unknown_value` for a section `required_when` naming no section of
/// its merged doc type.
void _checkRequiredWhen(
  List<MergedDocType> docTypes,
  Map<String, DocTypeLayers> layerLists,
) {
  for (final docType in docTypes) {
    final ids = {for (final section in docType.sections) section.id};
    for (final section in docType.sections) {
      final rule = section.requiredWhen;
      if (rule == null || ids.contains(rule.section)) continue;
      throw TemplateFault(
        FaultCode.unknownValue,
        'a required_when names no section of the doc type: ${rule.section}',
        file: _writerOf(
          docType.id,
          (layer) => layer.sections.any(
            (entry) =>
                entry.id == section.id && entry.lint?.requiredWhen != null,
          ),
          layerLists,
        ),
        key: 'sections.${section.id}.lint.required_when.section',
      );
    }
  }
}

/// Throws `unknown_value` for the record doc type rules (INV-29, INV-31):
/// a second `record_status` holder, a record doc type whose merged
/// `per_target` is not `true`, and a named-target config with no record doc
/// type.
void _checkRecords(
  List<MergedDocType> docTypes,
  Map<String, DocTypeLayers> layerLists,
  LoadIndex loadIndex,
  List<String> targetNames,
) {
  final holders = [
    for (final docType in docTypes)
      if (docType.fields.any((f) => f.type == FieldType.recordStatus)) docType,
  ];
  if (holders.length > 1) {
    _throwSecondRecordHolder(holders, layerLists, loadIndex);
  }
  for (final holder in holders) {
    if (!holder.isPerTarget) {
      throw TemplateFault(
        FaultCode.unknownValue,
        'the record doc type ${holder.id} must set per_target: true, so no '
        'layer makes one record serve every target',
        file:
            _writerOf(holder.id, _wrotePerTarget, layerLists) ??
            _writerOf(holder.id, _wroteRecordField, layerLists),
        key: 'per_target',
      );
    }
  }
  if (holders.isEmpty && targetNames.isNotEmpty) {
    throw TemplateFault(
      FaultCode.unknownValue,
      'a target owns a spec tree and its records, and this merged set holds '
      'no record doc type, no doc type with a field of type record_status',
      file: projectConfigPath,
      key: 'targets',
    );
  }
}

Never _throwSecondRecordHolder(
  List<MergedDocType> holders,
  Map<String, DocTypeLayers> layerLists,
  LoadIndex loadIndex,
) {
  final (:file, :related) = rankFaultFiles([
    for (final holder in holders)
      _writerOf(holder.id, _wroteRecordField, layerLists),
  ], loadIndex);
  // Every holder's field traces to a parsed layer, `_writerOf` climbing the
  // extends chain, so the writer file is always found.
  final writer = file!;
  throw TemplateFault(
    FaultCode.unknownValue,
    'only one doc type holds a record_status field: '
    '${_joinIds([for (final h in holders) h.id])} do',
    file: writer,
    key: 'fields[${_recordFieldIndex(writer, layerLists)}].type',
    relatedFiles: related,
  );
}

bool _wrotePerTarget(DocTypeLayer layer) => layer.perTarget != null;

bool _wroteRecordField(DocTypeLayer layer) =>
    layer.fields.any((f) => f.type == FieldType.recordStatus);

/// The `fields[<i>]` index of the `record_status` field [file] wrote.
///
/// [file] always holds the writer a holder's field traces to, so the scan
/// always returns.
int _recordFieldIndex(String file, Map<String, DocTypeLayers> layerLists) {
  for (final list in layerLists.values) {
    for (final entry in list) {
      if (entry.layer.file != file) continue;
      final index = entry.layer.fields.indexWhere(
        (f) => f.type == FieldType.recordStatus,
      );
      if (index != -1) return index;
    }
  }
  throw StateError('no layer of $file writes record_status');
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
