import 'package:markdown/markdown.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/doc_model/markdown_body.dart';
import 'package:specstone_core/src/doc_model/models/destination_kind.dart';
import 'package:specstone_core/src/doc_model/models/source_order_nodes.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show parsedDestinationOf;
import 'package:specstone_core/src/index_query/link_scan.dart';
import 'package:specstone_core/src/index_query/models/link_scan.dart';
import 'package:specstone_core/src/index_query/models/link_source.dart';
import 'package:specstone_core/src/index_query/models/scanned_destination.dart';

/// The syntax that makes `markdown`'s link elements, whose href it decodes.
final _linkSyntax = LinkSyntax();

/// A link of a doc: the path it resolves to, the file line it is written on,
/// its destination as written, and its decoded `#anchor`, null with no `#`.
///
/// The target is a docPath for a doc link and a self link, and the path under
/// the docs root for a file link.
typedef LinkPlace = ({String target, int line, String shown, String? anchor});

/// A doc link or self link whose text reads as an item ID:
/// the text as written, where the link sits, and what it points at.
///
/// `column` is the 0-based offset of the link's first character in its line
/// `line`; `endColumn` the offset after its last character in its line
/// `endLine`, so a reader tests what lies between two links on one line. A
/// link text reads as an item ID when it holds no whitespace and a digit; the
/// reader that knows the target section's prefix judges it. `shown` is the
/// link's destination as written, the `shown` of its [LinkPlace].
typedef LinkText = ({
  int line,
  int column,
  int endLine,
  int endColumn,
  String text,
  String target,
  String? anchor,
  String shown,
});

/// The links of a doc: the doc links, which resolve to a `.md` doc other than
/// the doc itself, the file links, every other relative link, the self links,
/// which name the doc itself, a bare `#anchor` included; the [LinkText] of
/// each doc link and self link the scan placed; and whether the scan and
/// `markdown` agree on them (see [readersAgree]), without which a move, the
/// see rule, and the renumber pass read no href of an inline link.
typedef LinkPlaces = ({
  List<LinkPlace> docLinks,
  List<LinkPlace> fileLinks,
  List<LinkPlace> selfLinks,
  List<LinkText> texts,
  bool readersAgree,
});

/// The links of a body that holds no link syntax: none of any class.
const LinkPlaces noLinks = (
  docLinks: [],
  fileLinks: [],
  selfLinks: [],
  texts: [],
  readersAgree: true,
);

/// Returns, for each of [places], the [LinkText] in [stored] that is its own,
/// or null when the index keeps none.
///
/// A stored text joins the nth place of its line, target, anchor, and
/// destination as written, so each link is read once.
List<LinkText?> storedLinkTextsOf(
  List<LinkPlace> places,
  List<LinkText> stored,
) {
  final texts = <(int, String, String?, String), List<LinkText>>{};
  for (final text in stored) {
    (texts[(text.line, text.target, text.anchor, text.shown)] ??= []).add(text);
  }
  final taken = <(int, String, String?, String), int>{};
  return [
    for (final place in places)
      _nthStoredText(texts, taken, (
        place.line,
        place.target,
        place.anchor,
        place.shown,
      )),
  ];
}

LinkText? _nthStoredText(
  Map<(int, String, String?, String), List<LinkText>> texts,
  Map<(int, String, String?, String), int> taken,
  (int, String, String?, String) key,
) {
  final nth = taken[key] ?? 0;
  taken[key] = nth + 1;
  final found = texts[key];
  return found != null && nth < found.length ? found[nth] : null;
}

/// Returns the [LinkText] of [place] when the index keeps no text for it: an
/// empty text, which reads as no item ID.
LinkText textFreeLinkOf(LinkPlace place) => (
  line: place.line,
  column: 0,
  endLine: place.line,
  endColumn: 0,
  text: '',
  target: place.target,
  anchor: place.anchor,
  shown: place.shown,
);

/// Returns the links of [lfBody], doc links and file links, each in source
/// order.
///
/// [lfBody] is the doc text after the frontmatter, with LF line ends, and
/// [firstLine] is its first file line. `markdown` decides which links exist.
/// Each is then placed in the source text for its line and its destination as
/// written: the scan reads the links by CommonMark's bracket procedure (see
/// [linkSourcesOf]). When the scan and `markdown` agree on the links (see
/// [readersAgree]), the nth link takes the nth source, so no other link moves
/// it. Otherwise the nth link to an href takes the nth use of that href. A link
/// the scan cannot place takes line 1 and the href `markdown` gives as its
/// destination.
///
/// Returns null when `markdown` fails on [lfBody] (see [parseMarkdown]), and
/// [noLinks] for a body with no link syntax, which it never parses. Given
/// [tree], the tree either `parseMarkdownTree` or `parseMarkdownTreeByBlock`
/// gives [lfBody], the caller has passed that gate, so it is not run again.
LinkPlaces? linkPlacesOf(
  String lfBody, {
  required String docPath,
  required int firstLine,
  MarkdownTree? tree,
}) {
  if (tree == null && !holdsLinkSyntax(lfBody)) return noLinks;
  final hrefs = _hrefsOf(lfBody, tree: tree);
  if (hrefs == null) return null;
  final placed = _placedHrefs(docPath, hrefs);
  final sources = linkSourcesOf(lfBody, firstLine: firstLine);
  final agree = readersAgree(sources, hrefs);
  final located = agree
      ? [
          for (final (:index, :href, :target, kind: _, :anchor) in placed)
            (
              place: (
                target: target,
                line: sources[index].line,
                shown: sources[index].shown ?? href,
                anchor: anchor,
              ),
              source: sources[index],
            ),
        ]
      : _placedByUse(placed, sources);
  List<LinkPlace> placesOf(_LinkKind kind) => [
    for (final (i, (:place, source: _)) in located.indexed)
      if (placed[i].kind == kind) place,
  ];
  return (
    docLinks: placesOf(_LinkKind.doc),
    fileLinks: placesOf(_LinkKind.file),
    selfLinks: placesOf(_LinkKind.self),
    texts: [
      for (final (i, (:place, :source)) in located.indexed)
        if (placed[i].kind == _LinkKind.doc || placed[i].kind == _LinkKind.self)
          if (source != null) ?_linkTextOf(lfBody, source, place),
    ],
    readersAgree: agree,
  );
}

/// A place together with the source it was read from, null when the scan
/// found none for it.
typedef _Located = ({LinkPlace place, LinkSource? source});

/// Returns the places of [placed], each href taking its nth use among the
/// destinations of [sources], or line 1 when it has no nth use.
List<_Located> _placedByUse(
  List<_PlacedHref> placed,
  List<LinkSource> sources,
) {
  final uses = _usesByHref([for (final p in placed) p.href], sources);
  return [
    for (final (i, (:href, :target, :anchor, index: _, kind: _))
        in placed.indexed)
      (
        place: (
          target: target,
          line: uses[i]?.line ?? 1,
          shown: uses[i]?.shown ?? href,
          anchor: anchor,
        ),
        source: uses[i],
      ),
  ];
}

/// Returns the source each of [hrefs] takes, the nth occurrence of an href
/// taking the nth source whose destination, normalized, is that href, or null
/// when it has no nth use.
List<LinkSource?> _usesByHref(List<String> hrefs, List<LinkSource> sources) {
  final usesOf = <String, List<LinkSource>>{};
  for (final source in sources) {
    final shown = source.shown;
    if (shown != null) {
      usesOf.putIfAbsent(_normalize(shown), () => []).add(source);
    }
  }
  final taken = <String, int>{};
  final uses = <LinkSource?>[];
  for (final href in hrefs) {
    final sameHref = usesOf[href] ?? const <LinkSource>[];
    final nth = taken[href] ?? 0;
    taken[href] = nth + 1;
    uses.add(nth < sameHref.length ? sameHref[nth] : null);
  }
  return uses;
}

/// Returns the [sources] `markdown` reads as a link or an image, given [tree],
/// its parse of the body [sources] come from.
///
/// When the scan and `markdown` agree (see [readersAgree]) the nth source is
/// the nth link, a null href, a link in a footnote definition `markdown`
/// drops, leaving it out. Otherwise each href takes its nth use, as
/// [linkPlacesOf] places it, and a link the scan lists that no href takes is
/// left out.
List<LinkSource> parserReadSourcesOf(
  List<LinkSource> sources,
  MarkdownTree tree,
) {
  final hrefs = _hrefsIn(tree.inSourceOrder);
  if (readersAgree(sources, hrefs)) {
    return [
      for (final (i, source) in sources.indexed)
        if (hrefs[i] != null) source,
    ];
  }
  final read = [for (final href in hrefs) ?href];
  return [for (final use in _usesByHref(read, sources)) ?use];
}

/// The text of a link whose text holds no whitespace and a digit.
final _itemIdShapedText = RegExp(r'^\S*\d\S*$');

/// Returns the [LinkText] of [place], which [source] is the use of in
/// [lfBody], or null for an image, a link with no bracketed text, and a text
/// that cannot read as an item ID.
LinkText? _linkTextOf(String lfBody, LinkSource source, LinkPlace place) {
  final textEnd = source.textEnd;
  final offset = source.offset;
  final end = source.end;
  if (textEnd == null || lfBody.codeUnitAt(offset) == _bang) return null;
  final text = lfBody.substring(offset + 1, textEnd);
  if (!_itemIdShapedText.hasMatch(text)) return null;
  return (
    line: source.line,
    column: offset - _lineStartAt(lfBody, offset),
    endLine: source.line + _lineFeeds(lfBody, offset, end),
    endColumn: end - _lineStartAt(lfBody, end),
    text: text,
    target: place.target,
    anchor: place.anchor,
    shown: place.shown,
  );
}

const _bang = 0x21;
const _lineFeed = 0x0A;

/// Returns the offset of the first character of the line that holds [offset]
/// in [text], or, when [offset] ends a line, of the line it closes.
int _lineStartAt(String text, int offset) =>
    offset == 0 ? 0 : text.lastIndexOf('\n', offset - 1) + 1;

int _lineFeeds(String text, int from, int to) {
  var count = 0;
  for (var i = from; i < to; i++) {
    if (text.codeUnitAt(i) == _lineFeed) count++;
  }
  return count;
}

/// Returns whether [sources] and [hrefs] describe the same links: equal
/// counts, and each source whose destination holds no `\` and no `&` has the
/// normalized destination `markdown` gives as its href, where it gives one.
bool readersAgree(List<LinkSource> sources, List<String?> hrefs) {
  if (sources.length != hrefs.length) return false;
  for (var i = 0; i < sources.length; i++) {
    final (shown, href) = (sources[i].shown, hrefs[i]);
    if (shown == null || href == null) continue;
    if (shown.contains(r'\') || shown.contains('&')) continue;
    if (_normalize(shown) != href) return false;
  }
  return true;
}

/// Returns the href `markdown` gives the link of each of [sources], the link
/// sources of [lfBody], by index: the nth href for the nth source, null for a
/// link in a footnote definition `markdown` drops (see [_hrefsOf]).
///
/// Null when `markdown` fails on [lfBody] or the readers disagree (see
/// [readersAgree]), so no href is known for any source.
List<String?>? sourceHrefsOf(String lfBody, List<LinkSource> sources) {
  if (sources.isEmpty) return const [];
  final hrefs = _hrefsOf(lfBody);
  return hrefs != null && readersAgree(sources, hrefs) ? hrefs : null;
}

/// A link destination as written, by its body range, the href `markdown`
/// gives it, and how `markdown` reads it.
typedef HrefDestination = ({
  int start,
  int end,
  String href,
  DestinationKind kind,
});

/// The destinations of a link scan that have an href, and whether `markdown`
/// read the links: false when it fails on the body, which leaves every
/// destination without one, or the readers disagree (see [readersAgree]),
/// which leaves each inline link's without one; true when no destination
/// needed the read.
typedef HrefDestinations = ({
  List<HrefDestination> destinations,
  bool linksRead,
});

/// Returns each destination of [scan], the link scan of [lfBody], that has an
/// href [canMove] holds for, with that href, in [scan]'s order.
///
/// An inline link's destination takes the href of its link (see
/// [sourceHrefsOf]); one in an image description, which is no link, or in a
/// footnote definition `markdown` drops takes none. A definition's destination
/// takes the href `markdown` gives a link to a definition whose destination is
/// written so.
///
/// The body is parsed only when some destination, read from its own text,
/// has an href [canMove] holds for: context takes a link away, so the read
/// never misses a move. Only in a GFM table cell can context change an href
/// (`p\\\|q.md`); the gate holds there, since a moved segment matches
/// `[a-z0-9_]+` and a slug holds no `|`.
HrefDestinations hrefDestinationsOf(
  String lfBody,
  LinkScan scan, {
  required bool Function(String href) canMove,
}) {
  final movable = [
    for (final destination in scan.destinations)
      if (_writtenHrefOf(lfBody, destination) case final href?
          when canMove(href))
        destination,
  ];
  if (movable.isEmpty) return (destinations: [], linksRead: true);
  final tree = parseMarkdownTree(lfBody);
  if (tree == null) return (destinations: [], linksRead: false);
  final hrefs = _hrefsIn(tree.inSourceOrder);
  final linkHrefs = readersAgree(scan.sources, hrefs) ? hrefs : null;
  final definitionHrefs = {
    for (final LinkReference(:destination) in tree.definitions.values)
      destination: _hrefOfLink(destination),
  };
  String? hrefOf(ScannedDestination destination) {
    final ScannedDestination(:start, :end, :link, :kind) = destination;
    if (kind == DestinationKind.definition) {
      return definitionHrefs[lfBody.substring(start, end)];
    }
    return link == null ? null : linkHrefs?[link];
  }

  return (
    destinations: [
      for (final destination in movable)
        if (hrefOf(destination) case final href?)
          (
            start: destination.start,
            end: destination.end,
            href: href,
            kind: destination.kind,
          ),
    ],
    linksRead: linkHrefs != null,
  );
}

/// Returns the href `markdown` gives a link written with [destination], read
/// from its text in [lfBody] alone.
String? _writtenHrefOf(String lfBody, ScannedDestination destination) =>
    _hrefOfLink(
      parsedDestinationOf(
        lfBody.substring(destination.start, destination.end),
        destination.kind,
      ),
    );

/// Returns the href `markdown` gives a link whose destination it read as
/// [destination], escapes kept.
String? _hrefOfLink(String destination) {
  final node = _linkSyntax.createNode(
    destination,
    null,
    getChildren: () => const [],
  );
  return node is Element ? node.attributes['href'] : null;
}

/// The class a placed href falls into.
enum _LinkKind { doc, file, self }

/// A placed href together with its index among the hrefs, the path it
/// resolved to, its class, and its decoded anchor.
typedef _PlacedHref = ({
  int index,
  String href,
  String target,
  _LinkKind kind,
  String? anchor,
});

/// Returns the hrefs [linkPlacesOf] places, each with its index in [hrefs],
/// the path it resolved to, and its class.
///
/// A link to a `.md` doc other than [docPath] is a doc link; a link to
/// [docPath] itself is a self link, a bare `#anchor` and an empty path with
/// no anchor (`[x]()`, `[x](?q)`) included; a web address, another scheme, and
/// a rooted path are left out; every other relative link is a file link.
///
/// Each href resolves exactly once: the caller reads the path from here
/// instead of resolving again. A null href, a link `markdown` drops, is no
/// link of the doc.
List<_PlacedHref> _placedHrefs(String docPath, List<String?> hrefs) {
  final placed = <_PlacedHref>[];
  for (var index = 0; index < hrefs.length; index++) {
    final href = hrefs[index];
    if (href == null) continue;
    final target = resolveDocLink(href, docPath);
    if (target is DocTarget && target.docPath.endsWith('.md')) {
      final kind = target.docPath == docPath ? _LinkKind.self : _LinkKind.doc;
      placed.add((
        index: index,
        href: href,
        target: target.docPath,
        kind: kind,
        anchor: target.anchor,
      ));
      continue;
    }
    final filePath = relativeFilePathOf(href, docPath);
    if (filePath == null) continue;
    placed.add((
      index: index,
      href: href,
      target: filePath,
      kind: _LinkKind.file,
      anchor: null,
    ));
  }
  return placed;
}

/// Mirrors `markdown`'s link destination normalization: percent-escapes stay,
/// the rest is percent-encoded.
String _normalize(String dest) => dest.splitMapJoin(
  RegExp('%[0-9A-Fa-f]{2}'),
  onMatch: (m) => m.group(0)!,
  onNonMatch: Uri.encodeFull,
);

/// Returns the hrefs of the links and images in [body], in source order, or
/// null when `markdown` fails on it; [tree], when given, is the tree either
/// `parseMarkdownTree` or `parseMarkdownTreeByBlock` gives [body], so it is
/// parsed once.
///
/// Each link of a footnote definition is read where the definition is
/// written; one in a definition `markdown` drops, which no reference names,
/// has no href and stands as null, so each link the text holds keeps its
/// place. The links `markdown` makes for a footnote are left out: the author
/// wrote neither the reference's link nor the back link.
List<String?>? _hrefsOf(String body, {MarkdownTree? tree}) {
  final parsed = tree ?? parseMarkdownTree(body);
  return parsed == null ? null : _hrefsIn(parsed.inSourceOrder);
}

/// Returns the hrefs of the links and images of [tree], in order, null for
/// each in a dropped node (see [_hrefsOf]).
List<String?> _hrefsIn(SourceOrderNodes tree) {
  final hrefs = <String?>[];
  void visit(List<Node> nodes, {required bool rendered}) {
    for (final node in nodes) {
      if (node is! Element || _isFootnoteMade(node)) continue;
      final isRendered = rendered && !tree.dropped.contains(node);
      final href = switch (node.tag) {
        'a' => node.attributes['href'],
        'img' => node.attributes['src'],
        _ => null,
      };
      if (href != null) hrefs.add(isRendered ? href : null);
      final children = node.children;
      if (children != null) visit(children, rendered: isRendered);
    }
  }

  visit(tree.nodes, rendered: true);
  return hrefs;
}

/// Whether `markdown` made [element] for a footnote: the `sup` that holds a
/// footnote reference's link, or a footnote's back link.
bool _isFootnoteMade(Element element) =>
    switch ((element.tag, element.attributes['class'])) {
      ('sup', 'footnote-ref') || ('a', 'footnote-backref') => true,
      _ => false,
    };
