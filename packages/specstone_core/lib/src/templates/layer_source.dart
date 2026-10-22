import 'dart:io';
import 'dart:typed_data';

import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/layer.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/yaml_reader.dart';

/// The `pack.yaml` file name, relative to its pack folder.
const packManifestName = 'pack.yaml';

/// A pack whose manifest is read and checked but whose files are not parsed.
///
/// The parse step runs later, after every listed pack's manifest check, so no
/// doc-type file of any pack parses before every check passes. `docTypes` is
/// null until then.
final class LoadedPack {
  new _({
    required this.manifest,
    required this.kind,
    required this.displayFolder,
    required List<String> paths,
    required LayerFiles files,
    required Uint8List Function(String path) read,
  }) : _paths = paths,
       _files = files,
       _read = read;

  /// The pack's `pack.yaml`.
  final PackManifest manifest;

  /// Whether the pack is shipped or personal.
  final LayerKind kind;

  /// The pack's doc-type layers, keyed by doc type id; null until parsed.
  Map<String, DocTypeLayer>? docTypes;

  /// The pack's folder as faults print it.
  final String displayFolder;

  /// The pack's layer-relative file paths.
  final List<String> _paths;

  /// The layer's file-existence view.
  final LayerFiles _files;

  /// The layer's byte reader.
  final Uint8List Function(String path) _read;

  /// Parses the pack's doc-type files, in code point order (INV-22).
  ///
  /// Every YAML file is read as bytes through `decodeYamlBytes` (F3-D50).
  /// Throws a [TemplateFault] for any format fault.
  void parseDocTypes() {
    docTypes = {
      for (final path in _docTypeNames(_paths))
        path.substring(0, path.length - '.yaml'.length): DocTypeLayer.parse(
          decodeYamlBytes(_read(path), file: '$displayFolder/$path'),
          file: '$displayFolder/$path',
          docTypeId: path.substring(0, path.length - '.yaml'.length),
          kind: kind,
          files: _files,
        ),
    };
  }
}

/// A [LayerFiles] view over an in-memory file map.
final class _MapFiles implements LayerFiles {
  const new(this.paths);

  /// The file paths the layer holds, layer-relative.
  final Set<String> paths;

  @override
  bool exists(String layerRelativePath) => paths.contains(layerRelativePath);
}

/// A [LayerFiles] view over one disk folder.
final class _DiskFiles implements LayerFiles {
  const new(this.folder);

  /// The folder paths are relative to.
  final Directory folder;

  @override
  bool exists(String layerRelativePath) =>
      File.fromUri(folder.uri.resolve(layerRelativePath)).existsSync();
}

/// Reads the manifest of the shipped pack [name] from its embedded [files]
/// (F3-D18).
///
/// [files] keys are `<pack>/<path>`; the pack holds the `<pack>/<path>` keys.
/// Call [LoadedPack.parseDocTypes] later to parse its doc-type files.
LoadedPack loadShippedPackManifest(String name, Map<String, Uint8List> files) {
  final displayFolder = 'packs/$name';
  final packFiles = <String, Uint8List>{
    for (final MapEntry(:key, :value) in files.entries)
      if (key.startsWith('$name/')) key.substring(name.length + 1): value,
  };
  return LoadedPack._(
    manifest: _packManifest(displayFolder, packFiles[packManifestName]),
    kind: LayerKind.shipped,
    displayFolder: displayFolder,
    paths: packFiles.keys.toList(),
    files: _MapFiles(packFiles.keys.toSet()),
    read: (path) => packFiles[path]!,
  );
}

/// Reads the manifest of the personal pack [name] under [home] (US-04 FR-01).
///
/// The pack folder is `~/.specstone/packs/<name>`; faults print it as that
/// path with `/` separators. Call [LoadedPack.parseDocTypes] later to parse
/// its doc-type files.
LoadedPack loadPersonalPackManifest(String name, Directory home) {
  final displayFolder = '~/.specstone/packs/$name';
  final folder = Directory.fromUri(home.uri.resolve('.specstone/packs/$name/'));
  return LoadedPack._(
    manifest: _packManifest(displayFolder, _manifestBytes(folder)),
    kind: LayerKind.personal,
    displayFolder: displayFolder,
    paths: _topLevelPaths(folder).toList(),
    files: _DiskFiles(folder),
    read: (path) => File.fromUri(folder.uri.resolve(path)).readAsBytesSync(),
  );
}

/// Loads the project templates under [root], in code point order (INV-22).
///
/// The template folder is `.specstone/templates`; faults print files relative
/// to the project root with `/` separators. Only `<id>.yaml` files at the
/// folder top level are doc types; other files are reference targets (Review
/// Focus 1). Throws a [TemplateFault] for any format fault.
List<DocTypeLayer> loadProjectTemplates(Directory root) {
  const displayFolder = '.specstone/templates';
  final folder = Directory.fromUri(root.uri.resolve(displayFolder));
  if (!folder.existsSync()) return <DocTypeLayer>[];
  return [
    for (final path in _docTypeNames(_topLevelPaths(folder)))
      DocTypeLayer.parse(
        decodeYamlBytes(
          File.fromUri(folder.uri.resolve(path)).readAsBytesSync(),
          file: '$displayFolder/$path',
        ),
        file: '$displayFolder/$path',
        docTypeId: path.substring(0, path.length - '.yaml'.length),
        kind: LayerKind.project,
        files: _DiskFiles(folder),
      ),
  ];
}

/// Parses the pack manifest from its [bytes], null when the file is absent.
///
/// [displayFolder] is the pack folder as faults print it. An absent
/// `pack.yaml` is `missing_key` at the manifest's `name` key, since the fault
/// catalog carries no absent-manifest code and US-04 FR-01 E04 routes an
/// unusable manifest there.
PackManifest _packManifest(String displayFolder, Uint8List? bytes) {
  final file = '$displayFolder/$packManifestName';
  if (bytes == null) {
    throw TemplateFault(
      FaultCode.missingKey,
      'the file does not exist and must hold the keys name and version',
      file: file,
      key: 'name',
    );
  }
  return PackManifest.parse(decodeYamlBytes(bytes, file: file), file: file);
}

/// Returns the manifest bytes of the pack [folder], null when absent.
Uint8List? _manifestBytes(Directory folder) {
  final manifest = File.fromUri(folder.uri.resolve(packManifestName));
  if (!manifest.existsSync()) return null;
  return manifest.readAsBytesSync();
}

/// Returns the doc-type names of [paths] in code point order (INV-22).
List<String> _docTypeNames(Iterable<String> paths) {
  final names = [
    for (final path in paths)
      if (isDocTypeFileName(path)) path,
  ]..sort(compareCodePoints);
  return names;
}

/// Returns the top-level file paths of [folder], or none when it is missing.
Set<String> _topLevelPaths(Directory folder) {
  if (!folder.existsSync()) return <String>{};
  return {
    for (final entry in folder.listSync())
      if (entry is File) entry.uri.pathSegments.last,
  };
}
