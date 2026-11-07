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
/// `next` its `item_id_lettered` finding named.
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

  late final Stamps _stamps = stampsOf(
    _docs.values,
    (doc) => _rewriteOf(doc, const {}).lf,
  );

  late final Map<String, _Rewrite> _rewrites = {
    for (final doc in _docs.values) doc.docPath: _rewriteOf(doc, _stamps),
  };

  /// Returns the doc at [docPath] with its renumbered IDs and every reference
  /// to one rewritten, each matched `confirmed` fingerprint carried over.
  ///
  /// A doc the pass was not planned over comes back as given. Throws an
  /// [ArgumentError] when [lf] is not the text the pass was planned over.
  String apply(String docPath, String lf) {
    if (renumberings.isEmpty) return lf;
    final rewrite = _rewrites[docPath];
    if (rewrite == null) return lf;
    if (lf != _docs[docPath]?.lf) {
      throw ArgumentError.value(
        docPath,
        'lf',
        'is not the text the renumber pass was planned over',
      );
    }
    return rewrite.lf;
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

  _Rewrite _rewriteOf(RenumberDoc doc, Stamps stamps) {
    final namesIds = _index.mayName(doc.lf);
    if (!namesIds && stamps.isEmpty) return (lf: doc.lf, citesOthers: false);
    var citesInBody = false;
    var rewritesSteps = false;
    var bodyText = doc.lf;
    if (namesIds) {
      final lines = [...doc.lines];
      final body = RenumberBodyRewrite(doc, _index, lines);
      citesInBody = body.rewriteTokens();
      rewritesSteps = body.rewriteSteps();
      bodyText = lines.join('\n');
    }
    final lf = withEntriesRenumbered(bodyText, doc.docPath, _index, stamps);
    return (
      lf: lf,
      citesOthers: citesInBody || rewritesSteps || lf != bodyText,
    );
  }
}
