/// One line of a held section's body.
///
/// `line` is the 1-based file line; `fenced` is true for fenced code content
/// and the fence lines.
typedef BodyLine = ({String text, int line, bool fenced});
