/// The DocPath of the gnfr doc that holds an NFR, and its Statement line; empty
/// without one.
final class NfrStatement {
  const new({required this.path, required this.text});

  final String path;
  final String text;
}
