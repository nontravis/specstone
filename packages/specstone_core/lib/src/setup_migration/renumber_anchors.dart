import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_anchors.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/doc_model/markdown_body.dart'
    show parseLinkFreeBody;
import 'package:specstone_core/src/index_query/link_scan.dart';
import 'package:specstone_core/src/setup_migration/renumber_doc.dart';

// MARK: - Constants

final _setextUnderline = RegExp(r'^ {0,3}(?:=+|-+)[ \t]*$');

// MARK: - Types

/// Per DocPath, each heading slug the pass changes and the slug after it.
final class SlugMoves {
  new(this.byDoc);

  final Map<String, Map<String, String>> byDoc;

  /// Each old slug, as written and escaped, the one gate of every doc.
  late final Set<String> _oldSlugs = {
    for (final moved in byDoc.values)
      for (final slug in moved.keys) ...[slug, Uri.encodeComponent(slug)],
  };

  bool get isEmpty => byDoc.isEmpty;

  /// Whether [lf] holds an old slug, as written or escaped.
  bool mayName(String lf) => _oldSlugs.any(lf.contains);
}

/// A doc's text after the anchors of its links moved, and whether one of
/// them names another doc.
typedef AnchorRewrite = ({String lf, bool citesOthers});

// MARK: - Slug moves

/// Returns, per doc of [docs] whose heading text the body rewrite changed,
/// each old heading slug and the slug its heading has after, by heading
/// position (W3).
///
/// [rewritten] holds the text after the body rewrite of each doc it changed.
SlugMoves slugMovesOf(
  Iterable<RenumberDoc> docs,
  Map<String, String> rewritten,
) {
  final moves = <String, Map<String, String>>{};
  for (final doc in docs) {
    final text = rewritten[doc.docPath];
    if (text == null || !_changesAHeading(doc.lines, text.split('\n'))) {
      continue;
    }
    final bodyStart = doc.frontmatterText.length;
    final before = _headingSlugsOf(doc.lf.substring(bodyStart));
    final after = _headingSlugsOf(text.substring(bodyStart));
    if (before == null || after == null || before.length != after.length) {
      continue;
    }
    final moved = {
      for (var i = 0; i < before.length; i++)
        if (before[i] != after[i]) before[i]: after[i],
    };
    if (moved.isNotEmpty) moves[doc.docPath] = moved;
  }
  return SlugMoves(moves);
}

/// Whether a line the body rewrite changed is a heading line: an ATX
/// heading, or a line a setext underline follows.
bool _changesAHeading(List<String> before, List<String> after) {
  for (var i = 0; i < before.length && i < after.length; i++) {
    if (before[i] == after[i]) continue;
    if (_isAtxHeading(before[i])) return true;
    if (i + 1 < before.length && _setextUnderline.hasMatch(before[i + 1])) {
      return true;
    }
  }
  return false;
}

/// Whether [line] opens an ATX heading: at most three spaces, then `#`.
bool _isAtxHeading(String line) {
  var indent = 0;
  while (indent < 3 && line.startsWith(' ', indent)) {
    indent++;
  }
  return line.startsWith('#', indent);
}

/// The heading slugs of [body], read by the anchor-only parse, whose heading
/// subtrees are the ones the full parse builds (P17).
List<String>? _headingSlugsOf(String body) {
  final nodes = parseLinkFreeBody(body);
  return nodes == null ? null : anchorsOf(nodes).headingSlugs;
}

// MARK: - Link anchors

/// Returns [lf], the text of the doc at [docPath], typed or not, with the
/// `#anchor` of each link and definition destination that names an old slug
/// of [moves] set to its new slug, self links included; null when none
/// changes (W3).
AnchorRewrite? withAnchorsMoved(String lf, String docPath, SlugMoves moves) {
  if (!moves.mayName(lf)) return null;
  final body = Doc.parse(lf).afterFrontmatter;
  final bodyStart = lf.length - body.length;
  final destinations = [...linkScanOf(body, firstLine: 1).destinations]
    ..sort((a, b) => b.start - a.start);
  var text = body;
  var citesOthers = false;
  for (final (:start, :end) in destinations) {
    final target = resolveDocLink(body.substring(start, end), docPath);
    if (target is! DocTarget) continue;
    final (anchor, rawAnchor) = (target.anchor, target.rawAnchor);
    final slug = anchor == null ? null : moves.byDoc[target.docPath]?[anchor];
    if (slug == null || rawAnchor == null) continue;
    final written = rawAnchor == anchor ? slug : Uri.encodeComponent(slug);
    text = text.replaceRange(end - rawAnchor.length, end, written);
    citesOthers = citesOthers || target.docPath != docPath;
  }
  if (text == body) return null;
  return (lf: lf.substring(0, bodyStart) + text, citesOthers: citesOthers);
}
