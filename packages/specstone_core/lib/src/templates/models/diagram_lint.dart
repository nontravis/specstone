/// The checks on each `mermaid` flowchart in a section.
final class DiagramLint {
  const new({
    this.title = false,
    this.edgeLabels = false,
    this.bannedLabels = const [],
  });

  /// Whether a diagram must carry a title.
  final bool title;

  /// Whether every edge must carry a label.
  final bool edgeLabels;

  /// The labels a diagram may not hold.
  final List<String> bannedLabels;

  /// Returns the JSON object of this diagram lint.
  Map<String, Object> toJson() => {
    'title': title,
    'edgeLabels': edgeLabels,
    'bannedLabels': bannedLabels,
  };
}
