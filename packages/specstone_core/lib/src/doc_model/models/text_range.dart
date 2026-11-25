/// A body range, `start` included, `end` excluded.
final class TextRange {
  const new({required this.start, required this.end});

  final int start;
  final int end;
}
