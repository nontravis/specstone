/// Where a link `[text](destination)` ends: `textEnd` is the offset of its
/// `]`, `end` one past its `)`.
final class LinkEnds {
  const new({required this.textEnd, required this.end});

  final int textEnd;
  final int end;
}
