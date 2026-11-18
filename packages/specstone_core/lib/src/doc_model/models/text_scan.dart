/// The `\n` count and the surrogate pair count of a text.
final class TextScan {
  const new({required this.breaks, required this.pairs});

  final int breaks;
  final int pairs;
}
