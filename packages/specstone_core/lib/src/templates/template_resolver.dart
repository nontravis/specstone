import 'dart:io';
import 'dart:typed_data';

import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/doc_type_merger.dart';
import 'package:specstone_core/src/templates/layer_source.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_fault.dart';

/// Loads the layers of one project and merges them into a [MergedSet].
///
/// The load runs in stages: the config; every listed pack's manifest read and
/// its pin, name, and version checked, packs by name in code point order;
/// each pack's doc-type files parsed in pack load order; the project
/// templates; the merge. The first fault in that order is the one fault
/// raised (one fault per run), so no doc-type file parses before every
/// manifest check passes.
final class TemplateResolver {
  new({Map<String, Uint8List>? shippedFiles})
    : _shippedFiles = shippedFiles ?? shippedPackFiles;

  final Map<String, Uint8List> _shippedFiles;

  /// Resolves the doc types of the project at [workingDirectory].
  ///
  /// [homeDirectory] is the personal pack home, `~`. Outside a project every
  /// shipped pack loads with no config, no pin check, no personal pack, and
  /// no project layer (INV-9). Throws the first [TemplateFault] in load
  /// order; nothing is cached between calls.
  MergedSet resolve({
    required Directory workingDirectory,
    required Directory homeDirectory,
  }) {
    final root = findProjectRoot(workingDirectory);
    final packs = root == null
        ? _everyShippedPack()
        : _listedPacks(ProjectConfig.read(root), homeDirectory);
    for (final pack in packs) {
      pack.parseDocTypes();
    }
    final projectLayers = root == null
        ? <DocTypeLayer>[]
        : loadProjectTemplates(root);
    return _merge(packs, projectLayers);
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
  List<LoadedPack> _listedPacks(ProjectConfig config, Directory home) {
    final names = config.pins.keys.toList()..sort(compareCodePoints);
    return [
      for (final name in names) _checkedPack(name, config.pins[name]!, home),
    ];
  }

  /// Loads the one listed pack [name] pinned at [pin].
  LoadedPack _checkedPack(String name, PackVersion pin, Directory home) {
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
    Directory home,
  ) {
    final folder = home.uri.resolve('.specstone/packs/$name/');
    if (!Directory.fromUri(folder).existsSync()) {
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
  /// Each doc type starts from its built-in base and folds its layers lowest
  /// first (shipped packs by name, personal packs, project templates); the
  /// lowest pack naming a doc type supplies its `pack`.
  MergedSet _merge(List<LoadedPack> packs, List<DocTypeLayer> projectLayers) {
    const merger = DocTypeMerger();
    final docTypes = <String, MergedDocType>{};
    final packOf = <String, String>{};
    for (final pack in packs) {
      for (final MapEntry(:key, :value) in pack.docTypes!.entries) {
        final base = docTypes[key] ?? merger.builtInBase(key);
        docTypes[key] = merger
            .apply(base, value)
            .copyWith(pack: packOf[key] ?? pack.manifest.name);
        packOf.putIfAbsent(key, () => pack.manifest.name);
      }
    }
    for (final layer in projectLayers) {
      final id = layer.docTypeId;
      final base = docTypes[id] ?? merger.builtInBase(id);
      docTypes[id] = merger.apply(base, layer);
    }
    return MergedSet(docTypes: docTypes.values.toList());
  }
}
