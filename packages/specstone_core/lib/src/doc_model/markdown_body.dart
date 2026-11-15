import 'dart:convert';

import 'package:markdown/markdown.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show schemeEndOf;

/// The deepest tree [parseMarkdown] returns, counted in element levels from a
/// top-level node (a paragraph is level 1), and the deepest container the
/// link scan's block pass reads (`leafTextOf`).
///
/// Every consumer of the nodes walks them recursively: the link walkers and
/// the `markdown` package's `renderToHtml`. Those overflow the stack near
/// 15,000 levels, the parse itself near 4,100, and the block pass between
/// 1,500 and 2,000. A bound of 1,000 sits below all three, and no real doc
/// nests that deep.
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
/// gets null treats the doc as one it can read no links from and goes on.
List<Node>? parseMarkdown(String text) => parseMarkdownTree(text)?.nodes;

/// Nodes `markdown` parses a text into, in source order, and the top-level
/// footnote definitions among them that it drops (see [MarkdownTree]).
typedef SourceOrderNodes = ({List<Node> nodes, Set<Node> dropped});

/// What `markdown` parses a text into: the nodes it renders, the link
/// reference definitions it reads, keyed by normalized label, and the nodes in
/// source order.
final class MarkdownTree {
  new _(
    this._text,
    this.nodes,
    this.definitions, {
    required bool definesFootnote,
  }) : _definesFootnote = definesFootnote;

  final String _text;
  final bool _definesFootnote;

  /// The nodes [parseMarkdown] returns.
  final List<Node> nodes;

  final Map<String, LinkReference> definitions;

  /// [nodes] with each top-level footnote definition where it is written.
  ///
  /// `markdown` moves each one a reference names into a trailing section, in
  /// first-reference order, and drops the rest (`Document.parseLineList`).
  /// Here every one stays in place, and the dropped ones are named, so a
  /// reader in source order meets each link where the text holds it.
  late final SourceOrderNodes inSourceOrder = _definesFootnote
      ? _inSourceOrder(_text, nodes)
      : (nodes: nodes, dropped: const {});
}

/// Returns the [MarkdownTree] of [text], or null when [parseMarkdown] fails on
/// it.
MarkdownTree? parseMarkdownTree(String text) {
  final Document document;
  final List<Node> nodes;
  try {
    document = Document(extensionSet: ExtensionSet.gitHubFlavored);
    nodes = document.parse(text);
  } on Object {
    return null;
  }
  if (_depthOf(nodes) > maxMarkdownDepth) return null;
  return MarkdownTree._(
    text,
    nodes,
    document.linkReferences,
    definesFootnote: document.footnoteReferences.isNotEmpty,
  );
}

/// Returns the [MarkdownTree] of [text] with the inline pass run only where a
/// link or an anchor can come from, or null where [parseMarkdownTree] gives
/// null for the same text.
///
/// A heading is always parsed, since the anchor set reads its text. Any other
/// block is parsed when its text holds `[`, `<`, `@`, `://`, or `www.`, the
/// starts of every inline link, autolink, and raw tag `markdown` reads; every
/// other block keeps its `UnparsedContent`. The block pass runs first on the
/// whole text, so a link reference definition resolves in any block. A text
/// that defines a footnote gets the full parse, which moves and drops its
/// footnote definitions by the references it counts.
///
/// A tree the full parse finds too deep only through inline nesting, in
/// blocks this pass leaves unparsed, comes back whole.
MarkdownTree? parseMarkdownTreeByBlock(String text) {
  final Document document;
  final List<Node> nodes;
  try {
    document = Document(extensionSet: ExtensionSet.gitHubFlavored);
    nodes = BlockParser(
      LineSplitter.split(text).map(Line.new).toList(),
      document,
    ).parseLines();
    if (document.footnoteReferences.isNotEmpty) return parseMarkdownTree(text);
    _parseInlineWhereGated(document, nodes, inHeading: false);
  } on Object {
    return null;
  }
  if (_depthOf(nodes) > maxMarkdownDepth) return null;
  return MarkdownTree._(
    text,
    nodes,
    document.linkReferences,
    definesFootnote: false,
  );
}

/// Runs [document]'s inline pass on the unparsed content of [nodes] that is
/// in a heading or whose text can start a link or an anchor.
void _parseInlineWhereGated(
  Document document,
  List<Node> nodes, {
  required bool inHeading,
}) {
  for (var i = 0; i < nodes.length; i++) {
    final node = nodes[i];
    if (node is UnparsedContent) {
      if (!inHeading && !_canStartInline(node.textContent)) continue;
      final inline = document.parseInline(node.textContent);
      nodes
        ..removeAt(i)
        ..insertAll(i, inline);
      i += inline.length - 1;
    } else if (node is Element && node.children != null) {
      _parseInlineWhereGated(
        document,
        node.children!,
        inHeading: inHeading || _isHeadingTag(node.tag),
      );
    }
  }
}

/// The starts of syntax the inline pass reads into a link or an anchor: `[`
/// (inline, reference, and footnote links), `<` (autolink and raw tag), `@`
/// (email autolink), `://` (bare web autolink), and `www.`; the bare web
/// autolink reads in any case.
final _inlineStart = RegExp(r'[\[<@]|://|www\.', caseSensitive: false);

bool _canStartInline(String text) => _inlineStart.hasMatch(text);

/// Returns the nodes of [text] in source order, as `markdown` builds them
/// before it moves its footnote definitions, or [rendered], its parse of
/// [text], when that build throws.
///
/// The build is `Document.parseLineList` short of its footnote step: the block
/// pass, then the inline pass on each node's unparsed content. A top-level
/// footnote definition no reference names is dropped, as there.
SourceOrderNodes _inSourceOrder(String text, List<Node> rendered) {
  final Document document;
  final List<Node> nodes;
  try {
    document = Document(extensionSet: ExtensionSet.gitHubFlavored);
    nodes = BlockParser(
      LineSplitter.split(text).map(Line.new).toList(),
      document,
    ).parseLines();
    _parseInline(document, nodes);
  } on Object {
    // The same text parsed once; a throw here leaves the rendered order.
    return (nodes: rendered, dropped: const {});
  }
  final references = document.footnoteReferences;
  return (
    nodes: nodes,
    dropped: Set.identity()
      ..addAll([
        for (final node in nodes)
          if (node is Element &&
              node.tag == 'li' &&
              references.containsKey(node.footnoteLabel) &&
              (references[node.footnoteLabel] ?? 0) == 0)
            node,
      ]),
  );
}

/// Runs [document]'s inline pass on the unparsed content of [nodes], as
/// `Document.parseLineList` does.
void _parseInline(Document document, List<Node> nodes) {
  for (var i = 0; i < nodes.length; i++) {
    final node = nodes[i];
    if (node is UnparsedContent) {
      final inline = document.parseInline(node.textContent);
      nodes
        ..removeAt(i)
        ..insertAll(i, inline);
      i += inline.length - 1;
    } else if (node is Element && node.children != null) {
      _parseInline(document, node.children!);
    }
  }
}

/// Whether [body] holds the least syntax a markdown link needs: an inline
/// opener (`](`), a definition opener (`]:`), or a scheme autolink opener
/// (`<` and a scheme).
///
/// A scheme autolink never resolves to a doc, but the grammar may fail to
/// read it, so it passes too. A body that fails it is never read for links
/// and never warns of its links: the index (`LineFacts.of`), `linkPlacesOf`
/// with no tree, the cite candidates, and the item words all start here.
bool holdsLinkSyntax(String body) =>
    body.contains('](') || body.contains(']:') || _holdsSchemeAutolink(body);

bool _holdsSchemeAutolink(String body) {
  for (var at = body.indexOf('<'); at >= 0; at = body.indexOf('<', at + 1)) {
    if (schemeEndOf(body, at + 1) > 0) return true;
  }
  return false;
}

/// Whether [tag] is `h1` through `h6`.
bool _isHeadingTag(String tag) =>
    tag.length == 2 &&
    tag.codeUnitAt(0) == 0x68 &&
    tag.codeUnitAt(1) >= 0x31 &&
    tag.codeUnitAt(1) <= 0x36;

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
