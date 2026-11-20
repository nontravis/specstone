/// The Specstone marker lines of a text, numbered from 1.
///
/// `firstMarkerLine` is the first BEGIN or END line, or the opening line of
/// the code fence still open at the end, null without either.
/// `openFenceLine` is that fence's opening line alone, null when every fence
/// closes.
final class MarkerScan {
  const new({
    required this.beginLine,
    required this.endLine,
    required this.firstMarkerLine,
    required this.openFenceLine,
    required this.isMalformed,
  });

  final int? beginLine;
  final int? endLine;
  final int? firstMarkerLine;
  final int? openFenceLine;
  final bool isMalformed;
}
