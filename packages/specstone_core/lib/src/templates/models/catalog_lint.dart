/// A section table that is a code catalog.
final class CatalogLint {
  const new({required this.column});

  /// The header of the column whose code spans are the catalog's codes.
  final String column;

  /// Returns the JSON object of this catalog.
  Map<String, Object> toJson() => {'column': column};
}
