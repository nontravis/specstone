/// The `{nn}` and `{slug}` values a name holds in a doc type's own segment; a
/// value the segment lacks is null.
final class OwnMatch {
  const new({required this.number, required this.slug});

  final int? number;
  final String? slug;
}
