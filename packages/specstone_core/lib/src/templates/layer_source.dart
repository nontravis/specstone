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

/// One loaded pack: its manifest plus every doc-type file it holds.
final class LoadedPack {
  new _({
    required this.manifest,
    required this.kind,
    required this.docTypes,
    required this.displayFolder,
  });

  /// The pack's `pack.yaml`.
  final PackManifest manifest;

  /// Whether the pack is shipped or personal.
  final LayerKind kind;

  /// The pack's doc-type layers, keyed by doc type id.
  final Map<String, DocTypeLayer> docTypes;

  /// The pack's folder as faults print it.
  final String displayFolder;
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

/// Loads the shipped pack [name] from its embedded [files] (F3-D18).
///
/// [files] keys are `<pack>/<path>`; the pack holds the `<pack>/<path>` keys.
/// Doc-type files load in code point order (INV-22); every YAML file is read
/// as bytes through `decodeYamlBytes` (F3-D50). Throws a [TemplateFault] for
/// any format fault.
LoadedPack loadShippedPack(String name, Map<String, Uint8List> files) {
  final displayFolder = 'packs/$name';
  final packFiles = <String, Uint8List>{
    for (final MapEntry(:key, :value) in files.entries)
      if (key.startsWith('$name/')) key.substring(name.length + 1): value,
  };
  final manifest = PackManifest.parse(
    decodeYamlBytes(
      packFiles[packManifestName]!,
      file: '$displayFolder/$packManifestName',
    ),
    file: '$displayFolder/$packManifestName',
  );
  return LoadedPack._(
    manifest: manifest,
    kind: LayerKind.shipped,
    docTypes: _docTypes(
      _docTypeNames(packFiles.keys),
      files: _MapFiles(packFiles.keys.toSet()),
      read: (path) => packFiles[path]!,
      kind: LayerKind.shipped,
      displayFolder: displayFolder,
    ),
    displayFolder: displayFolder,
  );
}

/// Loads the personal pack [name] under [home] (US-04 FR-01).
///
/// The pack folder is `~/.specstone/packs/<name>`; faults print it as that
/// path with `/` separators. Doc-type files load in code point order
/// (INV-22); every YAML file is read as bytes through `decodeYamlBytes`
/// (F3-D50). Throws a [TemplateFault] for any format fault.
LoadedPack loadPersonalPack(String name, Directory home) {
  final displayFolder = '~/.specstone/packs/$name';
  final folder = Directory.fromUri(home.uri.resolve('.specstone/packs/$name/'));
  final manifest = PackManifest.parse(
    decodeYamlBytes(
      File.fromUri(folder.uri.resolve(packManifestName)).readAsBytesSync(),
      file: '$displayFolder/$packManifestName',
    ),
    file: '$displayFolder/$packManifestName',
  );
  return LoadedPack._(
    manifest: manifest,
    kind: LayerKind.personal,
    docTypes: _docTypes(
      _docTypeNames(_topLevelPaths(folder)),
      files: _DiskFiles(folder),
      read: (path) => File.fromUri(folder.uri.resolve(path)).readAsBytesSync(),
      kind: LayerKind.personal,
      displayFolder: displayFolder,
    ),
    displayFolder: displayFolder,
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
  return _docTypes(
    _docTypeNames(_topLevelPaths(folder)),
    files: _DiskFiles(folder),
    read: (path) => File.fromUri(folder.uri.resolve(path)).readAsBytesSync(),
    kind: LayerKind.project,
    displayFolder: displayFolder,
  ).values.toList();
}

/// Returns the layers for [names] keyed by doc type id, in [names] order.
///
/// [read] returns the bytes of one layer-relative path; [files] answers
/// whether the layer holds a file, so nested reference targets resolve.
Map<String, DocTypeLayer> _docTypes(
  List<String> names, {
  required LayerFiles files,
  required Uint8List Function(String path) read,
  required LayerKind kind,
  required String displayFolder,
}) {
  return {
    for (final path in names)
      path.substring(0, path.length - '.yaml'.length): DocTypeLayer.parse(
        decodeYamlBytes(read(path), file: '$displayFolder/$path'),
        file: '$displayFolder/$path',
        docTypeId: path.substring(0, path.length - '.yaml'.length),
        kind: kind,
        files: files,
      ),
  };
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
