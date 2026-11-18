import 'package:yaml/yaml.dart' show YamlMap;

/// The frontmatter YAML read once: the mapping it holds, or the line that
/// makes it invalid.
///
/// Both are null for an empty or comment-only block. `errorLine` is the line
/// the YAML parser names, or 1 when the block is no mapping.
final class FrontmatterYaml {
  const new({required this.map, required this.errorLine});

  final YamlMap? map;
  final int? errorLine;
}
