/// A doc's LF text after a rewrite, and the number of places it changed.
final class CountedRewrite {
  const new({required this.lfText, required this.count});

  final String lfText;
  final int count;
}
