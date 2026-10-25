import 'dart:io';
import 'dart:typed_data';

import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/doc_type_merger.dart';
import 'package:specstone_core/src/templates/layer_source.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/merged_set_checks.dart';
import 'package:specstone_core/src/templates/pack_chain.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_fault.dart';

/// Loads the layers of one project and merges them into a [MergedSet].
///
/// The load runs in stages: the config; every listed pack's manifest read and
/// its pin, name, and version checked, packs by name in code point order; the
/// packs ordered by their `extends` chains; each pack's doc-type files parsed
/// in pack load order; the project templates; the merge. The first fault in
/// that order is the one fault raised (one fault per run), so no chain fault
/// or doc-type file fault surfaces before every manifest check passes.
final class TemplateResolver {
  new({Map<String, Uint8List>? shippedFiles})
    : _shippedFiles = shippedFiles ?? shippedPackFiles;

  final Map<String, Uint8List> _shippedFiles;

  /// Resolves the doc types of the project at [workingDirectory].
  ///
  /// [homeDirectory] is the personal pack home, `~`, or null when the
  /// environment names none; a listed personal pack is then `pack_not_found`.
  /// Outside a project every shipped pack loads with no config, no pin check,
  /// no personal pack, and no project layer (INV-9). Throws the first
  /// [TemplateFault] in load order; nothing is cached between calls.
  MergedSet resolve({
    required Directory workingDirectory,
    required Directory? homeDirectory,
  }) {
    final root = findProjectRoot(workingDirectory);
    final packs = root == null
        ? _everyShippedPack()
        : _listedPacks(ProjectConfig.read(root), homeDirectory);
    final ordered = orderPacks(packs, configFile: projectConfigPath);
    final parsed = [
      for (final pack in ordered) (pack: pack, layers: pack.parseDocTypes()),
    ];
    final projectLayers = root == null
        ? <DocTypeLayer>[]
        : loadProjectTemplates(root);
    return _merge(parsed, projectLayers);
  }

  /// Loads every shipped pack's manifest, by name in code point order
  /// (INV-22).
  List<LoadedPack> _everyShippedPack() => [
    for (final name in _shippedPackNames())
      loadShippedPackManifest(name, _shippedFiles),
  ];

  /// Loads the listed packs' manifests, checking every pin (INV-8).
  ///
  /// Packs load by name in code point order (INV-22), whatever the YAML
  /// order of `packs:`. A listed pack ships when its name is a top-level
  /// folder of the shipped files; its pin must equal its carried version
  /// (`pack_pin_older`, `pack_pin_newer`). A pack that does not ship loads
  /// from the home folder (`pack_not_found`, `pack_name_mismatch`,
  /// `personal_pack_version_differs`). Unlisted packs never load (INV-9).
  List<LoadedPack> _listedPacks(ProjectConfig config, Directory? home) {
    final names = config.pins.keys.toList()..sort(compareCodePoints);
    return [
      for (final name in names) _checkedPack(name, config.pins[name]!, home),
    ];
  }

  /// Loads the one listed pack [name] pinned at [pin].
  LoadedPack _checkedPack(String name, PackVersion pin, Directory? home) {
    if (_shippedPackNames().contains(name)) {
      return _checkedShippedPack(name, pin);
    }
    return _checkedPersonalPack(name, pin, home);
  }

  /// The top-level pack folder names of the shipped files, code point order.
  List<String> _shippedPackNames() {
    final names = <String>{
      for (final key in _shippedFiles.keys) key.substring(0, key.indexOf('/')),
    }.toList();
    return names..sort(compareCodePoints);
  }

  /// Loads the shipped pack [name], checking [pin] against its version.
  LoadedPack _checkedShippedPack(String name, PackVersion pin) {
    final pack = loadShippedPackManifest(name, _shippedFiles);
    final carried = pack.manifest.version;
    final compare = pin.compareTo(carried);
    if (compare < 0) {
      throw TemplateFault(
        FaultCode.packPinOlder,
        'Pack $name is pinned at $pin, and this Specstone carries $carried. '
        'Run: specstone migrate --dry-run',
        file: projectConfigPath,
        key: 'packs.$name',
      );
    }
    if (compare > 0) {
      throw TemplateFault(
        FaultCode.packPinNewer,
        'Pack $name is pinned at $pin, and this Specstone carries $carried. '
        'Upgrade Specstone',
        file: projectConfigPath,
        key: 'packs.$name',
      );
    }
    return pack;
  }

  /// Loads the personal pack [name] from [home], checking it against [pin].
  LoadedPack _checkedPersonalPack(
    String name,
    PackVersion pin,
    Directory? home,
  ) {
    if (home == null ||
        !Directory.fromUri(home.uri.resolve('.specstone/packs/$name/'))
            .existsSync()) {
      throw TemplateFault(
        FaultCode.packNotFound,
        'Pack $name is pinned but no shipped pack has that name and '
        '~/.specstone/packs/$name/ does not exist',
        file: projectConfigPath,
        key: 'packs.$name',
      );
    }
    final pack = loadPersonalPackManifest(name, home);
    if (pack.manifest.name != name) {
      throw TemplateFault(
        FaultCode.packNameMismatch,
        'the key name must equal the pack folder name and the packs key',
        file: pack.manifest.file,
        key: 'name',
      );
    }
    final carried = pack.manifest.version;
    if (carried != pin) {
      throw TemplateFault(
        FaultCode.personalPackVersionDiffers,
        'Pack $name is pinned at $pin, and the personal pack carries $carried',
        file: projectConfigPath,
        key: 'packs.$name',
      );
    }
    return pack;
  }

  /// Merges the [packs] and the [projectLayers] into a [MergedSet].
  ///
  /// Each doc type starts from its built-in base and folds the ordered
  /// layers `_docTypeLayers` collects for it, lowest first (pack layers in
  /// load order, then the project layer); the lowest pack naming a doc type
  /// supplies its `pack`. A project template over a pack-defined id is an
  /// override, never a duplicate. The defining layer, the lowest, of a new
  /// doc type needs `id` and `path`, plus `description` without `extends`
  /// (INV-12); with `extends` the doc type starts from the merged target
  /// with every key kept but `id` and `path` (F3-D49), and no layer above
  /// the defining layer may write `extends` (INV-4). The merged set is
  /// checked as one set after every merge. The one [LoadIndex] built here
  /// ranks every file a fault names.
  MergedSet _merge(List<ParsedPack> packs, List<DocTypeLayer> projectLayers) {
    const merger = DocTypeMerger();
    final layerLists = _docTypeLayers(packs, projectLayers);
    final loadOrder = [
      for (final (pack: _, :layers) in packs) ...layers.values,
      ...projectLayers,
    ];
    final loadIndex = loadIndexOf(loadOrder);
    _checkExtendsInOverride(loadOrder, layerLists);
    final docTypes = _resolveInDependencyOrder(layerLists, merger, loadIndex);
    checkMergedSet(docTypes.values.toList(), layerLists, loadIndex: loadIndex);
    return MergedSet(docTypes: docTypes.values.toList());
  }

  /// Throws `extends_in_override` for the first layer of [loadOrder] that is
  /// not its doc type's defining layer and writes `extends` (INV-4).
  ///
  /// The defining layer of a doc type is the lowest in [layerLists].
  void _checkExtendsInOverride(
    List<DocTypeLayer> loadOrder,
    Map<String, DocTypeLayers> layerLists,
  ) {
    for (final layer in loadOrder) {
      final defining = layerLists[layer.docTypeId]!.first.layer;
      if (identical(layer, defining) || !wroteExtends(layer)) continue;
      throw TemplateFault(
        FaultCode.extendsInOverride,
        'Write `extends` only in the file that first defines the doc type',
        file: layer.file,
        key: 'extends',
      );
    }
  }

  /// Merges every doc type, extending ones after their targets (INV-4).
  Map<String, MergedDocType> _resolveInDependencyOrder(
    Map<String, DocTypeLayers> layerLists,
    DocTypeMerger merger,
    LoadIndex loadIndex,
  ) {
    final docTypes = <String, MergedDocType>{};
    for (final id in _dependencyOrder(layerLists, loadIndex)) {
      docTypes[id] = _mergeOne(id, layerLists[id]!, merger, docTypes);
    }
    return docTypes;
  }

  /// The doc type ids ordered so every `extends` target precedes its
  /// extending doc type, or throws `extends_target_unknown` or
  /// `extends_cycle`.
  ///
  /// The defining layer of a doc type names its `extends`; ids without one
  /// merge in code point order (INV-22).
  List<String> _dependencyOrder(
    Map<String, DocTypeLayers> layerLists,
    LoadIndex loadIndex,
  ) {
    String? extendsOf(String id) =>
        topMostWriter(layerLists[id]!, wroteExtends)?.extendsId;

    final order = <String>[];
    final done = <String>{};
    final sorted = layerLists.keys.toList()..sort(compareCodePoints);
    for (final id in sorted) {
      _visit(id, extendsOf, layerLists, loadIndex, done, order);
    }
    return order;
  }

  /// Visits [id] for the dependency order, walking its `extends` chain.
  void _visit(
    String id,
    String? Function(String) extendsOf,
    Map<String, DocTypeLayers> layerLists,
    LoadIndex loadIndex,
    Set<String> done,
    List<String> order,
  ) {
    if (done.contains(id)) return;
    final walked = <String>[];
    var current = id;
    while (true) {
      if (done.contains(current)) break;
      final target = extendsOf(current);
      if (target == null) break;
      walked.add(current);
      if (walked.contains(target)) {
        _throwExtendsCycle(
          walked.sublist(walked.indexOf(target)),
          layerLists,
          loadIndex,
        );
      }
      if (!layerLists.containsKey(target)) {
        _throwExtendsTargetUnknown(current, target, layerLists);
      }
      current = target;
    }
    if (!done.contains(current)) walked.add(current);
    // The chain merges root-first; emit the root and up.
    for (final member in walked.reversed) {
      if (done.add(member)) order.add(member);
    }
  }

  Never _throwExtendsTargetUnknown(
    String id,
    String target,
    Map<String, DocTypeLayers> layerLists,
  ) {
    throw TemplateFault(
      FaultCode.extendsTargetUnknown,
      'the key extends names no loaded doc type: $target',
      file: _extendsWriter(id, layerLists),
      key: 'extends',
    );
  }

  /// Throws the `extends_cycle` fault for [cycle], walked in chain order.
  ///
  /// `file` holds the cycle file that loads last by [loadIndex];
  /// `relatedFiles` holds the other cycle files, ascending.
  Never _throwExtendsCycle(
    List<String> cycle,
    Map<String, DocTypeLayers> layerLists,
    LoadIndex loadIndex,
  ) {
    final walkedPath = [...cycle, cycle.first].join(', ');
    final (:file, :related) = rankFaultFiles([
      for (final member in cycle) _extendsWriter(member, layerLists),
    ], loadIndex);
    throw TemplateFault(
      FaultCode.extendsCycle,
      'extends chain returns to its start: $walkedPath',
      file: file,
      relatedFiles: related,
    );
  }

  /// The file of the layer writing `extends` for the doc type [id].
  String? _extendsWriter(String id, Map<String, DocTypeLayers> layerLists) {
    final layers = layerLists[id];
    if (layers == null) return null;
    return topMostWriter(layers, wroteExtends)?.file;
  }

  /// Merges the layers of one doc type [id] onto its base.
  ///
  /// A doc type whose defining layer writes `extends` starts from the
  /// merged target with every key kept but `id` and `path` (F3-D49); the
  /// base is frozen as merged. The defining layer must carry `id` and
  /// `path`, plus `description` without `extends` (INV-12).
  MergedDocType _mergeOne(
    String id,
    DocTypeLayers layers,
    DocTypeMerger merger,
    Map<String, MergedDocType> merged,
  ) {
    final defining = layers.first.layer;
    final target = defining.extendsId;
    final base = target == null
        ? merger.builtInBase(id)
        : _extendsBase(id, target, merged);
    _checkNewDocTypeKeys(defining, target);
    String? packName;
    var mergedType = base;
    for (final (:layer, :pack) in layers) {
      mergedType = merger.apply(mergedType, layer);
      packName ??= pack?.manifest.name;
    }
    return mergedType.copyWith(pack: packName);
  }

  /// Throws `missing_key` when the defining layer of a new doc type misses
  /// `id`, `path`, or `description` without `extends` (INV-12).
  void _checkNewDocTypeKeys(DocTypeLayer defining, String? target) {
    if (defining.id == null) {
      throw TemplateFault(
        FaultCode.missingKey,
        'the key id is required',
        file: defining.file,
        key: 'id',
      );
    }
    if (defining.path == null) {
      throw TemplateFault(
        FaultCode.missingKey,
        'the key path is required',
        file: defining.file,
        key: 'path',
      );
    }
    if (target == null && defining.description == null) {
      throw TemplateFault(
        FaultCode.missingKey,
        'the key description is required without extends',
        file: defining.file,
        key: 'description',
      );
    }
  }

  /// The base of the doc type [id] extending [targetId]: every key of the
  /// merged target kept but `id` and `path` (F3-D49).
  ///
  /// `pack` and `files` restart with the defining layer; `extendsId` holds
  /// the target. Every list is unmodifiable, so the base is frozen as
  /// merged.
  MergedDocType _extendsBase(
    String id,
    String targetId,
    Map<String, MergedDocType> merged,
  ) {
    final target = merged[targetId]!;
    return MergedDocType(
      id: id,
      description: target.description,
      parent: target.parent,
      extendsId: targetId,
      path: null,
      bundle: target.bundle == null ? null : List.unmodifiable(target.bundle!),
      fields: List.unmodifiable(target.fields),
      sections: List.unmodifiable(target.sections),
      lint: target.lint,
      reference: target.reference == null
          ? null
          : List.unmodifiable(target.reference!),
      files: const [],
    );
  }

  /// The ordered layers each doc type id folds, lowest first (INV-5).
  ///
  /// Pack layers come in `orderPacks` order, then the project layer, whose
  /// `pack` is null. Two packs defining one id where neither reaches the
  /// other are `doc_type_duplicate`: `file` holds the upper or later pack's
  /// file, `relatedFiles` the other's, and the message names the id. A
  /// project template over a pack-defined id is an override, never a
  /// duplicate.
  Map<String, DocTypeLayers> _docTypeLayers(
    List<ParsedPack> packs,
    List<DocTypeLayer> projectLayers,
  ) {
    final lists = <String, DocTypeLayers>{};
    final extendsOf = extendsMapOf([
      for (final (:pack, layers: _) in packs) pack,
    ]);
    for (final (:pack, :layers) in packs) {
      for (final MapEntry(key: id, value: layer) in layers.entries) {
        final list = lists.putIfAbsent(id, () => []);
        // No project layer sits in `list` here: they append after this loop.
        for (final (pack: priorPack!, layer: prior) in list) {
          final upper = reaches(pack, priorPack, extendsOf: extendsOf);
          final lower = reaches(priorPack, pack, extendsOf: extendsOf);
          if (!upper && !lower) {
            throw TemplateFault(
              FaultCode.docTypeDuplicate,
              'two loaded packs define one doc type id: $id',
              file: layer.file,
              relatedFiles: [prior.file],
            );
          }
        }
        list.add((pack: pack, layer: layer));
      }
    }
    for (final layer in projectLayers) {
      lists.putIfAbsent(layer.docTypeId, () => []).add((
        pack: null,
        layer: layer,
      ));
    }
    return lists;
  }
}
