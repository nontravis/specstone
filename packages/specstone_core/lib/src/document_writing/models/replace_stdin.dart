/// The old and the new passage of a `set --replace` stdin.
final class ReplaceStdin {
  const new({required this.oldPassage, required this.newPassage});

  final String oldPassage;
  final String newPassage;
}
