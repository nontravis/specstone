/// The stored outcome of parsing one `mermaid` block.
final class DiagramParse {
  const new({
    required this.blockHash,
    this.diagram,
    required this.parses,
    this.message,
    this.blockLine,
  });

  /// The content hash of the block's text.
  final String blockHash;

  /// The diagram type the parser found; null when it found none.
  final String? diagram;

  /// Whether the parser accepted the block.
  final bool parses;

  /// The parser's error text; null when the block parses.
  final String? message;

  /// The 1-based line inside the block the error points at; null when none.
  final int? blockLine;
}
