import 'package:specstone_core/src/journeys/journey_steps.dart'
    show journeyTypeId;
import 'package:specstone_core/src/setup_migration/renumber_anchors.dart';
import 'package:specstone_core/src/setup_migration/renumber_body.dart';
import 'package:specstone_core/src/setup_migration/renumber_doc.dart';
import 'package:specstone_core/src/setup_migration/renumber_entries.dart';
import 'package:specstone_core/src/setup_migration/renumber_index.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

// MARK: - Constants

const _planLabel = 'renumber ids: ';
const _unreadLabel = '; not fully rewritten: ';

// MARK: - Types

/// The body rewrite of each doc it changes, and each doc whose links it
/// needs but `markdown` does not read.
typedef _BodyPass = ({Map<String, String> bodies, Set<String> linksUnread});

// MARK: - RenumberPass

/// The one-time pass of a pack upgrade that renumbers each lettered item ID
/// and scenario number (`doc_model` RULE-12, apply_steps_and_pins E18, E19).
///
/// It reads IDs and next numbers as `check` does, so each new number is the
/// `next` its `item_id_lettered` finding named. Its cost follows the lettered
/// IDs: a doc holding no renumbered token is read for its structure once and
/// never rewritten, and each rewrite runs once (W17).
final class RenumberPass {
  new _(this._texts, this._docs, this._index)
    : renumberings = _index.renumberings;

  /// Plans the pass over every doc of the run: planned DocPath, LF text, and
  /// merged doc type, null for an untyped doc.
  ///
  /// An untyped doc holds no ID; only its links take the moved anchors, as
  /// `check` reads its links too (W3).
  factory plan(List<({String docPath, String lf, MergedDocType? type})> docs) {
    final sorted = [...docs]
      ..sort((a, b) => compareCodePoints(a.docPath, b.docPath));
    final runDocs = [
      for (final doc in sorted)
        if (doc.type case final type?) RenumberDoc(doc.docPath, doc.lf, type),
    ];
    return RenumberPass._(
      {for (final doc in sorted) doc.docPath: doc.lf},
      {for (final doc in runDocs) doc.docPath: doc},
      RenumberIndex(runDocs),
    );
  }

  /// The LF text of every doc of the run, typed or not, in tree order.
  final Map<String, String> _texts;

  /// The typed docs of the run.
  final Map<String, RenumberDoc> _docs;
  final RenumberIndex _index;

  /// Each renumbering, in tree then document order.
  final List<({String docPath, String from, String to})> renumberings;

  late final _BodyPass _bodyPass = _bodyPassOf();

  /// The text after the body rewrite of each doc it changes: ID tokens,
  /// journey steps, then the anchors of links to a moved heading slug.
  late final Map<String, String> _bodies = _bodyPass.bodies;

  /// The final text of each doc the pass changes, in tree order.
  late final Map<String, String> _rewrites = {
    for (final docPath in _texts.keys)
      docPath: ?switch (_docs[docPath]) {
        final doc? => _rewriteOf(doc),
        null => _bodies[docPath],
      },
  };

  /// Returns the doc at [docPath] with its renumbered IDs and every reference
  /// to one rewritten, each matched `confirmed` fingerprint carried over.
  ///
  /// A doc the pass was not planned over comes back as given. Throws an
  /// [ArgumentError] when [lf] is not the text the pass was planned over.
  String apply(String docPath, String lf) {
    if (renumberings.isEmpty) return lf;
    final planned = _texts[docPath];
    if (planned == null) return lf;
    if (lf != planned) {
      throw ArgumentError.value(
        docPath,
        'lf',
        'is not the text the renumber pass was planned over',
      );
    }
    return _rewrites[docPath] ?? lf;
  }

  /// The `renumber ids:` plan line, `<n> IDs in <m> docs`, or null when
  /// nothing renumbers.
  ///
  /// `<m>` counts the docs the pass rewrites, the renumbered docs and each
  /// other doc it rewrites for them. A doc whose links it needs but `markdown`
  /// does not read, whose link citations and link anchors stay as written,
  /// adds `; not fully rewritten: <k>` (LP2, R74).
  String? get planLine {
    if (renumberings.isEmpty) return null;
    final unread = _unreadDocs;
    return '$_planLabel${renumberings.length} IDs in ${_rewrites.length} docs'
        '${unread.isEmpty ? '' : '$_unreadLabel${unread.length}'}';
  }

  /// Each renumbering as `<DocPath> <old> -> <new>` in tree then document
  /// order, then each doc the pass rewrites, then each doc it cannot fully
  /// rewrite that it does not rewrite; empty when nothing renumbers.
  List<String> get paths {
    if (renumberings.isEmpty) return const [];
    final rewritten = _rewrites.keys.toList();
    return [
      for (final (:docPath, :from, :to) in renumberings)
        '$docPath $from -> $to',
      ...rewritten,
      for (final docPath in _unreadDocs)
        if (!_rewrites.containsKey(docPath)) docPath,
    ];
  }

  List<String> get _unreadDocs => [
    for (final docPath in _texts.keys)
      if (_bodyPass.linksUnread.contains(docPath)) docPath,
  ];

  _BodyPass _bodyPassOf() {
    final bodies = <String, String>{};
    final linksUnread = <String>{};
    for (final doc in _docs.values) {
      final (:rewrite, :linksRead) = _tokenRewriteOf(doc);
      if (rewrite != null) bodies[doc.docPath] = rewrite;
      if (!linksRead) linksUnread.add(doc.docPath);
    }
    final moves = slugMovesOf(_docs.values, bodies);
    if (!moves.isEmpty) _moveAnchors(bodies, linksUnread, moves);
    return (bodies: bodies, linksUnread: linksUnread);
  }

  /// Sets in [bodies] each doc whose link anchors or bare `see` anchors
  /// [moves] change, and adds to [linksUnread] each doc whose links
  /// `markdown` does not read.
  void _moveAnchors(
    Map<String, String> bodies,
    Set<String> linksUnread,
    SlugMoves moves,
  ) {
    for (final MapEntry(key: docPath, value: lf) in _texts.entries) {
      var current = bodies[docPath] ?? lf;
      final (:moved, :linksRead) = withAnchorsMoved(current, docPath, moves);
      if (!linksRead) linksUnread.add(docPath);
      if (moved != null) current = moved.lf;
      final doc = _docs[docPath];
      final concerns = doc == null
          ? null
          : withConcernsAnchorsMoved(doc, current, moves);
      if (concerns != null) current = concerns.lf;
      if (current != lf) bodies[docPath] = current;
    }
  }

  /// The doc's ID tokens and journey steps rewritten, null when none
  /// changes, and whether `markdown` read the links a token's citation may
  /// come from.
  ({String? rewrite, bool linksRead}) _tokenRewriteOf(RenumberDoc doc) {
    final stepsMayChange =
        doc.type.id == journeyTypeId && _index.renumbersScenarios;
    final body = doc.lf.substring(doc.frontmatterText.length);
    final namesToken = _index.mayName(body);
    if (!stepsMayChange && !namesToken) return (rewrite: null, linksRead: true);
    final lines = [...doc.lines];
    final rewrite = RenumberBodyRewrite(doc, _index, lines)
      ..rewriteTokens()
      ..rewriteSteps();
    final lf = lines.join('\n');
    return (
      rewrite: lf == doc.lf ? null : lf,
      linksRead: !namesToken || rewrite.linksRead,
    );
  }

  String? _rewriteOf(RenumberDoc doc) {
    final bodyText = _bodies[doc.docPath] ?? doc.lf;
    final lf = _mayRenameEntries(doc)
        ? withEntriesRenumbered(bodyText, doc, _index)
        : bodyText;
    return lf == doc.lf ? null : lf;
  }

  /// Whether the doc's frontmatter may hold an entry the pass renames: a
  /// renumbered ID's text, or, while a scenario renumbers, any
  /// [renumberedEntryKeys] key.
  bool _mayRenameEntries(RenumberDoc doc) {
    final frontmatter = doc.frontmatterText;
    if (frontmatter.isEmpty) return false;
    if (_index.mayName(frontmatter)) return true;
    if (!_index.renumbersScenarios) return false;
    return renumberedEntryKeys.any(frontmatter.contains);
  }
}
