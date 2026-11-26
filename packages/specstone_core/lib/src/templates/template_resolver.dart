import 'dart:io';
import 'dart:typed_data';

import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/doc_type_merger.dart';
import 'package:specstone_core/src/templates/feature_pattern.dart';
import 'package:specstone_core/src/templates/feature_pattern_layer.dart';
import 'package:specstone_core/src/templates/generator_kinds.dart';
import 'package:specstone_core/src/templates/layer.dart';
import 'package:specstone_core/src/templates/layer_source.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/merged_set_checks.dart';
import 'package:specstone_core/src/templates/models/matrix_mode.dart';
import 'package:specstone_core/src/templates/models/migration_step.dart';
import 'package:specstone_core/src/templates/models/ranked_fault_files.dart';
import 'package:specstone_core/src/templates/pack_chain.dart';
import 'package:specstone_core/src/templates/pack_floors.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/templates/shared_entry.dart';
import 'package:specstone_core/src/templates/shared_merge.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_fault.dart';

/// Loads the layers of one project and merges them into a [MergedSet].
///
/// The load runs in stages: the config; every listed shipped pin checked
/// against its floor; every listed pack's manifest read and
/// its pin, name, and version checked, packs by name in code point order; the
/// packs ordered by their `extends` chains; each pack's doc-type files, then
/// its feature pattern files, parsed in pack load order; the project
/// templates, then the project shared lines, then the project feature
/// patterns; the merge. The first fault in
/// that order is the one fault raised (one fault per run), so no chain fault
/// or doc-type file fault surfaces before every manifest check passes.
final class TemplateResolver {
  /// Builds a resolver over [shippedFiles], the binary's own when null.
  ///
  /// [floors] defaults to [PackFloors.shipped] over the binary's own files
  /// and to [PackFloors.none] over any other [shippedFiles].
  new({
    Map<String, Uint8List>? shippedFiles,
    Set<String>? generatorKinds,
    PackFloors? floors,
  }) : _shippedFiles = shippedFiles ?? shippedPackFiles,
       _generatorKinds = generatorKinds ?? shippedGeneratorKinds,
       _floors =
           floors ??
           (shippedFiles == null ? PackFloors.shipped : PackFloors.none);

  final Map<String, Uint8List> _shippedFiles;

  final PackFloors _floors;

  /// The generator kinds a layer's `generators` entry may name.
  final Set<String> _generatorKinds;

  /// The generator kinds a layer's `generators` entry may name.
  Set<String> get generatorKinds => Set.unmodifiable(_generatorKinds);

  /// Throws `pack_pin_below_floor` for the first of [pins] under its floor.
  ///
  /// Checks every pin against this resolver's floors, in code point order;
  /// a resolver with no floors never throws.
  void requireAtFloor(Map<String, PackVersion> pins) {
    final belowFloor = _floors.firstBelow(pins);
    if (belowFloor != null) throw belowFloor;
  }

  /// Resolves the doc types of the project at [workingDirectory].
  ///
  /// [homeDirectory] is the personal pack home, `~`, or null when the
  /// environment names none; a listed personal pack is then `pack_not_found`.
  /// Outside a project every shipped pack loads with no config, no pin check,
  /// no personal pack, and no project layer. Throws the first
  /// [TemplateFault] in load order; nothing is cached between calls.
  MergedSet resolve({
    required Directory workingDirectory,
    required Directory? homeDirectory,
  }) {
    final root = findProjectRoot(workingDirectory);
    final config = root == null ? null : ProjectConfig.read(root);
    final packs = root == null
        ? _everyShippedPack()
        : _listedPacks(config!, homeDirectory);
    final ordered = orderPacks(packs, configFile: projectConfigPath);
    final _ParsedPacks(:docTypes, :patterns) = _parsePacks(ordered);
    final folded = _foldedDocTypes(docTypes);
    final projectLayers = root == null
        ? <DocTypeLayer>[]
        : loadProjectTemplates(
            root,
            skippedIds: _leftBehindIds(folded, _droppedDocTypes(docTypes)),
          );
    final projectSharedLines = root == null
        ? <SharedLine>[]
        : loadProjectSharedLines(root);
    final projectPatterns = root == null
        ? <FeaturePatternLayer>[]
        : loadProjectFeaturePatterns(root);
    return _merge(
      docTypes,
      projectLayers,
      folded: folded,
      projectSharedLines: projectSharedLines,
      patterns: patterns,
      projectPatterns: projectPatterns,
      targetNames: config?.targetNames ?? const [],
      matrixMode: config?.matrixMode ?? MatrixMode.off,
    );
  }

  /// Returns the manifest of each pack in [names] at the version this
  /// Specstone or the home folder carries, keyed by name.
  ///
  /// A shipped name reads from the binary, any other name from
  /// `~/.specstone/packs/<name>/pack.yaml` under [homeDirectory]. No pin is
  /// checked; a missing or misnamed personal pack throws `pack_not_found` or
  /// `pack_name_mismatch`.
  Map<String, PackManifest> availableManifests(
    Iterable<String> names, {
    required Directory? homeDirectory,
  }) => {
    for (final pack in _availablePacks(names, homeDirectory))
      pack.manifest.name: pack.manifest,
  };

  /// Whether a shipped pack or a `~/.specstone/packs/<name>/` folder under
  /// [homeDirectory] carries [name].
  ///
  /// Reads no manifest, so a personal pack's faults surface when it loads.
  bool carriesPack(String name, {required Directory? homeDirectory}) =>
      _shippedPackNames().contains(name) ||
      _hasPersonalFolder(name, homeDirectory);

  /// Resolves the doc types of [packNames] at their available versions.
  ///
  /// The packs merge with [projectLayers] and nothing else: no
  /// `.specstone/config.yaml` is read and no pin is checked, so a tree with
  /// no config resolves. [projectSharedLines] are the `shared.yaml` lines
  /// merged on top of the packs'. Throws the first [TemplateFault] in load
  /// order.
  MergedSet resolveCarried({
    required Iterable<String> packNames,
    required Directory? homeDirectory,
    List<DocTypeLayer> projectLayers = const [],
    List<SharedLine> projectSharedLines = const [],
  }) => resolveCarriedPinned(
    packNames: packNames,
    homeDirectory: homeDirectory,
    projectLayers: projectLayers,
    projectSharedLines: projectSharedLines,
  ).set;

  /// Resolves like [resolveCarried] and also returns each loaded pack's
  /// version, keyed by name, from the same load.
  PinnedSet resolveCarriedPinned({
    required Iterable<String> packNames,
    required Directory? homeDirectory,
    List<DocTypeLayer> projectLayers = const [],
    List<SharedLine> projectSharedLines = const [],
  }) {
    final loaded = _availablePacks(packNames, homeDirectory);
    final ordered = orderPacks(loaded, configFile: projectConfigPath);
    final _ParsedPacks(:docTypes, :patterns) = _parsePacks(ordered);
    return PinnedSet(
      set: _merge(
        docTypes,
        projectLayers,
        folded: _foldedDocTypes(docTypes),
        projectSharedLines: projectSharedLines,
        patterns: patterns,
      ),
      pins: {
        for (final pack in loaded) pack.manifest.name: pack.manifest.version,
      },
    );
  }

  /// Returns the frozen doc types of [packNames] at their available versions,
  /// by id.
  ///
  /// A frozen doc type is a pack's `frozen/<id>.yaml` file: a doc type the
  /// pack dropped, as it stood in the last version that shipped it, written
  /// whole with the shared fields that reached it. Only the migration steps
  /// that run on a `merge_doc` step's `from` docs before the fold read it; it
  /// is no doc type of any [MergedSet]. Its `extends` names another frozen
  /// doc type. A higher pack's file of one id wins. Throws the first
  /// [TemplateFault] in load order.
  Map<String, MergedDocType> frozenDocTypes({
    required Iterable<String> packNames,
    required Directory? homeDirectory,
  }) {
    final ordered = orderPacks(
      _availablePacks(packNames, homeDirectory),
      configFile: projectConfigPath,
    );
    final layerLists = <String, DocTypeLayers>{
      for (final pack in ordered)
        for (final MapEntry(key: id, value: layer)
            in pack.parseFrozenDocTypes().entries)
          id: [PackLayer(pack: pack, layer: layer)],
    };
    const merger = DocTypeMerger();
    final loadIndex = loadIndexOf([
      for (final layers in layerLists.values) layers.single.layer,
    ]);
    final merged = <String, MergedDocType>{};
    for (final id in _dependencyOrder(layerLists, loadIndex)) {
      final layer = layerLists[id]!.single.layer;
      final target = layer.extendsId;
      final base = target == null
          ? merger.builtInBase(id)
          : _extendsBase(id, target, merged, layer);
      merged[id] = merger.apply(base, layer);
    }
    return merged;
  }

  /// Parses the doc-type files and then the feature pattern files of each pack
  /// of [ordered], pack by pack, so one pack's pattern fault never precedes
  /// its own doc-type fault.
  _ParsedPacks _parsePacks(List<LoadedPack> ordered) {
    final docTypes = <ParsedPack>[];
    final patterns = <_ParsedPatterns>[];
    for (final pack in ordered) {
      docTypes.add(ParsedPack(pack: pack, layers: pack.parseDocTypes()));
      patterns.add(
        _ParsedPatterns(pack: pack, layers: pack.parseFeaturePatterns()),
      );
    }
    return _ParsedPacks(docTypes: docTypes, patterns: patterns);
  }

  /// Loads the packs [names] at their available versions, by name in code
  /// point order, with no pin check.
  List<LoadedPack> _availablePacks(Iterable<String> names, Directory? home) {
    final shipped = _shippedPackNames();
    final sorted = names.toList()..sort(compareCodePoints);
    return [
      for (final name in sorted)
        if (shipped.contains(name))
          loadShippedPackManifest(name, _shippedFiles)
        else
          _personalPack(name, home),
    ];
  }

  /// Loads every shipped pack's manifest, by name in code point order.
  List<LoadedPack> _everyShippedPack() => [
    for (final name in _shippedPackNames())
      loadShippedPackManifest(name, _shippedFiles),
  ];

  /// Loads the listed packs' manifests, checking every pin.
  ///
  /// Packs load by name in code point order, whatever the YAML
  /// order of `packs:`. A listed shipped pin under its floor is
  /// `pack_pin_below_floor`, checked over every pin before any pack loads. A
  /// listed pack ships when its name is a top-level
  /// folder of the shipped files; its pin must equal its carried version
  /// (`pack_pin_older`, `pack_pin_newer`). A pack that does not ship loads
  /// from the home folder (`pack_not_found`, `pack_name_mismatch`,
  /// `personal_pack_version_differs`). Unlisted packs never load.
  List<LoadedPack> _listedPacks(ProjectConfig config, Directory? home) {
    requireAtFloor(config.pins);
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
    if (compare > 0) throw pinNewerFault(name, pin, carried);
    return pack;
  }

  /// Loads the personal pack [name] from [home], checking it against [pin].
  LoadedPack _checkedPersonalPack(
    String name,
    PackVersion pin,
    Directory? home,
  ) {
    final pack = _personalPack(name, home);
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

  bool _hasPersonalFolder(String name, Directory? home) =>
      home != null &&
      Directory.fromUri(home.uri.resolve('.specstone/packs/$name/'))
          .existsSync();

  /// Loads the personal pack [name] from [home], with no pin check.
  ///
  /// Throws `pack_not_found` when [home] holds no folder for it and
  /// `pack_name_mismatch` when its `pack.yaml` names another pack.
  LoadedPack _personalPack(String name, Directory? home) {
    if (home == null || !_hasPersonalFolder(name, home)) {
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
    return pack;
  }

  /// Maps each `merge_doc` `from` id in the manifests of [packs] to its `to`
  /// id; a later step over one `from` id, in each pack's
  /// `PackManifest.chainOrder`, wins.
  Map<String, String> _foldedDocTypes(List<ParsedPack> packs) => {
    for (final ParsedPack(pack: LoadedPack(:manifest)) in packs)
      for (final index in manifest.chainOrder)
        for (final step in manifest.migrations[index].steps)
          if (step is MergeDoc) step.fromId: step.toId,
  };

  /// Returns the ids of the doc types a project layer file must never load as:
  /// each key of [folded] and each of [dropped]. The file stays on disk.
  Set<String> _leftBehindIds(Map<String, String> folded, Set<String> dropped) =>
      {...folded.keys, ...dropped};

  /// Returns the doc type id of each of [projectLayers] that writes neither
  /// `id` nor `extends` and names a doc type no layer of [packs] defines.
  ///
  /// Such a layer only overrides, so it has no type to override. An override
  /// never writes `extends`, and a new doc type needs `id`.
  Set<String> _orphanedIds(
    List<ParsedPack> packs,
    List<DocTypeLayer> projectLayers,
  ) {
    final packDefined = {
      for (final ParsedPack(:layers) in packs) ...layers.keys,
    };
    return {
      for (final layer in projectLayers)
        if (layer.id == null &&
            layer.extendsId == null &&
            !packDefined.contains(layer.docTypeId))
          layer.docTypeId,
    };
  }

  /// Returns the `id` of each `drop_doc_type` step in the manifests of
  /// [packs].
  Set<String> _droppedDocTypes(List<ParsedPack> packs) => {
    for (final ParsedPack(:pack) in packs)
      for (final migration in pack.manifest.migrations)
        for (final step in migration.steps)
          if (step is DropDocType) step.id,
  };

  /// Merges the [packs] and the [allProjectLayers] into a [MergedSet].
  ///
  /// A project layer whose id is a key of [folded] or the id of a pack's
  /// `drop_doc_type` step, or an orphan `_orphanedIds` names, is dropped
  /// before any check; [folded] becomes `MergedSet.foldedDocTypes`, those ids
  /// `MergedSet.droppedDocTypes`, and the orphans `MergedSet.orphanedDocTypes`.
  ///
  /// Each doc type starts from its built-in base and folds the ordered
  /// layers `_docTypeLayers` collects for it, lowest first (pack layers in
  /// load order, then the project layer); the lowest pack naming a doc type
  /// supplies its `pack`. A project template over a pack-defined id is an
  /// override, never a duplicate. The defining layer, the lowest, of a new
  /// doc type needs `id` and `path`, plus `description` without `extends`;
  /// with `extends` the doc type starts from the merged target
  /// with every key kept but `id` and `path`, and no layer above
  /// the defining layer may write `extends`. The merged set is
  /// checked as one set after every merge, with [targetNames] gating a
  /// `targets:` config on the record doc type and a [matrixMode] other than
  /// off on its enabled matrix section. The one [LoadIndex]
  /// built here ranks every file a fault names. The shared entries of the
  /// packs and [projectSharedLines] merge once, after the `extends` check and
  /// before any doc type. The feature patterns merge
  /// last, from the layers `_featurePatternLayers` collects: pack layers in
  /// load order, then [projectPatterns].
  MergedSet _merge(
    List<ParsedPack> packs,
    List<DocTypeLayer> allProjectLayers, {
    required Map<String, String> folded,
    required List<_ParsedPatterns> patterns,
    List<SharedLine> projectSharedLines = const [],
    List<FeaturePatternLayer> projectPatterns = const [],
    List<String> targetNames = const [],
    MatrixMode matrixMode = MatrixMode.off,
  }) {
    const merger = DocTypeMerger();
    final dropped = _droppedDocTypes(packs);
    final leftBehind = _leftBehindIds(folded, dropped);
    final orphaned = _orphanedIds(packs, allProjectLayers);
    final projectLayers = [
      for (final layer in allProjectLayers)
        if (!leftBehind.contains(layer.docTypeId) &&
            !orphaned.contains(layer.docTypeId))
          layer,
    ];
    final layerLists = _docTypeLayers(packs, projectLayers);
    final patternLayers = _featurePatternLayers(patterns, projectPatterns);
    final loadOrder = [
      for (final ParsedPack(:layers) in packs) ...layers.values,
      ...projectLayers,
    ];
    final loadIndex = loadIndexOf(loadOrder);
    _checkGeneratorKinds(loadOrder);
    _checkRecordTargets(packs);
    _checkBulletLineTargets(packs, layerLists);
    _checkMarkRetrimTargets(packs, layerLists);
    _checkRegenerateKinds(packs);
    _checkDropSectionTargets(packs, layerLists);
    _checkDropDocTypeTargets(packs);
    _checkMergeDocTargets(packs, layerLists);
    final docTypeIds = layerLists.keys.toSet();
    for (final ParsedPack(:pack) in packs) {
      // A shipped pack's entries are held to its own chain by its pack test.
      if (pack.kind != LayerKind.shipped) {
        pack.manifest.checkLeftoverHomes(docTypeIds);
      }
      pack.checkFrozenDocTypes();
    }
    _checkExtendsInOverride(loadOrder, layerLists);
    final shared = mergeSharedEntries(
      ordered: [for (final ParsedPack(:pack) in packs) pack],
      projectLines: projectSharedLines,
      docTypeIdsByPack: {
        for (final ParsedPack(:pack, :layers) in packs)
          pack.manifest.name: layers.keys.toSet(),
      },
      mergedDocTypeIds: layerLists.keys.toSet(),
    );
    final reach = _SharedReach(shared, [
      for (final ParsedPack(:pack) in packs) pack,
    ]);
    final docTypes = _resolveInDependencyOrder(
      layerLists,
      merger,
      loadIndex,
      reach,
    );
    checkMergedSet(
      docTypes.values.toList(),
      layerLists,
      loadIndex: loadIndex,
      targetNames: targetNames,
      matrixMode: matrixMode,
    );
    return MergedSet(
      docTypes: docTypes.values.toList(),
      featurePatterns: mergeFeaturePatterns(
        patternLayers,
        loadIndex: _patternLoadIndex(patterns, projectPatterns),
      ),
      shared: shared,
      foldedDocTypes: folded,
      droppedDocTypes: dropped,
      orphanedDocTypes: orphaned,
      leftoverHomes: [
        for (final ParsedPack(:pack) in packs)
          for (final entry in pack.manifest.leftoverHomes)
            if (pack.kind != LayerKind.shipped ||
                docTypeIds.containsAll([...entry.docTypes, ...entry.to]))
              entry,
      ],
    );
  }

  /// Throws `unknown_value` for the first `merge_doc` step whose `to` names no
  /// doc type its pack, or a pack its chain reaches, defines.
  void _checkRecordTargets(List<ParsedPack> packs) {
    final extendsOf = extendsMapOf([
      for (final ParsedPack(:pack) in packs) pack,
    ]);
    for (final ParsedPack(:pack) in packs) {
      pack.manifest.checkRecordTargets({
        for (final ParsedPack(pack: other, :layers) in packs)
          if (other == pack || reaches(pack, other, extendsOf: extendsOf))
            ...layers.keys,
      });
    }
  }

  /// Throws `unknown_value` for the first `bullet_lines` step whose doc type
  /// or section no layer of [layerLists] defines.
  void _checkBulletLineTargets(
    List<ParsedPack> packs,
    Map<String, DocTypeLayers> layerLists,
  ) {
    for (final ParsedPack(:pack) in packs) {
      pack.manifest.checkBulletLineTargets(layerLists);
    }
  }

  /// Throws `unknown_value` for the first `mark_retrim` doc type or section
  /// no layer of [layerLists] defines.
  void _checkMarkRetrimTargets(
    List<ParsedPack> packs,
    Map<String, DocTypeLayers> layerLists,
  ) {
    for (final ParsedPack(:pack) in packs) {
      pack.manifest.checkMarkRetrimTargets(layerLists);
    }
  }

  /// Throws `unknown_value` for the first `regenerate` generator no kind of
  /// this resolver registers.
  void _checkRegenerateKinds(List<ParsedPack> packs) {
    for (final ParsedPack(:pack) in packs) {
      pack.manifest.checkRegenerateKinds(_generatorKinds);
    }
  }

  /// Throws `unknown_value` for the first `drop_section` doc type no layer of
  /// [layerLists] defines, or section its own pack still defines.
  void _checkDropSectionTargets(
    List<ParsedPack> packs,
    Map<String, DocTypeLayers> layerLists,
  ) {
    for (final ParsedPack(:pack, :layers) in packs) {
      pack.manifest.checkDropSectionTargets(layerLists, ownLayers: layers);
    }
  }

  /// Throws `unknown_value` for the first `drop_doc_type` id its own pack
  /// still defines.
  void _checkDropDocTypeTargets(List<ParsedPack> packs) {
    for (final ParsedPack(:pack, :layers) in packs) {
      pack.manifest.checkDropDocTypeTargets(layers);
    }
  }

  /// Throws `unknown_value` for the first `merge_doc` section whose `to` id no
  /// layer of its `to` doc type in [layerLists] defines.
  void _checkMergeDocTargets(
    List<ParsedPack> packs,
    Map<String, DocTypeLayers> layerLists,
  ) {
    for (final ParsedPack(:pack) in packs) {
      pack.manifest.checkMergeDocTargets(layerLists);
    }
  }

  /// Throws `unknown_value` for the first `generators` entry of [loadOrder]
  /// that names a kind this resolver does not register.
  ///
  /// `remove` entries are not checked here; the merger owns that fault.
  void _checkGeneratorKinds(List<DocTypeLayer> loadOrder) {
    for (final layer in loadOrder) {
      final written = switch (layer.generators) {
        null => const <String>[],
        PlainList<String>(:final items) => items,
        ListChange<String>(:final add) => add,
      };
      final unknown = written.where((kind) => !_generatorKinds.contains(kind));
      if (unknown.isEmpty) continue;
      throw TemplateFault(
        FaultCode.unknownValue,
        'the key generators names no registered kind: ${unknown.first}',
        file: layer.file,
        key: 'generators',
      );
    }
  }

  /// Throws `extends_in_override` for the first layer of [loadOrder] that is
  /// not its doc type's defining layer and writes `extends`.
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

  /// Merges every doc type, extending ones after their targets, once every
  /// shared pattern's `sections` match a section where it lands.
  Map<String, MergedDocType> _resolveInDependencyOrder(
    Map<String, DocTypeLayers> layerLists,
    DocTypeMerger merger,
    LoadIndex loadIndex,
    _SharedReach reach,
  ) {
    final docTypes = <String, MergedDocType>{};
    final order = _dependencyOrder(layerLists, loadIndex);
    reach.checkPatternSections(layerLists);
    for (final id in order) {
      docTypes[id] = _mergeOne(id, layerLists[id]!, merger, docTypes, reach);
    }
    return docTypes;
  }

  /// The doc type ids ordered so every `extends` target precedes its
  /// extending doc type, or throws `extends_target_unknown` or
  /// `extends_cycle`.
  ///
  /// The defining layer of a doc type names its `extends`; ids without one
  /// merge in code point order.
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
    final RankedFaultFiles(:file, :related) = rankFaultFiles([
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
  /// merged target with every key kept but `id` and `path`; the
  /// base is frozen as merged. The defining layer must carry `id` and
  /// `path`, plus `description` without `extends`.
  ///
  /// A doc type with `extends` and no `description` of its own also takes the
  /// shared lines reaching its target.
  MergedDocType _mergeOne(
    String id,
    DocTypeLayers layers,
    DocTypeMerger merger,
    Map<String, MergedDocType> merged,
    _SharedReach reach,
  ) {
    final defining = layers.first.layer;
    final target = defining.extendsId;
    final base = target == null
        ? merger.builtInBase(id)
        : _extendsBase(id, target, merged, defining);
    _checkNewDocTypeKeys(defining);
    final mergedType = _applyLayers(base, id, layers, merger, reach);
    final writesDescription = layers.any((l) => l.layer.description != null);
    return mergedType.copyWith(
      pack: layers.map((l) => l.pack).nonNulls.firstOrNull?.manifest.name,
      sharedLines: reach.linesFor(
        id,
        inheritedFrom: target == null || writesDescription
            ? null
            : merged[target],
      ),
    );
  }

  /// Folds [layers] onto [base], each shared field and shared pattern
  /// reaching the doc type [id] right after the layer of the pack declaring
  /// it.
  ///
  /// A layer's own entry of a shared field's id, at or below that place,
  /// waits and merges over the shared field there; a higher layer's merges
  /// over it in turn. A shared pattern joins as a lower entry of each list it
  /// reaches, which a higher layer's `add:` or `remove:` changes.
  MergedDocType _applyLayers(
    MergedDocType base,
    String id,
    DocTypeLayers layers,
    DocTypeMerger merger,
    _SharedReach reach,
  ) {
    reach.checkOwnPatternEntries(id, layers, extendsChain: base.extendsChain);
    final placed = reach.placeFields(id, layers);
    final placedPatterns = reach.placePatterns(id, layers);
    final heldBy = <String, List<DocTypeLayer>>{};
    var mergedType = base;
    for (final (index, PackLayer(:layer)) in layers.indexed) {
      final held = _fieldIdsPlacedFrom(placed, index);
      mergedType = merger.apply(mergedType, layer, heldFieldIds: held);
      for (final entry in layer.fields.where((e) => held.contains(e.id))) {
        heldBy.putIfAbsent(entry.id, () => []).add(layer);
      }
      for (final field in placed[index] ?? const <MergedSharedField>[]) {
        final fieldId = field.entry.id;
        mergedType = merger.applyFields(mergedType, [
          field.entry,
        ], file: reach.declaringFile(field.declaringPack));
        for (final own in heldBy.remove(fieldId) ?? const <DocTypeLayer>[]) {
          mergedType = merger.applyFields(mergedType, [
            ...own.fields.where((e) => e.id == fieldId),
          ], file: own.file);
        }
      }
      for (final pattern
          in placedPatterns[index] ?? const <MergedSharedPattern>[]) {
        mergedType = merger.applyPatterns(mergedType, [
          pattern,
        ], file: reach.declaringFile(pattern.declaringPack));
      }
    }
    return mergedType;
  }

  /// The ids of the shared fields [placed] at layer [index] or above.
  Set<String> _fieldIdsPlacedFrom(
    Map<int, List<MergedSharedField>> placed,
    int index,
  ) => {
    for (final MapEntry(key: at, value: fields) in placed.entries)
      if (at >= index)
        for (final field in fields) field.entry.id,
  };

  /// Throws `missing_key` when the defining layer of a new doc type misses
  /// `id`, `path` without `path_from`, `file` with `path_from`, or
  /// `description` without `extends`.
  void _checkNewDocTypeKeys(DocTypeLayer defining) {
    final key = defining.missingNewDocTypeKey;
    if (key == null) return;
    throw TemplateFault(
      FaultCode.missingKey,
      key == 'description'
          ? 'the key description is required without extends'
          : 'the key $key is required',
      file: defining.file,
      key: key,
    );
  }

  /// The base of the doc type [id] extending [targetId]: every key of the
  /// merged target kept but `id`, `path`, `path_from`, `file`, and
  /// `max_depth`; an extending type writes its own pattern key.
  ///
  /// `pack` and `files` restart with the defining layer; `extendsId` holds
  /// the target. The base drops `parent` when the [defining] layer clears it,
  /// since a new doc type has no docs the clear could move. Every list is
  /// unmodifiable, so the base is frozen as merged.
  MergedDocType _extendsBase(
    String id,
    String targetId,
    Map<String, MergedDocType> merged,
    DocTypeLayer defining,
  ) {
    final target = merged[targetId]!;
    final clearsParent = defining.writesParent && defining.parent == null;
    return MergedDocType(
      id: id,
      description: target.description,
      parent: clearsParent ? null : target.parent,
      extendsId: targetId,
      extendsChain: List.unmodifiable([targetId, ...target.extendsChain]),
      path: null,
      pathFrom: null,
      file: null,
      maxDepth: null,
      isPerTarget: target.isPerTarget,
      fixedNumbers: target.fixedNumbers,
      bundle: target.bundle == null ? null : List.unmodifiable(target.bundle!),
      bundleRefs: target.bundleRefs,
      summaryFor: target.summaryFor == null
          ? null
          : List.unmodifiable(target.summaryFor!),
      generators: target.generators == null
          ? null
          : List.unmodifiable(target.generators!),
      fields: List.unmodifiable(target.fields),
      sections: List.unmodifiable(target.sections),
      lint: target.lint,
      reference: target.reference == null
          ? null
          : List.unmodifiable(target.reference!),
      files: const [],
      disabledFieldIds: target.disabledFieldIds,
      disabledSectionIds: target.disabledSectionIds,
    );
  }

  /// The ordered layers each doc type id folds, lowest first.
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
      for (final ParsedPack(:pack) in packs) pack,
    ]);
    for (final ParsedPack(:pack, :layers) in packs) {
      for (final MapEntry(key: id, value: layer) in layers.entries) {
        final list = lists.putIfAbsent(id, () => []);
        // No project layer sits in `list` here: they append after this loop.
        for (final PackLayer(pack: priorPack!, layer: prior) in list) {
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
        list.add(PackLayer(pack: pack, layer: layer));
      }
    }
    for (final layer in projectLayers) {
      lists
          .putIfAbsent(layer.docTypeId, () => [])
          .add(PackLayer(pack: null, layer: layer));
    }
    return lists;
  }

  /// The load index of every pattern file: pack layers in load order, then
  /// [projectLayers], the sequence `_featurePatternLayers` walks.
  LoadIndex _patternLoadIndex(
    List<_ParsedPatterns> packs,
    List<FeaturePatternLayer> projectLayers,
  ) {
    final files = [
      for (final _ParsedPatterns(:layers) in packs)
        for (final layer in layers.values) layer.file,
      for (final layer in projectLayers) layer.file,
    ];
    return {for (final (index, file) in files.indexed) file: index};
  }

  /// The ordered layers each feature pattern id folds, lowest first.
  ///
  /// Pack layers come in `orderPacks` order, then the project layer, whose
  /// `pack` is null. Two packs defining one id where neither reaches the
  /// other are `feature_pattern_duplicate`: `file` holds the upper or later
  /// pack's file, `relatedFiles` the other's, and the message names the id.
  /// A project pattern over a pack-defined id is an override, never a
  /// duplicate.
  Map<String, List<WrittenPatternLayer>> _featurePatternLayers(
    List<_ParsedPatterns> packs,
    List<FeaturePatternLayer> projectLayers,
  ) {
    final lists = <String, List<WrittenPatternLayer>>{};
    final byName = {
      for (final _ParsedPatterns(:pack) in packs) pack.manifest.name: pack,
    };
    final extendsOf = extendsMapOf(byName.values);
    for (final _ParsedPatterns(:pack, :layers) in packs) {
      for (final MapEntry(key: id, value: layer) in layers.entries) {
        final list = lists.putIfAbsent(id, () => []);
        // No project layer sits in `list` here: they append after this loop.
        for (final WrittenPatternLayer(pack: priorName!, layer: prior)
            in list) {
          final priorPack = byName[priorName]!;
          final upper = reaches(pack, priorPack, extendsOf: extendsOf);
          final lower = reaches(priorPack, pack, extendsOf: extendsOf);
          if (!upper && !lower) {
            throw TemplateFault(
              FaultCode.featurePatternDuplicate,
              'two loaded packs define one feature pattern id: $id',
              file: layer.file,
              relatedFiles: [prior.file],
            );
          }
        }
        list.add(WrittenPatternLayer(pack: pack.manifest.name, layer: layer));
      }
    }
    for (final layer in projectLayers) {
      lists
          .putIfAbsent(layer.id, () => [])
          .add(WrittenPatternLayer(pack: null, layer: layer));
    }
    return lists;
  }
}

/// A merged set and the version of each pack it loaded, keyed by name.
final class PinnedSet {
  const new({required this.set, required this.pins});

  final MergedSet set;
  final Map<String, PackVersion> pins;
}

/// The doc-type layers and the feature pattern layers of each pack, in pack
/// order.
final class _ParsedPacks {
  const new({required this.docTypes, required this.patterns});

  final List<ParsedPack> docTypes;
  final List<_ParsedPatterns> patterns;
}

/// Decides where the shared entries of one resolve land in each doc type.
final class _SharedReach {
  new(this._shared, List<LoadedPack> packs)
    : _packsByName = {for (final pack in packs) pack.manifest.name: pack},
      _extendsOf = extendsMapOf(packs);

  final SharedSet _shared;
  final Map<String, LoadedPack> _packsByName;
  final Map<String, String?> _extendsOf;

  /// The `pack.yaml` of the pack [declaringPack].
  String declaringFile(String declaringPack) =>
      _packsByName[declaringPack]!.manifest.file;

  /// Groups the shared fields naming [id] by the index of the layer in
  /// [layers] each applies after, in shared order within a group.
  ///
  /// A field applies after the last pack layer written by its declaring pack
  /// or a pack the declaring pack extends: the layer the declaring pack's own
  /// file would sit in. When no such layer exists, as when an extending pack
  /// names its own new doc type in an override, it applies after the last
  /// pack layer.
  Map<int, List<MergedSharedField>> placeFields(
    String id,
    DocTypeLayers layers,
  ) {
    final placed = <int, List<MergedSharedField>>{};
    for (final field in _shared.fieldsNaming(id)) {
      placed
          .putIfAbsent(_placeIndex(field.declaringPack, layers), () => [])
          .add(field);
    }
    return placed;
  }

  /// Groups the shared patterns naming [id] by the index of the layer in
  /// [layers] each applies after, in shared order within a group, as
  /// [placeFields] places a field.
  Map<int, List<MergedSharedPattern>> placePatterns(
    String id,
    DocTypeLayers layers,
  ) {
    final placed = <int, List<MergedSharedPattern>>{};
    for (final pattern in _shared.patternsNaming(id)) {
      placed
          .putIfAbsent(_placeIndex(pattern.declaringPack, layers), () => [])
          .add(pattern);
    }
    return placed;
  }

  /// The index of the last layer of [layers] written by [declaringPack] or a
  /// pack it extends, else of the last pack layer.
  int _placeIndex(String declaringPack, DocTypeLayers layers) {
    final declaring = _packsByName[declaringPack]!;
    final atOrUnder = layers.lastIndexWhere((layer) {
      final pack = layer.pack;
      return pack != null &&
          (pack.manifest.name == declaringPack ||
              reaches(declaring, pack, extendsOf: _extendsOf));
    });
    if (atOrUnder != -1) return atOrUnder;
    return layers.lastIndexWhere((layer) => layer.pack != null);
  }

  /// Throws `unknown_value` at the `sections` of the first shared pattern
  /// whose named sections match no section of a doc type it names, as that
  /// type stands at the layer the pattern joins after.
  ///
  /// An extending doc type takes the pattern only through its base, so the
  /// types the pattern names decide where it lands. Runs before any doc type
  /// merges, once every `extends` target is known.
  void checkPatternSections(Map<String, DocTypeLayers> layerLists) {
    for (final pattern in _shared.patterns) {
      final sections = pattern.sections;
      if (sections == null) continue;
      final lands = pattern.forDocTypes.any((id) {
        final layers = layerLists[id];
        if (layers == null) return false;
        final index = _placeIndex(pattern.declaringPack, layers);
        return _sectionIdsThrough(
          layers,
          index,
          layerLists,
        ).any(sections.contains);
      });
      if (!lands) throw _sectionsMatchNone(pattern, sections);
    }
  }

  /// The section ids a doc type holds after [layers] up to [index], its
  /// `extends` target's merged sections first.
  Set<String> _sectionIdsThrough(
    DocTypeLayers layers,
    int index,
    Map<String, DocTypeLayers> layerLists,
  ) {
    final target = layers.first.layer.extendsId;
    final targetLayers = target == null ? null : layerLists[target];
    final ids = targetLayers == null
        ? <String>{}
        : _sectionIdsThrough(targetLayers, targetLayers.length - 1, layerLists);
    for (final PackLayer(:layer) in layers.take(index + 1)) {
      for (final section in layer.sections) {
        if (section.disabled) {
          ids.remove(section.id);
        } else {
          ids.add(section.id);
        }
      }
    }
    return ids;
  }

  /// The `unknown_value` fault at the `sections` of the `pack.yaml` entry
  /// that last wrote [pattern]'s [sections].
  TemplateFault _sectionsMatchNone(
    MergedSharedPattern pattern,
    List<String> sections,
  ) {
    final writer = [
      for (final pack in _packsByName.values)
        for (final written in pack.manifest.shared.patterns)
          if (written.kind == pattern.kind &&
              written.id == pattern.id &&
              written.sections != null)
            written,
    ].last;
    return TemplateFault(
      FaultCode.unknownValue,
      'sections names no section of a doc type the pattern reaches: '
      '${sections.join(', ')}',
      file: writer.file,
      key: '${pattern.kind.listKey}[${writer.index}].sections',
    );
  }

  /// Throws `unknown_value` at the first entry a layer of [layers] writes in a
  /// list that a shared pattern its own pack declares reaches in [id].
  ///
  /// A pattern reaches [id] when it names [id] or a type of [extendsChain].
  /// One layer defines one entry once.
  void checkOwnPatternEntries(
    String id,
    DocTypeLayers layers, {
    required List<String> extendsChain,
  }) {
    final reaching = {
      for (final type in [id, ...extendsChain]) ..._shared.patternsNaming(type),
    };
    for (final PackLayer(:pack, :layer) in layers) {
      for (final pattern in reaching) {
        if (pack?.manifest.name != pattern.declaringPack) continue;
        final key = _ownEntryKey(layer, pattern);
        if (key == null) continue;
        throw TemplateFault(
          FaultCode.unknownValue,
          'shared pattern ${pattern.id} of this pack already joins this list; '
          'one layer defines one entry once',
          file: layer.file,
          key: key,
        );
      }
    }
  }

  /// The key of [layer]'s own entry of [pattern]'s id in a list [pattern]
  /// reaches, or null when it writes none.
  String? _ownEntryKey(DocTypeLayer layer, MergedSharedPattern pattern) {
    final sections = pattern.sections;
    if (sections == null) {
      return _entryKey(
        layer.lint?.bannedPatterns,
        pattern.id,
        'lint.banned_patterns',
      );
    }
    for (final section in layer.sections) {
      if (section.disabled || !sections.contains(section.id)) continue;
      final lint = section.lint;
      final (write, name) = switch (pattern.kind) {
        SharedPatternKind.banned => (lint?.bannedPatterns, 'banned_patterns'),
        SharedPatternKind.required => (
          lint?.requiredPatterns,
          'required_patterns',
        ),
      };
      final key = _entryKey(
        write,
        pattern.id,
        'sections.${section.id}.lint.$name',
      );
      if (key != null) return key;
    }
    return null;
  }

  /// The key of the `id` of [write]'s entry [id] at the list key [listKey],
  /// or null when [write] holds none.
  String? _entryKey(ListWrite<PatternEntry>? write, String id, String listKey) {
    final (entries, at) = switch (write) {
      null => (const <PatternEntry>[], listKey),
      PlainList<PatternEntry>(:final items) => (items, listKey),
      ListChange<PatternEntry>(:final add) => (add, '$listKey.add'),
    };
    final index = entries.indexWhere((entry) => entry.id == id);
    return index == -1 ? null : '$at[$index].id';
  }

  /// The shared lines that reach [id], in print order, each id once.
  ///
  /// [inheritedFrom] is the merged target of a doc type that takes its
  /// target's lines, null when the doc type takes only the lines naming it or
  /// naming no doc type.
  List<MergedSharedLine> linesFor(
    String id, {
    required MergedDocType? inheritedFrom,
  }) {
    final byId = {
      for (final line in [
        ...?inheritedFrom?.sharedLines,
        ..._shared.linesNaming(id),
      ])
        line.id: line,
    };
    return List.unmodifiable(
      byId.values.toList()..sort((a, b) => a.printRank.compareTo(b.printRank)),
    );
  }
}

/// One pack with the feature pattern layers its folder parsed, by id.
final class _ParsedPatterns {
  const new({required this.pack, required this.layers});

  final LoadedPack pack;
  final Map<String, FeaturePatternLayer> layers;
}

/// Returns the `pack_pin_newer` fault for pack [name] pinned at [pin] while
/// this Specstone carries [carried].
TemplateFault pinNewerFault(
  String name,
  PackVersion pin,
  PackVersion carried,
) => TemplateFault(
  FaultCode.packPinNewer,
  'Pack $name is pinned at $pin, and this Specstone carries $carried. '
  'Upgrade Specstone',
  file: projectConfigPath,
  key: 'packs.$name',
);
