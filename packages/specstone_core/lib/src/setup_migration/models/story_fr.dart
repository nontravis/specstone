/// The story and FR numbers of the FR doc a `## FR trace` cell names.
final class StoryFr {
  const new({required this.story, required this.fr});

  final int story;
  final int fr;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is StoryFr && other.story == story && other.fr == fr;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(story, fr);
}
