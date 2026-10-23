import 'dart:io';

import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/yaml_reader.dart';
import 'package:yaml/yaml.dart';

/// The project config path, relative to the project root.
const projectConfigPath = '.specstone/config.yaml';

const _coreName = 'prd-core';

/// Lowercase letters and digits in hyphen-separated groups.
final _kebabCase = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

/// Returns the first folder from [start] upward holding a config file.
///
/// The config is `.specstone/config.yaml`. Returns null when no folder up to
/// the file-system root holds one.
Directory? findProjectRoot(Directory start) {
  var dir = start.absolute;
  while (true) {
    if (File.fromUri(dir.uri.resolve(projectConfigPath)).existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

/// The project config: the pack version each pack is pinned to.
final class ProjectConfig {
  new _({required this.pins});

  /// Reads `.specstone/config.yaml` under the project [root].
  ///
  /// Throws `unknown_key` for a key other than `packs` or a `packs` key that
  /// is not kebab-case, `missing_key` when `packs` is absent,
  /// `pack_version_invalid` for a bad pin, and `prd_core_missing` when `packs`
  /// pins no `prd-core`.
  ///
  /// A `packs` key is checked before its pin parses, so the first fault in file
  /// order wins, and before any pack file is opened.
  static ProjectConfig read(Directory root) {
    final text = decodeYamlBytes(
      File.fromUri(root.uri.resolve(projectConfigPath)).readAsBytesSync(),
      file: projectConfigPath,
    );
    final map = readYamlMap(text, file: projectConfigPath);
    checkKeys(map, {'packs'}, file: projectConfigPath, format: 'config');
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
    return ProjectConfig._(pins: Map.unmodifiable(pins));
  }

  /// The pinned version of each pack, in file order.
  final Map<String, PackVersion> pins;

  /// The config path, relative to the project root.
  String get file => projectConfigPath;
}
