import 'package:markdown/markdown.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/doc_model/markdown_body.dart';
import 'package:specstone_core/src/index_query/link_scan.dart';

/// A doc link of a doc: the docPath it resolves to, the file line it is
/// written on, and its destination as written.
typedef LinkPlace = ({String target, int line, String shown});

/// Returns the links of [lfBody] that resolve to a `.md` doc other than
/// [docPath], in source order.
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
/// `const []` for a body with no link syntax, which it never parses.
List<LinkPlace>? linkPlacesOf(
  String lfBody, {
  required String docPath,
  required int firstLine,
}) {
  // Exact: a doc link is inline (`](`) or has a `]:` definition; an autolink
  // is absolute, so it never resolves to a doc.
  if (!lfBody.contains('](') && !lfBody.contains(']:')) return const [];
  final hrefs = _hrefsOf(lfBody);
  if (hrefs == null) return null;
  final placed = _placedHrefs(docPath, hrefs);
  final sources = linkSourcesOf(lfBody, firstLine: firstLine);
  if (readersAgree(sources, hrefs)) {
    return [
      for (final (:index, :href, :docPath) in placed)
        (
          target: docPath,
          line: sources[index].line,
          shown: sources[index].shown ?? href,
        ),
    ];
  }
  return _placedByUse(placed, sources);
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
  for (final (:href, :docPath, index: _) in placed) {
    final sameHref = usesOf[href] ?? const <LinkSource>[];
    final nth = taken[href] ?? 0;
    taken[href] = nth + 1;
    final use = nth < sameHref.length ? sameHref[nth] : null;
    places.add((
      target: docPath,
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

/// A placed href together with its index among the hrefs and the doc path it
/// resolved to.
typedef _PlacedHref = ({int index, String href, String docPath});

/// Returns the hrefs [linkPlacesOf] places, each with its index in [hrefs] and
/// the doc path it resolved to.
///
/// Each href resolves exactly once: the caller reads the doc path from here
/// instead of resolving again.
List<_PlacedHref> _placedHrefs(String docPath, List<String> hrefs) {
  final placed = <_PlacedHref>[];
  for (var index = 0; index < hrefs.length; index++) {
    final href = hrefs[index];
    final target = resolveDocLink(href, docPath);
    if (target is! DocTarget ||
        !target.docPath.endsWith('.md') ||
        target.docPath == docPath) {
      continue;
    }
    placed.add((index: index, href: href, docPath: target.docPath));
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

/// Returns the hrefs of the links in [body], in order, or null when `markdown`
/// fails on it.
List<String>? _hrefsOf(String body) {
  final nodes = parseMarkdown(body);
  if (nodes == null) return null;
  final hrefs = <String>[];
  void visit(List<Node> nodes) {
    for (final node in nodes) {
      if (node is! Element) continue;
      final href = node.attributes['href'];
      if (node.tag == 'a' && href != null) hrefs.add(href);
      final children = node.children;
      if (children != null) visit(children);
    }
  }

  visit(nodes);
  return hrefs;
}
