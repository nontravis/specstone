import 'package:markdown/markdown.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/doc_model/markdown_body.dart';
import 'package:specstone_core/src/index_query/link_scan.dart';

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
/// links, whose target the grammar cannot read.
typedef LinkPlaces = ({
  List<LinkPlace> docLinks,
  List<LinkPlace> fileLinks,
  List<LinkPlace> selfLinks,
  List<LinkPlace> unreadableLinks,
});

/// The links of a body that holds no link syntax: none of any class.
const LinkPlaces noLinks = (
  docLinks: [],
  fileLinks: [],
  selfLinks: [],
  unreadableLinks: [],
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
/// [bodyNodes], the caller has passed that gate, so it is not run again.
LinkPlaces? linkPlacesOf(
  String lfBody, {
  required String docPath,
  required int firstLine,
  List<Node>? bodyNodes,
}) {
  if (bodyNodes == null && !holdsLinkSyntax(lfBody)) return noLinks;
  final hrefs = _hrefsOf(lfBody, bodyNodes: bodyNodes);
  if (hrefs == null) return null;
  final placed = _placedHrefs(docPath, hrefs);
  final sources = linkSourcesOf(lfBody, firstLine: firstLine);
  final places = readersAgree(sources, hrefs)
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
/// normalized destination `markdown` gives as its href.
bool readersAgree(List<LinkSource> sources, List<String> hrefs) {
  if (sources.length != hrefs.length) return false;
  for (var i = 0; i < sources.length; i++) {
    final shown = sources[i].shown;
    if (shown == null || shown.contains(r'\') || shown.contains('&')) continue;
    if (_normalize(shown) != hrefs[i]) return false;
  }
  return true;
}

/// Returns the href `markdown` makes of a link destination written as
/// [shown], inside angle brackets when [angle], or null when that makes no
/// one link.
///
/// The href is the destination decoded as every link href is: backslash
/// escapes and entity references read, the rest percent-encoded.
String? hrefOfSpelling(String shown, {required bool angle}) {
  final hrefs = _hrefsOf(angle ? '[x](<$shown>)' : '[x]($shown)');
  return hrefs != null && hrefs.length == 1 ? hrefs.single : null;
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
/// instead of resolving again.
List<_PlacedHref> _placedHrefs(String docPath, List<String> hrefs) {
  final placed = <_PlacedHref>[];
  for (var index = 0; index < hrefs.length; index++) {
    final href = hrefs[index];
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

/// Returns the hrefs of the links and images in [body], in order, or null when
/// `markdown` fails on it; [bodyNodes], when given, are `parseMarkdown(body)`'s
/// nodes, so they are parsed once.
///
/// The links `markdown` makes for a footnote are left out: the author wrote
/// neither the reference's link nor the back link.
List<String>? _hrefsOf(String body, {List<Node>? bodyNodes}) {
  final nodes = bodyNodes ?? parseMarkdown(body);
  if (nodes == null) return null;
  final hrefs = <String>[];
  void visit(List<Node> nodes) {
    for (final node in nodes) {
      if (node is! Element || _isFootnoteMade(node)) continue;
      final href = switch (node.tag) {
        'a' => node.attributes['href'],
        'img' => node.attributes['src'],
        _ => null,
      };
      if (href != null) hrefs.add(href);
      final children = node.children;
      if (children != null) visit(children);
    }
  }

  visit(nodes);
  return hrefs;
}

/// Whether `markdown` made [element] for a footnote: the `sup` that holds a
/// footnote reference's link, or a footnote's back link.
bool _isFootnoteMade(Element element) =>
    switch ((element.tag, element.attributes['class'])) {
      ('sup', 'footnote-ref') || ('a', 'footnote-backref') => true,
      _ => false,
    };
