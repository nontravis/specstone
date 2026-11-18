import 'package:markdown/markdown.dart' show Node;

/// Nodes `markdown` parses a text into, in source order, and the top-level
/// footnote definitions among them that it drops (see `MarkdownTree`).
final class SourceOrderNodes {
  const new({required this.nodes, required this.dropped});

  final List<Node> nodes;
  final Set<Node> dropped;
}
