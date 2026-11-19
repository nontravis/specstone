/// The most sentences a line, or a table cell, may hold.
final class SentenceLimit {
  const new({required this.count, this.linePrefix, this.column});

  /// The most sentences allowed.
  final int count;

  /// Limits the check to lines that start with it.
  final String? linePrefix;

  /// Limits the check to cells under this table header.
  final String? column;

  /// Returns the JSON object of this limit, each optional key only when set.
  Map<String, Object> toJson() => {
    'count': count,
    'linePrefix': ?linePrefix,
    'column': ?column,
  };
}
