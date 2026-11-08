import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/doc_model/doc.dart' show Doc;
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/setup_migration/renumber_doc.dart';
import 'package:specstone_core/src/setup_migration/renumber_entries.dart'
    show withBlockValues;
import 'package:specstone_core/src/setup_migration/renumber_index.dart';
import 'package:specstone_core/src/setup_migration/tracked_blocks.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/pack_version.dart';

// MARK: - Constants

const _confirmedKey = 'confirmed';
final _fingerprintShape = RegExp(r'^[0-9a-f]{12}$');

// MARK: - Types

/// A doc of the run: planned DocPath, LF text, and merged doc type, null for
/// an untyped doc.
typedef StampDoc = ({String docPath, String lf, MergedDocType? type});

// MARK: - StampPass

/// The last step of a pack upgrade: it stamps the approval hash on each doc
/// that counted as approved before the run (R81) and, in the one-time run
/// alone, re-stamps each `confirmed` entry that matched before the run
/// (apply_steps_and_pins E30, E31).
///
/// One pass computes every after-hash, over the text each doc has after every
/// other step, so no earlier step stamps a value a later one changes.
final class StampPass {
  new _(
    this._planned,
    this._stamped,
    this._approvals,
    this._fingerprints,
    this._skipped,
  );

  /// Plans the pass over the docs of the run as they were [before] it and as
  /// they stand [after] its last step, both at the planned DocPath.
  ///
  /// An entry is paired with the one at its position in the doc before the
  /// run; a doc whose `confirmed` entries changed in number keeps them.
  ///
  /// [pins] are the pack pins before the run: a doc counts as approved when it
  /// did not await approval under them (`document_writing` approval rule).
  /// [restampsFingerprints] holds for the one-time run alone. A typed doc
  /// whose frontmatter is not valid YAML, before or after, is skipped and
  /// named on the plan line.
  factory plan(
    List<StampDoc> before,
    List<StampDoc> after, {
    required Map<String, PackVersion> pins,
    required bool restampsFingerprints,
  }) {
    final ran = stampsHaveRun(pins);
    final skipped = <String>[];
    final beforeAt = {for (final doc in before) doc.docPath: doc};
    final world = _World(after);
    final beforeWorld = _World(before);
    final planned = <String, String>{};
    final stamped = <String, String>{};
    var approvals = 0;
    var fingerprints = 0;
    for (final doc in after) {
      final type = doc.type;
      final old = beforeAt[doc.docPath];
      if (type == null || old == null) continue;
      final beforeHash = comparedApprovalHash(old.lf, type);
      if (beforeHash == null || comparedApprovalHash(doc.lf, type) == null) {
        skipped.add(doc.docPath);
        continue;
      }
      planned[doc.docPath] = doc.lf;
      final entries = restampsFingerprints
          ? _restamped(doc, old, beforeWorld, world)
          : (lf: doc.lf, count: 0);
      var lf = entries.lf;
      // A doc that did not await approval before the run counts as approved;
      // one `check` flagged then (a stale hash, a bad value) stays (G32).
      if (!awaitsApproval(
        ApprovalFields.of(Doc.parse(old.lf)),
        beforeHash,
        stampsHaveRun: ran,
      )) {
        lf = withApprovalHash(lf, type);
      }
      if (lf == doc.lf) continue;
      stamped[doc.docPath] = lf;
      fingerprints += entries.count;
      if (lf != entries.lf) approvals++;
    }
    return StampPass._(planned, stamped, approvals, fingerprints, skipped);
  }

  final Map<String, String> _planned;
  final Map<String, String> _stamped;
  final int _approvals;
  final int _fingerprints;
  final List<String> _skipped;

  /// Returns the doc at [docPath] with its approval hash and `confirmed`
  /// fingerprints stamped.
  ///
  /// A doc the pass was not planned over comes back as given. Throws an
  /// [ArgumentError] when [lf] is not the text the pass was planned over.
  String apply(String docPath, String lf) {
    final planned = _planned[docPath];
    if (planned == null) return lf;
    if (lf != planned) {
      throw ArgumentError.value(
        docPath,
        'lf',
        'is not the text the stamp pass was planned over',
      );
    }
    return _stamped[docPath] ?? lf;
  }

  /// The `stamps:` plan line, or null when nothing is stamped or skipped.
  String? get planLine =>
      stampsPlanLine(_approvals, _fingerprints, skipped: _skipped);
}

/// The `stamps:` plan line for [approvals] approval hashes and [fingerprints]
/// `confirmed` fingerprints, then `; skipped: ` and each DocPath of [skipped],
/// a doc left unstamped for invalid frontmatter; null when all are empty.
String? stampsPlanLine(
  int approvals,
  int fingerprints, {
  List<String> skipped = const [],
}) {
  if (approvals == 0 && fingerprints == 0 && skipped.isEmpty) return null;
  final counts =
      'stamps: $approvals approval hashes, $fingerprints fingerprints';
  if (skipped.isEmpty) return counts;
  final paths = [...skipped]..sort(compareCodePoints);
  return '$counts; skipped: ${paths.join(', ')}';
}

// MARK: - Confirmed entries

/// A doc's text with its matched `confirmed` entries re-stamped, and how many
/// changed.
typedef _Restamped = ({String lf, int count});

/// Re-stamps each entry of [doc] whose fingerprint matched its upstream block
/// in [old], the doc before the run, with the block's fingerprint in
/// [after].
_Restamped _restamped(StampDoc doc, StampDoc old, _World before, _World after) {
  final unchanged = (lf: doc.lf, count: 0);
  if (!_holdsConfirmed(doc.type!)) return unchanged;
  final matched = <bool>[];
  withBlockValues(
    old.lf,
    _confirmedKey,
    _EntryWalk((_, label, fingerprint) {
      matched.add(before.matches(old.docPath, label, fingerprint));
      return null;
    }).call,
  );
  var seen = 0;
  withBlockValues(
    doc.lf,
    _confirmedKey,
    _EntryWalk((_, _, _) {
      seen++;
      return null;
    }).call,
  );
  if (seen != matched.length || !matched.contains(true)) return unchanged;
  var count = 0;
  final lf = withBlockValues(
    doc.lf,
    _confirmedKey,
    _EntryWalk((index, label, fingerprint) {
      if (!matched[index]) return null;
      final now = after.currentFingerprint(doc.docPath, label);
      if (now == null || now == fingerprint) return null;
      count++;
      return now;
    }).call,
  );
  return (lf: lf, count: count);
}

bool _holdsConfirmed(MergedDocType type) =>
    type.fields.any((field) => field.id == _confirmedKey);

/// Walks the values of a `confirmed` key as entries, `<label> <fingerprint>`.
///
/// A quoted entry arrives as one value; a bare one as its label and its
/// fingerprint, which [call] pairs.
final class _EntryWalk {
  new(this._onEntry);

  final String? Function(int index, String label, String fingerprint) _onEntry;
  String? _label;
  int _index = 0;

  /// Returns the value to write for [value], or null to keep it.
  String? call(String value) {
    final space = value.indexOf(' ');
    if (space >= 0) {
      _flush();
      final label = value.substring(0, space);
      final stamped = _onEntry(_index++, label, value.substring(space + 1));
      return stamped == null ? null : '$label $stamped';
    }
    final label = _label;
    if (label == null || !_fingerprintShape.hasMatch(value)) {
      _flush();
      _label = value;
      return null;
    }
    _label = null;
    return _onEntry(_index++, label, value);
  }

  // A label no fingerprint follows is an entry whose fingerprint is empty.
  void _flush() {
    final label = _label;
    if (label == null) return;
    _label = null;
    _onEntry(_index++, label, '');
  }
}

// MARK: - World

/// The docs of one moment of the run, and the blocks their `confirmed`
/// entries track.
final class _World {
  new(List<StampDoc> docs)
    : _docs = [
        for (final doc in docs)
          if (doc.type case final type?) RenumberDoc(doc.docPath, doc.lf, type),
      ] {
    _index = RenumberIndex(_docs);
  }

  final List<RenumberDoc> _docs;
  late final RenumberIndex _index;
  late final Map<String, RenumberDoc> _byPath = {
    for (final doc in _docs) doc.docPath: doc,
  };
  final Map<String, Map<String, String>> _blocks = {};

  /// Whether the entry [label] [fingerprint] of the doc at [docPath] equals
  /// the fingerprint of its block, by the current recipe or the 1.1.0 one (G9).
  bool matches(String docPath, String label, String fingerprint) {
    final block = _blockOf(docPath, label);
    if (block == null) return false;
    return fingerprint == fingerprintOf(block) ||
        fingerprint == legacyFingerprintOf(block);
  }

  /// The fingerprint of the block [label] names in the doc at [docPath]; null
  /// when it names none.
  String? currentFingerprint(String docPath, String label) {
    final block = _blockOf(docPath, label);
    return block == null ? null : fingerprintOf(block);
  }

  String? _blockOf(String docPath, String label) {
    final target = _index.confirmedTarget(label, docPath);
    if (target == null) return null;
    final (blockPath, key) = target.block;
    final doc = _byPath[blockPath];
    if (doc == null) return null;
    return (_blocks[blockPath] ??= trackedBlocksOf(doc))[key];
  }
}
