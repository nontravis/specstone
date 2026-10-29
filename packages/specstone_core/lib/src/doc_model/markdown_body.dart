import 'package:markdown/markdown.dart';

/// The deepest tree [parseMarkdown] returns, counted in element levels from a
/// top-level node (a paragraph is level 1).
///
/// Every consumer of the nodes walks them recursively: the link walkers and
/// the `markdown` package's `renderToHtml`. Those overflow the stack near
/// 15,000 levels, and the parse itself fails near 4,100. A bound of 1,000 sits
/// well below both, and no real doc nests that deep.
const maxMarkdownDepth = 1000;

/// Returns the nodes the `markdown` package parses [text] into, or null when
/// that parse throws or builds a tree deeper than [maxMarkdownDepth].
///
/// This is the one call that parses doc text. `markdown` 7.3.1 has no failure
/// contract: a fault in it throws whatever the fault is, so the catch takes
/// every object. The classes `## Verified items` of the link-parse-crash plan
/// lists are a RangeError (a definition-shaped paragraph ending in a backslash
/// or a bare `<`, which `LinkParser` reads past its end), an AssertionError (a
/// definition with an unclosed title followed by a table delimiter row, where
/// `BlockParser.parseLines` stops advancing), a TypeError (a footnote
/// definition holding a list), and a StackOverflowError (a deeply nested
/// blockquote). A tree the parser builds but that is too deep to walk counts
/// as a failed parse, so no consumer gets a tree it cannot walk. A caller that
/// gets null treats the doc as one it can read no links from and goes on, as
/// LP2 decides.
List<Node>? parseMarkdown(String text) {
  final List<Node> nodes;
  try {
    nodes = Document(extensionSet: ExtensionSet.gitHubFlavored).parse(text);
  } on Object {
    return null;
  }
  return _depthOf(nodes) > maxMarkdownDepth ? null : nodes;
}

/// The number of element levels in [nodes], measured without recursion.
int _depthOf(List<Node> nodes) {
  var deepest = 0;
  final pending = <(Node, int)>[for (final node in nodes) (node, 1)];
  while (pending.isNotEmpty) {
    final (node, depth) = pending.removeLast();
    if (node is! Element) continue;
    if (depth > deepest) deepest = depth;
    if (deepest > maxMarkdownDepth) return deepest;
    final children = node.children;
    if (children == null) continue;
    for (final child in children) {
      pending.add((child, depth + 1));
    }
  }
  return deepest;
}
