/// A link the index stores: the DocPath of the doc it is written in and of the
/// doc it reaches.
final class IndexedLink {
  const new({required this.source, required this.target});

  final String source;
  final String target;
}
