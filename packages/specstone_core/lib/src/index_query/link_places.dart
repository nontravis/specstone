import 'package:markdown/markdown.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/doc_model/markdown_body.dart';
import 'package:specstone_core/src/index_query/link_scan.dart';

/// A link of a doc: the path it resolves to, the file line it is written on,
/// and its destination as written.
///
/// The target is a docPath for a doc link, and the path under the docs root
/// for a file link.
typedef LinkPlace = ({String target, int line, String shown});

/// The links of a doc: the doc links, which resolve to a `.md` doc other than
/// the doc itself, and the file links, every other relative link.
typedef LinkPlaces = ({List<LinkPlace> docLinks, List<LinkPlace> fileLinks});

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
/// no links for a body with no link syntax, which it never parses.
LinkPlaces? linkPlacesOf(
  String lfBody, {
  required String docPath,
  required int firstLine,
}) {
  // Exact: a doc link is inline (`](`) or has a `]:` definition; an autolink
  // is absolute, so it never resolves to a doc.
  if (!lfBody.contains('](') && !lfBody.contains(']:')) {
    return (docLinks: const [], fileLinks: const []);
  }
  final hrefs = _hrefsOf(lfBody);
  if (hrefs == null) return null;
  final placed = _placedHrefs(docPath, hrefs);
  final sources = linkSourcesOf(lfBody, firstLine: firstLine);
  final places = readersAgree(sources, hrefs)
      ? [
          for (final (:index, :href, :target, isFile: _) in placed)
            (
              target: target,
              line: sources[index].line,
              shown: sources[index].shown ?? href,
            ),
        ]
      : _placedByUse(placed, sources);
  return (
    docLinks: [
      for (final (i, place) in places.indexed)
        if (!placed[i].isFile) place,
    ],
    fileLinks: [
      for (final (i, place) in places.indexed)
        if (placed[i].isFile) place,
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
  for (final (:href, :target, index: _, isFile: _) in placed) {
    final sameHref = usesOf[href] ?? const <LinkSource>[];
    final nth = taken[href] ?? 0;
    taken[href] = nth + 1;
    final use = nth < sameHref.length ? sameHref[nth] : null;
    places.add((
      target: target,
      line: use?.line ?? 1,
      shown: use?.shown ?? href,
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

/// A placed href together with its index among the hrefs, the path it
/// resolved to, and whether that path is a file link, not a doc link.
typedef _PlacedHref = ({int index, String href, String target, bool isFile});

/// Returns the hrefs [linkPlacesOf] places, each with its index in [hrefs],
/// the path it resolved to, and its class.
///
/// A link to a `.md` doc other than [docPath] is a doc link; a link to
/// [docPath] itself, an empty path, a web address, another scheme, and a
/// rooted path are left out; every other relative link is a file link.
///
/// Each href resolves exactly once: the caller reads the path from here
/// instead of resolving again.
List<_PlacedHref> _placedHrefs(String docPath, List<String> hrefs) {
  final placed = <_PlacedHref>[];
  for (var index = 0; index < hrefs.length; index++) {
    final href = hrefs[index];
    final target = resolveDocLink(href, docPath);
    if (target is DocTarget && target.docPath.endsWith('.md')) {
      if (target.docPath == docPath) continue;
      placed.add((
        index: index,
        href: href,
        target: target.docPath,
        isFile: false,
      ));
      continue;
    }
    final filePath = relativeFilePathOf(href, docPath);
    if (filePath == null) continue;
    placed.add((index: index, href: href, target: filePath, isFile: true));
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
/// `markdown` fails on it.
List<String>? _hrefsOf(String body) {
  final nodes = parseMarkdown(body);
  if (nodes == null) return null;
  final hrefs = <String>[];
  void visit(List<Node> nodes) {
    for (final node in nodes) {
      if (node is! Element) continue;
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
