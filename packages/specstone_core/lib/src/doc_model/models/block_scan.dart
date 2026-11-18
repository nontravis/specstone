/// The block reading of a run of lines.
///
/// Per line, `fenced` is whether it is fenced code content or a fence
/// delimiter, and `continuesParagraph` whether it is the next line of the
/// paragraph above it (GFM). `openFence` is the delimiter line of a fence
/// still open after the last line, or null when every fence closed.
final class BlockScan {
  const new({
    required this.fenced,
    required this.continuesParagraph,
    required this.openFence,
  });

  final List<bool> fenced;
  final List<bool> continuesParagraph;
  final String? openFence;
}
