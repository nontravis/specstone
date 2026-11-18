/// The fence reading of a run of lines.
///
/// `opens` holds the info word of the fence a line opens (empty without one),
/// null on any other line; `closes` is whether a line is a closing delimiter.
/// A fence a container ends has no closing line. `contents` holds, per line,
/// the text of a fence's content line past its containers' marks (tabs
/// expanded), and an empty string on any other line.
final class FenceScan {
  const new({
    required this.fenced,
    required this.opens,
    required this.closes,
    required this.contents,
  });

  final List<bool> fenced;
  final List<String?> opens;
  final List<bool> closes;
  final List<String> contents;
}
