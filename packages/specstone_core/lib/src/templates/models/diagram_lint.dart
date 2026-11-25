/// The checks on each `mermaid` diagram block in a section.
final class DiagramLint {
  const new({
    this.title = false,
    this.edgeLabels = false,
    this.bannedLabels = const [],
    this.names = false,
  });

  /// Whether a diagram must carry a title.
  final bool title;

  /// Whether every edge must carry a label.
  final bool edgeLabels;

  /// The labels a diagram may not hold.
  final List<String> bannedLabels;

  /// Whether each node, participant, or actor name must match a source name.
  final bool names;

  /// Returns the JSON object of this diagram lint.
  Map<String, Object> toJson() => {
    'title': title,
    'edgeLabels': edgeLabels,
    'bannedLabels': bannedLabels,
    'names': names,
  };
}
