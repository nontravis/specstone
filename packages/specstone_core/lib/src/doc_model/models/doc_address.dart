/// A doc reference split into its parts; DocIndex
/// resolves it.
final class DocAddress {
  const new({this.typeId, required this.body, this.sectionKey});

  /// The text before the first `:`, when that text is one slug
  /// (`[a-z][a-z0-9_]*`) and the `:` sits before any `#`.
  final String? typeId;

  /// The Name or path after any `<doc type>:`, before any `#`, as written.
  final String body;

  /// The text after the first `#`; null when the text holds no `#`.
  final String? sectionKey;

  /// Whether [body] is a Name: one or more slugs (`[a-z0-9_]+`) joined by
  /// `/`.
  bool get isName => _slugCount(body) >= 1;

  /// Whether the form alone marks a reference: a Name of 2 or more
  /// slugs, bare or after `<doc type>:`, or a one-slug Name after
  /// `<doc type>:`.
  bool get isReferenceWithoutLookup =>
      typeId != null ? isName : _slugCount(body) >= 2;

  /// The text as written, less any `#<section key>`.
  String get docPart => typeId == null ? body : '$typeId:$body';
}

/// The number of `/`-joined slugs in [text]; 0 when any segment is not a
/// non-empty run of `[a-z0-9_]`.
int _slugCount(String text) {
  var count = 0;
  var segmentLength = 0;
  for (var i = 0; i <= text.length; i++) {
    if (i < text.length && _isSlugChar(text.codeUnitAt(i))) {
      segmentLength++;
      continue;
    }
    if (i < text.length && text.codeUnitAt(i) != 0x2F) return 0;
    if (segmentLength == 0) return 0;
    count++;
    segmentLength = 0;
  }
  return count;
}

bool _isSlugChar(int code) =>
    (code >= 0x61 && code <= 0x7A) || // a-z
    (code >= 0x30 && code <= 0x39) || // 0-9
    code == 0x5F; // _
