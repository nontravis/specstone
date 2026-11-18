/// An attribute of a start tag in html: its name in ASCII lower case, the
/// span of its value, and the tag holding it.
final class HtmlAttribute {
  const new({
    required this.name,
    required this.start,
    required this.end,
    required this.value,
    required this.tag,
  });

  final String name;
  final int start;
  final int end;
  final String value;
  final String tag;
}
