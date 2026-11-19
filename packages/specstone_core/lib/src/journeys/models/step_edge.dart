/// One on-path pair of step indexes: the step followed, and its follower.
final class StepEdge {
  const new({required this.from, required this.to});

  final int from;
  final int to;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is StepEdge && other.from == from && other.to == to;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(from, to);
}
