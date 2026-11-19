import 'dart:io';
import 'dart:typed_data';

import 'package:specstone_core/src/plan_hash.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/feature_pattern_layer.dart';
import 'package:specstone_core/src/templates/layer.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/shared_entry.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/yaml_reader.dart';

/// The `pack.yaml` file name, relative to its pack folder.
const packManifestName = 'pack.yaml';

/// The project's shared-lines file name, relative to `.specstone/templates`.
const projectSharedFileName = '$reservedDocTypeId.yaml';

const _projectSharedKeys = {'shared_lines'};

/// The personal packs folder as faults and plans print it.
const _personalPacksFolder = '~/.specstone/packs';

/// A pack whose manifest is read and checked but whose files are not parsed.
///
/// The parse step runs later, after every listed pack's manifest check, so no
/// doc-type file of any pack parses before every check passes.
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

  /// The pack's folder as faults print it.
  final String displayFolder;

  /// The pack's layer-relative file paths.
  final List<String> _paths;

  /// The layer's file-existence view.
  final LayerFiles _files;

  /// The layer's byte reader.
  final Uint8List Function(String path) _read;

  /// Returns the pack's doc-type layers, keyed by id, in code point order.
  ///
  /// Every YAML file is read as bytes through `decodeYamlBytes`.
  /// Throws a [TemplateFault] for any format fault.
  Map<String, DocTypeLayer> parseDocTypes() => {
    for (final path in _docTypeNames(_paths))
      path.substring(0, path.length - '.yaml'.length): DocTypeLayer.parse(
        decodeYamlBytes(_read(path), file: '$displayFolder/$path'),
        file: '$displayFolder/$path',
        docTypeId: path.substring(0, path.length - '.yaml'.length),
        kind: kind,
        files: _files,
      ),
  };

  /// Returns the text of each doc-type file, keyed by layer-relative path, in
  /// code point order, with CRLF read as LF.
  ///
  /// Throws a [TemplateFault] `yaml_syntax` for a file that is not UTF-8.
  Map<String, String> docTypeTexts() => {
    for (final path in _docTypeNames(_paths))
      path: decodeYamlBytes(_read(path), file: '$displayFolder/$path'),
  };

  /// Returns the pack's feature pattern layers, keyed by id, in code point
  /// order.
  ///
  /// Only `patterns/<id>.yaml` files are patterns. Throws a [TemplateFault]
  /// for any format fault.
  Map<String, FeaturePatternLayer> parseFeaturePatterns() => {
    for (final path in _featurePatternNames(_paths))
      _patternId(path): _parsePatternFile(
        path,
        displayFolder: displayFolder,
        bytes: _read(path),
        kind: kind,
        files: _files,
      ),
  };
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

/// Reads the manifest of the shipped pack [name] from its embedded [files].
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

/// Reads the manifest of the personal pack [name] under [home].
///
/// The pack folder is `~/.specstone/packs/<name>`; faults print it as that
/// path with `/` separators. Call [LoadedPack.parseDocTypes] later to parse
/// its doc-type files.
LoadedPack loadPersonalPackManifest(String name, Directory home) {
  final displayFolder = '$_personalPacksFolder/$name';
  final folder = Directory.fromUri(home.uri.resolve('.specstone/packs/$name/'));
  return LoadedPack._(
    manifest: _packManifest(displayFolder, _manifestBytes(folder)),
    kind: LayerKind.personal,
    displayFolder: displayFolder,
    paths: [..._topLevelPaths(folder), ..._patternPaths(folder)],
    files: _DiskFiles(folder),
    read: (path) => readPlanInput(File.fromUri(folder.uri.resolve(path))),
  );
}

/// Loads the personal packs among [manifests] from [home], in the order of
/// [manifests].
///
/// A manifest read from a shipped pack is skipped. [home] is null only when
/// [manifests] holds no personal pack.
List<LoadedPack> loadPersonalPacks(
  Iterable<PackManifest> manifests, {
  required Directory? home,
}) => [
  for (final manifest in manifests)
    if (manifest.file.startsWith('$_personalPacksFolder/'))
      loadPersonalPackManifest(manifest.name, home!),
];

/// Loads the project templates under [root], in code point order.
///
/// The template folder is `.specstone/templates`; faults print files relative
/// to the project root with `/` separators. Only `<id>.yaml` files at the
/// folder top level are doc types, `shared.yaml` excepted; other files are
/// reference targets (Review Focus 1). Throws a [TemplateFault] for any format
/// fault.
List<DocTypeLayer> loadProjectTemplates(Directory root) {
  const displayFolder = '.specstone/templates';
  final folder = Directory.fromUri(root.uri.resolve(displayFolder));
  if (!folder.existsSync()) return <DocTypeLayer>[];
  return [
    for (final path in _docTypeNames(_topLevelPaths(folder)))
      if (path != projectSharedFileName)
        DocTypeLayer.parse(
          decodeYamlBytes(
            readPlanInput(File.fromUri(folder.uri.resolve(path))),
            file: '$displayFolder/$path',
          ),
          file: '$displayFolder/$path',
          docTypeId: path.substring(0, path.length - '.yaml'.length),
          kind: LayerKind.project,
          files: _DiskFiles(folder),
        ),
  ];
}

/// Loads the shared lines of `.specstone/templates/shared.yaml` under [root].
///
/// Returns none when the file is absent, holds no key, or holds `shared_lines:`
/// with no value. Throws `unknown_key` for any other top-level key,
/// `shared_fields` included, and a [TemplateFault] for any other format fault.
List<SharedLine> loadProjectSharedLines(Directory root) {
  const display = '.specstone/templates/$projectSharedFileName';
  final file = File.fromUri(root.uri.resolve(display));
  if (!file.existsSync()) return <SharedLine>[];
  final map = readYamlMap(
    decodeYamlBytes(readPlanInput(file), file: display),
    file: display,
  );
  checkKeys(map, _projectSharedKeys, file: display, format: 'shared');
  return parseSharedEntries(map, file: display, allowsFields: false).lines;
}

/// Loads the project feature patterns under [root], in code point order.
///
/// The files are `.specstone/templates/patterns/<id>.yaml`; faults print them
/// relative to the project root with `/` separators. Throws a
/// [TemplateFault] for any format fault.
List<FeaturePatternLayer> loadProjectFeaturePatterns(Directory root) {
  const displayFolder = '.specstone/templates';
  final folder = Directory.fromUri(root.uri.resolve(displayFolder));
  return [
    for (final path in _featurePatternNames(_patternPaths(folder)))
      _parsePatternFile(
        path,
        displayFolder: displayFolder,
        bytes: readPlanInput(File.fromUri(folder.uri.resolve(path))),
        kind: LayerKind.project,
        files: _DiskFiles(folder),
      ),
  ];
}

/// Parses the feature pattern file at [path], relative to its layer folder.
FeaturePatternLayer _parsePatternFile(
  String path, {
  required String displayFolder,
  required Uint8List bytes,
  required LayerKind kind,
  required LayerFiles files,
}) {
  final file = '$displayFolder/$path';
  return FeaturePatternLayer.parse(
    decodeYamlBytes(bytes, file: file),
    file: file,
    patternId: _patternId(path),
    kind: kind,
    files: files,
  );
}

/// Returns the pattern id of [path], `patterns/<id>.yaml`.
String _patternId(String path) =>
    path.substring('patterns/'.length, path.length - '.yaml'.length);

/// Returns the feature pattern file names of [paths] in code point order.
List<String> _featurePatternNames(Iterable<String> paths) => [
  for (final path in paths)
    if (isFeaturePatternFileName(path)) path,
]..sort(compareCodePoints);

/// Returns the files directly under `patterns/` of [folder] as
/// `patterns/<name>`, or none when the folder is missing.
Set<String> _patternPaths(Directory folder) {
  final patterns = Directory.fromUri(folder.uri.resolve('patterns/'));
  return {for (final path in _topLevelPaths(patterns)) 'patterns/$path'};
}

/// Parses the pack manifest from its [bytes], null when the file is absent.
///
/// [displayFolder] is the pack folder as faults print it. An absent
/// `pack.yaml` is `missing_key` at the manifest's `name` key, since the fault
/// catalog carries no absent-manifest code and an unusable manifest
/// routes there.
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
  return readPlanInput(manifest);
}

/// Returns the doc-type names of [paths] in code point order.
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
