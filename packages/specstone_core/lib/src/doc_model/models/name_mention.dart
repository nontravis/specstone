import 'package:specstone_core/src/doc_model/models/doc_address.dart';

/// A doc-name mention: a code span whose whole text, less an optional
/// `#<section key>`, reads as a DocAddress of the no-lookup class, or a token
/// of that class in a `mermaid` block.
///
/// `line` is 1-based and `column` the 0-based offset of the first character
/// of `text` in its line, after the opening backticks.
final class NameMention {
  const new({
    required this.line,
    required this.column,
    required this.text,
    required this.address,
  });

  final int line;
  final int column;
  final String text;
  final DocAddress address;
}
