/// An ATX heading line: its level, 1 to 6, and its text without the marks.
final class AtxHeading {
  const new({required this.level, required this.text});

  final int level;
  final String text;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is AtxHeading && other.level == level && other.text == text;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(level, text);
}
