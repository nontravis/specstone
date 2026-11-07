import 'package:markdown/markdown.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/doc_model/markdown_body.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show DestinationKind, parsedDestinationOf;
import 'package:specstone_core/src/index_query/link_scan.dart';

/// The syntax that makes `markdown`'s link elements, whose href it decodes.
final _linkSyntax = LinkSyntax();

/// A link of a doc: the path it resolves to, the file line it is written on,
/// its destination as written, and its decoded `#anchor`, null with no `#`.
///
/// The target is a docPath for a doc link and a self link, and the path under
/// the docs root for a file link; an unreadable link's target is its href as
/// written.
typedef LinkPlace = ({String target, int line, String shown, String? anchor});

/// The links of a doc: the doc links, which resolve to a `.md` doc other than
/// the doc itself, the file links, every other relative link, the self links,
/// which name the doc itself, a bare `#anchor` included, and the unreadable
/// links, whose target the grammar cannot read; and whether the scan and
/// `markdown` agree on them (see [readersAgree]), without which a move, the
/// see rule, and the renumber pass read no href of an inline link.
typedef LinkPlaces = ({
  List<LinkPlace> docLinks,
  List<LinkPlace> fileLinks,
  List<LinkPlace> selfLinks,
  List<LinkPlace> unreadableLinks,
  bool readersAgree,
});

/// The links of a body that holds no link syntax: none of any class.
const LinkPlaces noLinks = (
  docLinks: [],
  fileLinks: [],
  selfLinks: [],
  unreadableLinks: [],
  readersAgree: true,
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
/// [tree], `parseMarkdownTree(lfBody)`, the caller has passed that gate, so it
/// is not run again.
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
  final places = agree
      ? [
          for (final (:index, :href, :target, kind: _, :anchor) in placed)
            (
              target: target,
              line: sources[index].line,
              shown: sources[index].shown ?? href,
              anchor: anchor,
            ),
        ]
      : _placedByUse(placed, sources);
  return (
    docLinks: [
      for (final (i, place) in places.indexed)
        if (placed[i].kind == _LinkKind.doc) place,
    ],
    fileLinks: [
      for (final (i, place) in places.indexed)
        if (placed[i].kind == _LinkKind.file) place,
    ],
    selfLinks: [
      for (final (i, place) in places.indexed)
        if (placed[i].kind == _LinkKind.self) place,
    ],
    unreadableLinks: [
      for (final (i, place) in places.indexed)
        if (placed[i].kind == _LinkKind.unreadable) place,
    ],
    readersAgree: agree,
  );
}

/// Returns the places of [placed], each href taking its nth use among the
/// destinations of [sources], or line 1 when it has no nth use.
List<LinkPlace> _placedByUse(
  List<_PlacedHref> placed,
  List<LinkSource> sources,
) {
  final usesOf = <String, List<LinkSource>>{};
  for (final source in sources) {
    final shown = source.shown;
    if (shown != null) {
      usesOf.putIfAbsent(_normalize(shown), () => []).add(source);
    }
  }
  final places = <LinkPlace>[];
  final taken = <String, int>{};
  for (final (:href, :target, :anchor, index: _, kind: _) in placed) {
    final sameHref = usesOf[href] ?? const <LinkSource>[];
    final nth = taken[href] ?? 0;
    taken[href] = nth + 1;
    final use = nth < sameHref.length ? sameHref[nth] : null;
    places.add((
      target: target,
      line: use?.line ?? 1,
      shown: use?.shown ?? href,
      anchor: anchor,
    ));
  }
  return places;
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
/// has an href [canMove] holds for: a link takes that href or none, since
/// context only takes a link away, so the read never misses a move.
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
    final (:start, :end, :link, :kind) = destination;
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
enum _LinkKind { doc, file, self, unreadable }

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
/// no anchor (`[x]()`, `[x](?q)`) included; a link whose target the grammar
/// cannot read is an unreadable link, its target the href as written; a web
/// address, another scheme, and a rooted path are left out; every other
/// relative link is a file link.
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
    if (target is UnreadableTarget) {
      placed.add((
        index: index,
        href: href,
        target: href,
        kind: _LinkKind.unreadable,
        anchor: null,
      ));
      continue;
    }
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
/// null when `markdown` fails on it; [tree], when given, is
/// `parseMarkdownTree(body)`, so it is parsed once.
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
