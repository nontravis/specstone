/// The 1-based file lines `first` through `last`, both included.
final class LineRange {
  const new({required this.first, required this.last});

  final int first;
  final int last;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is LineRange && other.first == first && other.last == last;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(first, last);
}
