/// One line of a held section's body.
///
/// `line` is its 1-based line in the text read; `fenced` is true for fenced
/// code content and the fence lines.
typedef BodyLine = ({String text, int line, bool fenced});
