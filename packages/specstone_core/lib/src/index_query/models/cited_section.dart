/// What a classifier needs of the `##` section a link names.
final class CitedSection {
  const new({
    required this.key,
    required this.prefixId,
    required this.isAcceptanceCriteria,
  });

  final String key;
  final String? prefixId;
  final bool isAcceptanceCriteria;
}
