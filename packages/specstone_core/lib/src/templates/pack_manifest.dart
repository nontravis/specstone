import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/yaml_reader.dart';

const _keys = {'name', 'version', 'extends'};

/// The `pack.yaml` of one pack: its name, version, and optional base pack.
final class PackManifest {
  new _({
    required this.name,
    required this.version,
    required this.extendsPack,
    required this.file,
  });

  /// Parses the text of a `pack.yaml` read from [file].
  ///
  /// `name` and `version` are required (`missing_key`); a key outside `name`,
  /// `version`, and `extends` is `unknown_key`.
  static PackManifest parse(String text, {required String file}) {
    final map = readYamlMap(text, file: file);
    checkKeys(map, _keys, file: file, format: 'pack');
    final name = requireValue<String>(map, 'name', file: file);
    requireValue<Object>(map, 'version', file: file);
    final version = PackVersion.fromYaml(
      map.nodes['version']!,
      file: file,
      key: 'version',
    );
    return PackManifest._(
      name: name,
      version: version,
      extendsPack: optionalValue<String>(map, 'extends', file: file),
      file: file,
    );
  }

  /// The pack name.
  final String name;

  /// The pack version.
  final PackVersion version;

  /// The name of the pack this pack extends, when written.
  final String? extendsPack;

  /// The file this manifest was read from.
  final String file;
}
