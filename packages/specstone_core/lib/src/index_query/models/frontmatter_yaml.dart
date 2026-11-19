import 'package:yaml/yaml.dart'
    show YamlException, YamlMap, YamlScalar, loadYamlNode;

/// The frontmatter YAML read once: the mapping it holds, or the line that
/// makes it invalid.
///
/// Both are null for an empty or comment-only block. `errorLine` is the line
/// the YAML parser names, or 1 when the block is no mapping.
final class FrontmatterYaml {
  const new({required this.map, required this.errorLine});

  /// Reads [source], the frontmatter lines between the `---` delimiters, as a
  /// mapping or the line that makes it invalid.
  ///
  /// File line numbers are the node line plus 2, since [source] starts on
  /// line 2.
  factory parse(String source) {
    try {
      final node = loadYamlNode(source);
      if (node is YamlMap) return FrontmatterYaml(map: node, errorLine: null);
      if (node is YamlScalar && node.value == null) {
        return const FrontmatterYaml(map: null, errorLine: null);
      }
      return const FrontmatterYaml(map: null, errorLine: 1);
    } on YamlException catch (e) {
      return FrontmatterYaml(map: null, errorLine: e.span!.start.line + 2);
    }
  }

  final YamlMap? map;
  final int? errorLine;
}
