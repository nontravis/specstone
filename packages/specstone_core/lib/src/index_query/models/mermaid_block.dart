/// A `mermaid` block as the line facts keep it: its opening fence's 1-based
/// file line and the [hash] of its text.
final class MermaidBlock {
  const new({required this.fenceLine, required this.hash});

  /// The 1-based file line of the opening fence.
  final int fenceLine;

  /// The full `sha256` hex of the block's text.
  final String hash;
}
