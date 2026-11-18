/// A text block of a doc: its `text`, and whether a `###` or deeper heading
/// is the block.
final class TextBlock {
  const new({required this.text, required this.isHeading});

  final String text;
  final bool isHeading;
}
