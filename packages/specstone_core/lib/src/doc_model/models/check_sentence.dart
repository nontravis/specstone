/// A sentence of the check's cut, and whether a `###` heading ends it.
final class CheckSentence {
  const new({required this.text, required this.isHeading});

  final String text;
  final bool isHeading;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is CheckSentence &&
      other.text == text &&
      other.isHeading == isHeading;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(text, isHeading);
}
