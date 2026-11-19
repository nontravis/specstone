/// The anchors of one doc body.
final class DocAnchors {
  /// Makes [headingSlugs] and [htmlIds] the doc's anchor set.
  const new({
    required this.headingSlugs,
    required this.headingLevels,
    required this.htmlIds,
  });

  /// One slug per heading, in file order, a repeat suffixed `-1`, `-2`.
  final List<String> headingSlugs;

  /// The level, 1 to 6, of each heading of [headingSlugs], in the same order.
  final List<int> headingLevels;

  /// Each body start tag's `id` and each `<a>`'s `name`, footnote ids
  /// excluded.
  final Set<String> htmlIds;

  /// Whether [anchor] names a heading slug or an html id of this doc.
  bool holds(String anchor) =>
      headingSlugs.contains(anchor) || htmlIds.contains(anchor);

  /// Returns the anchors as JSON values, as `LineFacts.toJson` stores them.
  Map<String, Object> toJson() => {
    'headings': headingSlugs,
    'levels': headingLevels,
    'ids': htmlIds.toList(),
  };
}
