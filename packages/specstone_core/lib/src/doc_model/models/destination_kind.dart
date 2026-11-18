/// How `markdown` 7.3.1 reads a link destination as written, which decides
/// the backslashes its link parser drops before the rest is decoded.
enum DestinationKind {
  /// An inline link's or image's destination, bare.
  inline,

  /// An inline link's or image's destination in angle brackets.
  angleInline,

  /// A link reference definition's destination, bare or in angle brackets.
  definition,
}
