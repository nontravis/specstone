/// Returns [text] with each `\r\n` turned into `\n`.
///
/// Returns [text] itself when it holds no `\r`.
String toLf(String text) =>
    text.contains('\r') ? text.replaceAll('\r\n', '\n') : text;
