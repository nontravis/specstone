/// A cite candidate of a typed doc's body: the doc name or
/// path as written, less its `#<section key>`, at its 1-based file `line`,
/// with the section key it names, null when it names none, and the item IDs
/// of the run right after it.
///
/// A candidate holds no resolution: `check` and the cite pass judge it when
/// they run.
final class CiteCandidate {
  const new({
    required this.line,
    required this.written,
    required this.sectionKey,
    required this.itemIds,
  });

  final int line;
  final String written;
  final String? sectionKey;
  final List<String> itemIds;
}
