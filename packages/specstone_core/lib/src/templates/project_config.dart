import 'dart:io';

import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/yaml_reader.dart';
import 'package:yaml/yaml.dart';

/// The project config path, relative to the project root.
const projectConfigPath = '.specstone/config.yaml';

const _coreName = 'prd-core';
const _codeRootKey = 'code_root';

/// Lowercase letters and digits in hyphen-separated groups.
final _kebabCase = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

final _driveLetter = RegExp('^[A-Za-z]:');

/// Returns the project root for a folder holding a `docs` link.
///
/// When `<folder>/docs` is a symbolic link, the root is the parent of the
/// link's resolved target; otherwise [folder]. The result is canonical.
Directory rootThroughDocsLink(Directory folder) {
  final docs = '${folder.path}${Platform.pathSeparator}docs';
  if (FileSystemEntity.isLinkSync(docs)) {
    try {
      return Directory(Link(docs).resolveSymbolicLinksSync()).parent;
    } on FileSystemException {
      // A dangling link has no target to stand for; the folder is the root.
    }
  }
  return Directory(folder.resolveSymbolicLinksSync());
}

/// Returns the first root from [start] upward for which [isRoot] holds.
///
/// The walk is [matchRootUpward]'s. Returns null when no folder up to the
/// file-system root yields one; never throws.
Directory? findRootUpward(
  Directory start,
  bool Function(Directory candidate) isRoot,
) => matchRootUpward(start, isRoot)?.root;

/// Returns the first root from [start] upward for which [isRoot] holds, with
/// the folder the walk stood in.
///
/// At each folder the candidates are [rootThroughDocsLink] of the folder, then
/// the folder itself when that is another path. A `docs` link to a folder
/// outside any project thus falls through to the folder's own markers. The
/// root and the folder are canonical; they differ only when the root came
/// through the folder's `docs` link. Returns null when no folder up to the
/// file-system root yields one; never throws, a folder that cannot be resolved
/// stands for itself, absolute.
({Directory folder, Directory root})? matchRootUpward(
  Directory start,
  bool Function(Directory candidate) isRoot,
) {
  var dir = start.absolute;
  while (true) {
    final own = _canonicalOr(
      () => Directory(dir.resolveSymbolicLinksSync()),
      dir,
    );
    final linked = _canonicalOr(() => rootThroughDocsLink(dir), dir);
    if (isRoot(linked)) return (folder: own, root: linked);
    if (own.path != linked.path && isRoot(own)) return (folder: own, root: own);
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

Directory _canonicalOr(Directory Function() resolve, Directory fallback) {
  try {
    return resolve();
  } on FileSystemException {
    return fallback;
  }
}

/// Returns the project root holding [start], or null outside a project.
///
/// The root is the first [findRootUpward] candidate holding
/// `.specstone/config.yaml`, canonical. Never throws.
Directory? findProjectRoot(Directory start) => findRootUpward(
  start,
  (candidate) =>
      File.fromUri(candidate.uri.resolve(projectConfigPath)).existsSync(),
);

/// The project config: the pack version each pack is pinned to and the folder
/// code paths are written from.
final class ProjectConfig {
  new _({required this.pins, required this.codeRoot});

  /// Reads `.specstone/config.yaml` under the project [root].
  ///
  /// Throws `unknown_key` for a key other than `packs` and `code_root` or a
  /// `packs` key that is not kebab-case, `missing_key` when `packs` is absent,
  /// `pack_version_invalid` for a bad pin, `prd_core_missing` when `packs`
  /// pins no `prd-core`, and `unknown_value` for a `code_root` that is not a
  /// string, is empty, is absolute, or holds a backslash.
  ///
  /// A `packs` key is checked before its pin parses, so the first fault in file
  /// order wins, and before any pack file is opened.
  static ProjectConfig read(Directory root) {
    final text = decodeYamlBytes(
      File.fromUri(root.uri.resolve(projectConfigPath)).readAsBytesSync(),
      file: projectConfigPath,
    );
    final map = readYamlMap(text, file: projectConfigPath);
    checkKeys(
      map,
      {'packs', _codeRootKey},
      file: projectConfigPath,
      format: 'config',
    );
    final packs = requireValue<YamlMap>(map, 'packs', file: projectConfigPath);
    final pins = <String, PackVersion>{};
    for (final MapEntry(:key, :value) in packs.nodes.entries) {
      final name = '${(key as YamlNode).value}';
      if (!_kebabCase.hasMatch(name)) {
        throw TemplateFault(
          FaultCode.unknownKey,
          'pack names are kebab-case',
          file: projectConfigPath,
          key: 'packs.$name',
        );
      }
      pins[name] = PackVersion.fromYaml(
        value,
        file: projectConfigPath,
        key: 'packs.$name',
      );
    }
    if (!pins.containsKey(_coreName)) {
      throw TemplateFault(
        FaultCode.prdCoreMissing,
        'the packs must pin $_coreName',
        file: projectConfigPath,
        key: 'packs',
      );
    }
    return ProjectConfig._(
      pins: Map.unmodifiable(pins),
      codeRoot: _readCodeRoot(map),
    );
  }

  /// The pinned version of each pack, in file order.
  final Map<String, PackVersion> pins;

  /// The folder code paths are written from, relative to the project root.
  ///
  /// `/`-separated and possibly outside the project root (`../code`); `.` when
  /// the config has no `code_root`.
  final String codeRoot;

  /// The config path, relative to the project root.
  String get file => projectConfigPath;
}

String _readCodeRoot(YamlMap map) {
  final value = optionalValue<String>(
    map,
    _codeRootKey,
    file: projectConfigPath,
  );
  if (value == null) return '.';
  if (!isCodeRootValue(value)) {
    throw TemplateFault(
      FaultCode.unknownValue,
      'the key $_codeRootKey must be a non-empty relative path with / '
      'separators',
      file: projectConfigPath,
      key: _codeRootKey,
    );
  }
  return value;
}

/// Whether [value] is a `code_root` the config reader accepts: a non-empty
/// relative path with `/` separators.
///
/// Omitting the key or writing `.` is the one spelling of the root itself, so
/// the empty string is refused.
bool isCodeRootValue(String value) =>
    value.isNotEmpty && !_isAbsolute(value) && !value.contains(r'\');

/// Whether [path] is rooted or starts with a drive letter, on any platform.
///
/// A config written on Windows must stay invalid on POSIX, where `C:/abs` is
/// an ordinary relative name to `File.isAbsolute`.
bool _isAbsolute(String path) =>
    path.startsWith('/') || _driveLetter.hasMatch(path);
