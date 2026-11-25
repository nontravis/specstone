/// One agent file write.
final class AgentWrite {
  const new({
    required this.path,
    required this.text,
    required this.isNew,
    required this.before,
    required this.isAtTop,
  });

  /// The path from the project root; it may name a symbolic link, which the
  /// writer must write through to the link's target.
  final String path;

  /// The whole new file text, in the file's own line ending.
  final String text;

  /// Whether the file does not exist yet.
  final bool isNew;

  /// The `textHashOf` of the existing file's text; null for a new file.
  final String? before;

  /// Whether the file lies at a repository top, outside the project's commits.
  final bool isAtTop;
}
