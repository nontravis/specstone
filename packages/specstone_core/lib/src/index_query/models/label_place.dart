/// A number label at its file line, as it is written.
final class LabelPlace {
  const new({required this.line, required this.written});

  final int line;
  final String written;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is LabelPlace && other.line == line && other.written == written;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(line, written);
}
