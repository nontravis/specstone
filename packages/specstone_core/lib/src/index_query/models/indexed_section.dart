/// One `##` section of an indexed doc.
final class IndexedSection {
  const new({required this.key, required this.headerLine, required this.body});

  /// The template section id, else the `sectionKeyOf` key of the header.
  final String key;

  /// The `##` line as written, without its line ending.
  final String headerLine;

  /// Every line after the header line up to the next section header.
  final String body;

  /// The header line and the body, without the final line break.
  String get text {
    final whole = '$headerLine\n$body';
    return whole.endsWith('\n') ? whole.substring(0, whole.length - 1) : whole;
  }
}
