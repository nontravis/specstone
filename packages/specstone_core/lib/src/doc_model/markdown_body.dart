import 'package:markdown/markdown.dart';

/// Returns the nodes the `markdown` package parses [text] into, or null when
/// that parse throws.
///
/// This is the one call that parses doc text. `markdown` 7.3.1 has no failure
/// contract: a fault in it throws whatever the fault is, so the catch takes
/// every object. The classes `## Verified items` of the link-parse-crash plan
/// lists are a RangeError (a definition-shaped paragraph ending in a backslash
/// or a bare `<`, which `LinkParser` reads past its end), an AssertionError (a
/// definition with an unclosed title followed by a table delimiter row, where
/// `BlockParser.parseLines` stops advancing), a TypeError (a footnote
/// definition holding a list), and a StackOverflowError (a deeply nested
/// blockquote). A caller that gets null treats the doc as one it can read no
/// links from and goes on, as LP2 decides.
List<Node>? parseMarkdown(String text) {
  try {
    return Document(extensionSet: ExtensionSet.gitHubFlavored).parse(text);
  } on Object {
    return null;
  }
}
