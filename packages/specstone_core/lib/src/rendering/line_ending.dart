/// The line-break style of a text file.
enum LineEnding {
  /// `\n`.
  lf,

  /// `\r\n`.
  crlf;

  /// Returns the style of the first line break in [text], [lf] without one.
  static LineEnding of(String text) {
    final firstBreak = text.indexOf('\n');
    final isCrlf = firstBreak > 0 && text.codeUnitAt(firstBreak - 1) == 0x0D;
    return isCrlf ? crlf : lf;
  }

  /// Returns [lfText] with every `\n` written in this style.
  String apply(String lfText) =>
      this == crlf ? lfText.replaceAll('\n', '\r\n') : lfText;
}

/// Returns [text] with each `\r\n` turned into `\n`.
String toLf(String text) => text.replaceAll('\r\n', '\n');
