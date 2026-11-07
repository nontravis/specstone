import 'package:specstone_core/src/journeys/journey_steps.dart'
    show journeyTypeId;
import 'package:specstone_core/src/setup_migration/renumber_anchors.dart';
import 'package:specstone_core/src/setup_migration/renumber_body.dart';
import 'package:specstone_core/src/setup_migration/renumber_doc.dart';
import 'package:specstone_core/src/setup_migration/renumber_entries.dart';
import 'package:specstone_core/src/setup_migration/renumber_index.dart';
import 'package:specstone_core/src/setup_migration/renumber_stamps.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

// MARK: - Constants

const _planLabel = 'renumber ids: ';
const _referencesLabel = '; references: ';

// MARK: - Types

/// A rewritten doc and whether it rewrote a reference to another doc's ID.
typedef _Rewrite = ({String lf, bool citesOthers});

// MARK: - RenumberPass

/// The one-time pass of a pack upgrade that renumbers each lettered item ID
/// and scenario number (`doc_model` RULE-12, apply_steps_and_pins E18, E19).
///
/// It reads IDs and next numbers as `check` does, so each new number is the
/// `next` its `item_id_lettered` finding named. Its cost follows the lettered
/// IDs: a doc holding no renumbered token is read for its structure once and
/// never rewritten, and each rewrite runs once (W17).
final class RenumberPass {
  new _(this._docs, this._index) : renumberings = _index.renumberings;

  /// Plans the pass over every typed doc of the run: planned DocPath, LF
  /// text, merged doc type.
  factory plan(List<({String docPath, String lf, MergedDocType type})> docs) {
    final runDocs = [
      for (final doc in docs) RenumberDoc(doc.docPath, doc.lf, doc.type),
    ]..sort((a, b) => compareCodePoints(a.docPath, b.docPath));
    return RenumberPass._({
      for (final doc in runDocs) doc.docPath: doc,
    }, RenumberIndex(runDocs));
  }

  final Map<String, RenumberDoc> _docs;
  final RenumberIndex _index;

  /// Each renumbering, in tree then document order.
  final List<({String docPath, String from, String to})> renumberings;

  /// The text after the body rewrite of each doc it changes: ID tokens,
  /// journey steps, then the anchors of links to a moved heading slug.
  late final Map<String, _Rewrite> _bodies = _bodiesOf();

  late final Stamps _stamps = stampsOf(_docs.values, {
    for (final MapEntry(:key, :value) in _bodies.entries) key: value.lf,
  });

  /// The final text of each doc the pass changes, in tree order.
  late final Map<String, _Rewrite> _rewrites = {
    for (final doc in _docs.values) doc.docPath: ?_rewriteOf(doc),
  };

  /// Returns the doc at [docPath] with its renumbered IDs and every reference
  /// to one rewritten, each matched `confirmed` fingerprint carried over.
  ///
  /// A doc the pass was not planned over comes back as given. Throws an
  /// [ArgumentError] when [lf] is not the text the pass was planned over.
  String apply(String docPath, String lf) {
    if (renumberings.isEmpty) return lf;
    final doc = _docs[docPath];
    if (doc == null) return lf;
    if (lf != doc.lf) {
      throw ArgumentError.value(
        docPath,
        'lf',
        'is not the text the renumber pass was planned over',
      );
    }
    return _rewrites[docPath]?.lf ?? lf;
  }

  /// The `renumber ids:` plan line, or null when nothing renumbers.
  String? get planLine {
    if (renumberings.isEmpty) return null;
    final ids = [
      for (final (:docPath, :from, :to) in renumberings)
        '$docPath $from -> $to',
    ].join(', ');
    final references = [
      for (final MapEntry(key: docPath, value: rewrite) in _rewrites.entries)
        if (rewrite.citesOthers) docPath,
    ];
    if (references.isEmpty) return '$_planLabel$ids';
    return '$_planLabel$ids$_referencesLabel${references.join(', ')}';
  }

  Map<String, _Rewrite> _bodiesOf() {
    final bodies = <String, _Rewrite>{};
    for (final doc in _docs.values) {
      final rewrite = _tokenRewriteOf(doc);
      if (rewrite != null) bodies[doc.docPath] = rewrite;
    }
    final moves = slugMovesOf(_docs.values, {
      for (final MapEntry(:key, :value) in bodies.entries) key: value.lf,
    });
    if (moves.isEmpty) return bodies;
    for (final doc in _docs.values) {
      final current = bodies[doc.docPath];
      final moved = withAnchorsMoved(current?.lf ?? doc.lf, doc, moves);
      if (moved == null) continue;
      bodies[doc.docPath] = (
        lf: moved.lf,
        citesOthers: (current?.citesOthers ?? false) || moved.citesOthers,
      );
    }
    return bodies;
  }

  /// The doc's ID tokens and journey steps rewritten; null when none
  /// changes.
  _Rewrite? _tokenRewriteOf(RenumberDoc doc) {
    final stepsMayChange =
        doc.type.id == journeyTypeId && _index.renumbersScenarios;
    final body = doc.lf.substring(doc.frontmatterText.length);
    if (!stepsMayChange && !_index.mayName(body)) return null;
    final lines = [...doc.lines];
    final rewrite = RenumberBodyRewrite(doc, _index, lines);
    final citesInBody = rewrite.rewriteTokens();
    final rewritesSteps = rewrite.rewriteSteps();
    final lf = lines.join('\n');
    if (lf == doc.lf) return null;
    return (lf: lf, citesOthers: citesInBody || rewritesSteps);
  }

  _Rewrite? _rewriteOf(RenumberDoc doc) {
    final body = _bodies[doc.docPath];
    final bodyText = body?.lf ?? doc.lf;
    final lf = _mayRenameEntries(doc)
        ? withEntriesRenumbered(bodyText, doc, _index, _stamps)
        : bodyText;
    if (lf == doc.lf) return null;
    return (
      lf: lf,
      citesOthers: (body?.citesOthers ?? false) || lf != bodyText,
    );
  }

  /// Whether the doc's frontmatter may hold an entry the pass renames: a
  /// renumbered ID's text, or, while a scenario renumbers or a block is
  /// re-stamped, any [renumberedEntryKeys] key.
  bool _mayRenameEntries(RenumberDoc doc) {
    final frontmatter = doc.frontmatterText;
    if (frontmatter.isEmpty) return false;
    if (_index.mayName(frontmatter)) return true;
    if (!_index.renumbersScenarios && _stamps.isEmpty) return false;
    return renumberedEntryKeys.any(frontmatter.contains);
  }
}
