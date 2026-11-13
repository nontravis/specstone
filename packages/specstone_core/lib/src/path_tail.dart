const _tailMark = ':';

/// Splits [text] of the form `path[:tail]` at its first `:`.
///
/// The tail is null when [text] holds no `:`; it keeps its own colons and
/// spaces whole.
({String path, String? tail}) splitPathTail(String text) {
  final split = text.indexOf(_tailMark);
  return split < 0
      ? (path: text, tail: null)
      : (path: text.substring(0, split), tail: text.substring(split + 1));
}
