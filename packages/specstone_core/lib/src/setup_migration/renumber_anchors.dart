import 'package:specstone_core/src/consistency_check/reference_rules.dart'
    show architectureTypeId, concernsSectionId, seeTargetIn;
import 'package:specstone_core/src/consistency_check/scenario_blocks.dart'
    show heldSectionIndex;
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_anchors.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/doc_model/markdown_body.dart'
    show parseLinkFreeBody;
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show destinationPartsOf;
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart'
    show docStructureOf;
import 'package:specstone_core/src/index_query/link_places.dart'
    show hrefDestinationsOf;
import 'package:specstone_core/src/index_query/link_scan.dart';
import 'package:specstone_core/src/setup_migration/renumber_doc.dart';

// MARK: - Constants

final _setextUnderline = RegExp(r'^ {0,3}(?:=+|-+)[ \t]*$');

// MARK: - Types

/// The move of a link's anchor: its old slug, decoded, the slug after it, the
/// anchor as the href writes it, and whether the link names another doc.
typedef _AnchorMove = ({
  String old,
  String slug,
  String rawAnchor,
  bool citesOther,
});

/// Per DocPath, each heading slug the pass changes and the slug after it.
final class SlugMoves {
  new(this.byDoc);

  final Map<String, Map<String, String>> byDoc;

  /// Each old slug, as written and escaped, the gate of the bare `see`
  /// targets.
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

/// The anchor rewrite of a doc's links, null when none changes, and whether
/// `markdown` read those links, without which none of them moves (LP2).
typedef LinkAnchorRewrite = ({AnchorRewrite? moved, bool linksRead});

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
/// `#anchor` of each link and definition destination whose href names an old
/// slug of [moves] set to its new slug, self links included (W3).
///
/// The href is the one `markdown` gives the destination (see
/// [hrefDestinationsOf]), so a slug written with escapes or character
/// references moves too; the anchor as written (see [destinationPartsOf])
/// takes the new slug.
LinkAnchorRewrite withAnchorsMoved(String lf, String docPath, SlugMoves moves) {
  final body = Doc.parse(lf).afterFrontmatter;
  if (!_mayMoveAnchors(body, moves)) return (moved: null, linksRead: true);
  final bodyStart = lf.length - body.length;
  final scan = linkScanOf(body, firstLine: 1);
  final (destinations: found, :linksRead) = hrefDestinationsOf(
    body,
    scan,
    canMove: (href) => _anchorMoveOf(href, docPath, moves) != null,
  );
  final destinations = [...found]..sort((a, b) => b.start - a.start);
  var text = body;
  var citesOthers = false;
  for (final (:start, :end, :href, :kind) in destinations) {
    final move = _anchorMoveOf(href, docPath, moves);
    if (move == null) continue;
    final written = body.substring(start, end);
    final at = destinationPartsOf(written, kind).anchorStart;
    if (at == null) continue;
    text = text.replaceRange(
      start + at,
      end,
      _movedOver(written.substring(at), move),
    );
    citesOthers = citesOthers || move.citesOther;
  }
  if (text == body) return (moved: null, linksRead: linksRead);
  return (
    moved: (lf: lf.substring(0, bodyStart) + text, citesOthers: citesOthers),
    linksRead: linksRead,
  );
}

/// Whether a link of [body] may name an old slug of [moves], so the link scan
/// and [hrefDestinationsOf] must read it.
///
/// A destination follows a written `](` or `]:`. With no `\`, `&`, or `%` in
/// the body, an href's anchor decodes to the text written for it, so a body
/// holding no old slug names none; any of the three may spell a slug the text
/// does not hold (`&#115;`, `%73`, `\-`), and then only the read can tell.
bool _mayMoveAnchors(String body, SlugMoves moves) {
  if (!body.contains('](') && !body.contains(']:')) return false;
  final spelledPlain =
      !body.contains(r'\') && !body.contains('&') && !body.contains('%');
  return !spelledPlain || moves.mayName(body);
}

/// Returns [lf] with the `#anchor` of each bare `see` target of the Concerns
/// section of [doc], an `architecture` doc, set to its new slug when it names
/// an old slug of [moves]; null when none changes (R63, E18).
///
/// A `see [text](href)` target is a link, which [withAnchorsMoved] moves.
AnchorRewrite? withConcernsAnchorsMoved(
  RenumberDoc doc,
  String lf,
  SlugMoves moves,
) {
  if (doc.type.id != architectureTypeId || !moves.mayName(lf)) return null;
  final content = docStructureOf(lf, doc.type);
  final section = heldSectionIndex(content, doc.type, concernsSectionId);
  if (section == null) return null;
  final lines = lf.split('\n');
  var citesOthers = false;
  for (final (:text, :line, :fenced) in sectionBodyLines(
    content.sections,
    content.lineFacts,
    section,
  )) {
    final see = fenced ? null : seeTargetIn(text);
    if (see == null || see.text.startsWith('[')) continue;
    final move = _anchorMoveOf(see.text, doc.docPath, moves);
    if (move == null) continue;
    final end = see.start + see.text.length;
    lines[line - 1] = lines[line - 1].replaceRange(
      end - move.rawAnchor.length,
      end,
      _movedOver(move.rawAnchor, move),
    );
    citesOthers = citesOthers || move.citesOther;
  }
  final moved = lines.join('\n');
  return moved == lf ? null : (lf: moved, citesOthers: citesOthers);
}

/// Returns the move of the anchor [href] names, a link of the doc at
/// [docPath], when that anchor is an old slug of [moves]; null otherwise.
_AnchorMove? _anchorMoveOf(String href, String docPath, SlugMoves moves) {
  final target = resolveDocLink(href, docPath);
  if (target is! DocTarget) return null;
  final (anchor, rawAnchor) = (target.anchor, target.rawAnchor);
  final slug = anchor == null ? null : moves.byDoc[target.docPath]?[anchor];
  if (anchor == null || slug == null || rawAnchor == null) return null;
  return (
    old: anchor,
    slug: slug,
    rawAnchor: rawAnchor,
    citesOther: target.docPath != docPath,
  );
}

/// Returns the anchor to write over [written], an anchor as written that
/// reads as [move]'s old slug: the new slug, percent-encoded unless
/// [written] is the old slug itself.
String _movedOver(String written, _AnchorMove move) =>
    written == move.old ? move.slug : Uri.encodeComponent(move.slug);
