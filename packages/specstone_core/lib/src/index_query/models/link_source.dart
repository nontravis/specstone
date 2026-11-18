/// A source of an `a` or `img` element markdown makes: the body offsets of its
/// first character and after its last, its file line, and, for an inline or
/// reference link or image, its destination as written (null for an autolink,
/// an email autolink, or a GFM bare URL or email), angle brackets dropped, and
/// whether angle brackets enclose it, and the body offset of the `]` that ends
/// its text (null for an autolink, an email autolink, or a GFM bare URL or
/// email, which have no bracketed text); the text starts after the `[`, or
/// after the `![` of an image.
final class LinkSource {
  const new({
    required this.offset,
    required this.end,
    required this.line,
    required this.shown,
    required this.angle,
    required this.textEnd,
  });

  final int offset;
  final int end;
  final int line;
  final String? shown;
  final bool angle;
  final int? textEnd;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is LinkSource &&
      other.offset == offset &&
      other.end == end &&
      other.line == line &&
      other.shown == shown &&
      other.angle == angle &&
      other.textEnd == textEnd;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(offset, end, line, shown, angle, textEnd);
}
