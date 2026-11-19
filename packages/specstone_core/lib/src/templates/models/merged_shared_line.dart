/// A shared guide line after every layer merged, as a guide prints it.
final class MergedSharedLine {
  const new({
    required this.id,
    required this.text,
    this.forDocTypes,
    required this.printRank,
  });

  /// The id the layers matched the line by.
  final String id;

  /// The one line of guide text.
  final String text;

  /// The doc type ids the line names; null reaches every doc type of the
  /// merged set.
  final List<String>? forDocTypes;

  /// The place of the line among the lines, set by its first defining layer.
  final int printRank;
}
