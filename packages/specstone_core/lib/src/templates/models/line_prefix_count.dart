/// A line prefix, and how many items opening with it a section must hold.
final class LinePrefixCount {
  const new({required this.linePrefix, required this.count});

  final String linePrefix;
  final int count;
}
