/// A folder segment of a path that repeats once per nesting level.
final class NestingSegment {
  const new({required this.index, required this.text});

  final int index;
  final String text;
}
