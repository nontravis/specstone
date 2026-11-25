/// The cap on the fenced code blocks of a section.
final class MaxCodeBlocks {
  const new({required this.count, this.perSubsection = false});

  /// The most code blocks, of any info string.
  final int count;

  /// Whether each subsection is capped alone, not the whole section.
  final bool perSubsection;

  /// Returns the JSON object of this cap.
  Map<String, Object> toJson() => {
    'count': count,
    'perSubsection': perSubsection,
  };
}
