/// One `<CAPITALS>-<digits>` part of a label chain, as it is written.
final class LabelPart {
  const new({
    required this.prefix,
    required this.written,
    this.ownerWritten,
    this.ownerStart,
  });

  /// The capitals and the dash, such as `FO-`.
  final String prefix;

  /// The prefix and the digits.
  final String written;

  /// The `written` of the built-in number label the part lies in; null for a
  /// part with a prefix outside the built-in ones.
  final String? ownerWritten;

  /// The offset in the line where that built-in label starts, which tells two
  /// equal labels of one line apart; null with [ownerWritten].
  final int? ownerStart;
}
