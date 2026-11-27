import 'package:specstone_core/src/consistency_check/contract_block.dart'
    show contractBlockIn;
import 'package:specstone_core/src/consistency_check/edge_case_blocks.dart'
    show edgeCaseBlocksIn;
import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/consistency_check/tracked_links.dart'
    show itemTextIn;
import 'package:specstone_core/src/doc_model/doc.dart' show Doc;
import 'package:specstone_core/src/doc_model/doc_splice.dart'
    show isFingerprint;
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show OverrideLabel, readLinkLabel;
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/index_query/doc_parse.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart' show docNameOf;
import 'package:specstone_core/src/index_query/item_facts.dart'
    show sectionItemsAt;
import 'package:specstone_core/src/index_query/line_facts.dart'
    show lineFactsOf;
import 'package:specstone_core/src/index_query/matrix_rows.dart'
    show matrixLinesIn;
import 'package:specstone_core/src/index_query/models/line_facts.dart'
    show LineFacts;
import 'package:specstone_core/src/index_query/models/link_cite.dart'
    show ItemCite;
import 'package:specstone_core/src/index_query/models/matrix_line.dart';
import 'package:specstone_core/src/index_query/override_chain.dart'
    show
        carriesOverrides,
        isOverrideLine,
        overrideLinkIn,
        overrideTextStart,
        readOverrideLinkIn;
import 'package:specstone_core/src/setup_migration/models/stamp_doc.dart';
import 'package:specstone_core/src/setup_migration/renumber_doc.dart';
import 'package:specstone_core/src/setup_migration/renumber_entries.dart'
    show withBlockValues;
import 'package:specstone_core/src/setup_migration/renumber_index.dart';
import 'package:specstone_core/src/setup_migration/tracked_blocks.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

// MARK: - Constants

const _confirmedKey = 'confirmed';
const _overridesKey = 'overrides';

// MARK: - StampPass

/// The last step of a pack upgrade: it stamps the approval hash on each doc
/// that counted as approved before the run and re-stamps each matched
/// `confirmed` entry whose block the link rewrites alone rewrote.
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
  /// A [before] doc carries the type it had before the run, so its hash is the
  /// one it was approved with even when a step dropped a field of that type.
  ///
  /// An entry is paired with the one at its position in the doc before the
  /// run; a doc whose `confirmed` entries changed in number keeps them.
  ///
  /// [linkedFrom] holds, for each doc the run's link rewrites changed, its
  /// text after the steps and before those rewrites; an entry whose block the
  /// steps left as before the run and the rewrites changed is re-stamped, and
  /// no other. A typed doc whose frontmatter is not valid YAML, before or
  /// after, is skipped and named on the plan line. A doc of [typedByAdd], by
  /// DocPath, is left as written: the add made it a draft awaiting approval.
  factory plan(
    List<StampDoc> before,
    List<StampDoc> after, {
    Set<String> typedByAdd = const {},
    Map<String, String> linkedFrom = const {},
  }) {
    final skipped = <String>[];
    final beforeAt = {for (final doc in before) doc.docPath: doc};
    final world = _World(after);
    final beforeWorld = _World(before);
    final linkedWorld = _worldOf(after, linkedFrom);
    final restamps = _restampRule(
      world,
      before: beforeWorld,
      linked: linkedWorld,
    );
    final linkOnly = linkedWorld == null
        ? null
        : _LinkOnlyRestamp(beforeWorld, linkedWorld, world);
    final planned = <String, String>{};
    final stamped = <String, String>{};
    var approvals = 0;
    var fingerprints = 0;
    for (final doc in after) {
      final type = doc.type;
      final old = beforeAt[doc.docPath];
      if (type == null || old == null) continue;
      if (typedByAdd.contains(doc.docPath)) continue;
      final beforeHash = comparedApprovalHash(old.lf, old.type);
      if (beforeHash == null || comparedApprovalHash(doc.lf, type) == null) {
        skipped.add(doc.docPath);
        continue;
      }
      planned[doc.docPath] = doc.lf;
      final confirmed = restamps == null
          ? RestampedEntries(doc.lf, 0)
          : _restamped(doc, old, beforeWorld, world, restamps);
      final entries = linkOnly?.apply(doc, type, confirmed) ?? confirmed;
      var lf = entries.lfText;
      // A doc that did not await approval before the run counts as approved;
      // one `check` flagged then (a stale hash, a bad value) stays.
      if (!awaitsApproval(ApprovalFields.of(Doc.parse(old.lf)), beforeHash)) {
        lf = withApprovalHash(lf, type);
      }
      if (lf == doc.lf) continue;
      stamped[doc.docPath] = lf;
      fingerprints += entries.count;
      if (lf != entries.lfText) approvals++;
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

  /// The DocPath of each doc left unstamped for invalid frontmatter, in code
  /// point order.
  List<String> get paths => [..._skipped]..sort(compareCodePoints);
}

/// The `stamps:` plan line for [approvals] approval hashes and [fingerprints]
/// `confirmed` fingerprints, then `; skipped: <n>` for the docs of [skipped],
/// left unstamped for invalid frontmatter; null when all are empty.
String? stampsPlanLine(
  int approvals,
  int fingerprints, {
  List<String> skipped = const [],
}) {
  if (approvals == 0 && fingerprints == 0 && skipped.isEmpty) return null;
  final counts =
      'stamps: $approvals approval hashes, $fingerprints fingerprints';
  return skipped.isEmpty ? counts : '$counts; skipped: ${skipped.length}';
}

// MARK: - Confirmed entries

/// A doc's text with its matched entries re-stamped, and how many changed.
final class RestampedEntries {
  const new(this.lfText, this.count);

  final String lfText;
  final int count;
}

/// Returns [lfText] with each entry of the frontmatter key [key],
/// `<label> <fingerprint>`, that [matched] its block before a step set to the
/// fingerprint [after] gives that block once the step ran.
///
/// An entry stale before the step, which [matched] rejects, keeps its value,
/// as does one whose block [after] gives none for.
RestampedEntries withEntriesRestamped(
  String lfText,
  String key, {
  required bool Function(int index, String label, String fingerprint) matched,
  required String? Function(String label) after,
}) {
  var count = 0;
  final text = withBlockValues(
    lfText,
    key,
    _EntryWalk((index, label, fingerprint) {
      if (!matched(index, label, fingerprint)) return null;
      final now = after(label);
      if (now == null || now == fingerprint) return null;
      count++;
      return now;
    }).call,
  );
  return RestampedEntries(text, count);
}

/// Whether the matched entry [label] of the doc at [docPath] takes its
/// block's fingerprint after the run.
typedef _Restamps = bool Function(String docPath, String label);

/// Returns which matched entries the pass re-stamps: each whose block the link
/// rewrites alone changed; null when it re-stamps none.
///
/// The link rewrites alone changed one whose fingerprint in [linked], the
/// world before those rewrites, equals the one in [before] and differs from
/// the one in [world].
_Restamps? _restampRule(
  _World world, {
  required _World before,
  required _World? linked,
}) {
  if (linked == null) return null;
  return (docPath, label) {
    final now = world.currentFingerprint(docPath, label);
    final unlinked = linked.currentFingerprint(docPath, label);
    return unlinked != null &&
        unlinked != now &&
        unlinked == before.currentFingerprint(docPath, label);
  };
}

/// Returns the world of [after] with each doc [texts] names at that text, or
/// null when [texts] names none.
_World? _worldOf(List<StampDoc> after, Map<String, String> texts) =>
    texts.isEmpty
    ? null
    : _World([
        for (final doc in after)
          StampDoc(
            docPath: doc.docPath,
            lf: texts[doc.docPath] ?? doc.lf,
            type: doc.type,
            target: doc.target,
          ),
      ]);

/// Re-stamps each entry of [doc] whose fingerprint matched its upstream block
/// in [old], the doc before the run, and that [restamps] picks, with the
/// block's fingerprint in [after].
RestampedEntries _restamped(
  StampDoc doc,
  StampDoc old,
  _World before,
  _World after,
  _Restamps restamps,
) {
  final unchanged = RestampedEntries(doc.lf, 0);
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
  return withEntriesRestamped(
    doc.lf,
    _confirmedKey,
    matched: (index, label, _) =>
        matched[index] && restamps(doc.docPath, label),
    after: (label) => after.currentFingerprint(doc.docPath, label),
  );
}

bool _holdsConfirmed(MergedDocType type) =>
    type.fields.any((field) => field.id == _confirmedKey);

// MARK: - Overrides entries and matrix rows

/// Re-stamps each `overrides` entry and Verification matrix row that matched
/// its block before the run and whose block only the run's link rewrites
/// changed, its block read in the world before the run, the world before
/// those rewrites, and the world after the run.
final class _LinkOnlyRestamp {
  const new(this._before, this._linked, this._after);

  final _World _before;
  final _World _linked;
  final _World _after;

  /// Returns [entries], the text of [doc], of [type], with its `confirmed`
  /// entries stamped, with each such entry and row set to its block's
  /// fingerprint after the run, the count taking them too.
  RestampedEntries apply(
    StampDoc doc,
    MergedDocType type,
    RestampedEntries entries,
  ) {
    var text = entries.lfText;
    var count = entries.count;
    if (carriesOverrides(type)) {
      final overrides = withEntriesRestamped(
        text,
        _overridesKey,
        matched: (_, label, fingerprint) => _isLinkOnly(
          (world) => world.overrideFingerprint(doc.docPath, label, doc.target),
          fingerprint,
        ),
        after: (label) =>
            _after.overrideFingerprint(doc.docPath, label, doc.target),
      );
      text = overrides.lfText;
      count += overrides.count;
    }
    if (verificationMatrixOf(type) != null) {
      final rows = _rowsRestamped(
        text,
        type,
        docNameOf(doc.docPath, type, target: doc.target),
      );
      text = rows.lfText;
      count += rows.count;
    }
    return RestampedEntries(text, count);
  }

  /// Whether a block [fingerprintIn] reads, recorded as [recorded], matched
  /// before the run, kept its fingerprint through the steps, and changed by
  /// the link rewrites.
  bool _isLinkOnly(
    String? Function(_World world) fingerprintIn,
    String recorded,
  ) =>
      fingerprintIn(_before) == recorded &&
      fingerprintIn(_linked) == recorded &&
      fingerprintIn(_after) != recorded;

  /// Returns [lfText], a record of [type] named [recordName], with each matrix
  /// row whose block only the link rewrites changed set to its fingerprint
  /// after the run.
  RestampedEntries _rowsRestamped(
    String lfText,
    MergedDocType type,
    String recordName,
  ) {
    final lines = lfText.split('\n');
    var count = 0;
    for (final row in matrixLinesIn(lfText, type).whereType<MatrixRow>()) {
      final recorded = row.fingerprint;
      if (recorded == null) continue;
      String? fingerprintIn(_World world) =>
          world.rowFingerprint(recordName, row);
      final now = fingerprintIn(_after);
      if (now == null || !_isLinkOnly(fingerprintIn, recorded)) continue;
      final line = lines[row.line - 1];
      final at = line.lastIndexOf(recorded);
      lines[row.line - 1] = line.replaceRange(at, at + recorded.length, now);
      count++;
    }
    return RestampedEntries(count == 0 ? lfText : lines.join('\n'), count);
  }
}

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
    if (label == null || !isFingerprint(value)) {
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

/// The docs of one moment of the run, and the blocks their `confirmed` and
/// `overrides` entries and matrix rows track.
///
/// It reads an override's item, an FR's contract block, and an edge case as
/// `check`'s tracked block reader does, through the same content-level
/// readers; a run's index cannot be opened before the pins move.
final class _World {
  new(List<StampDoc> docs)
    : _docs = [
        for (final doc in docs)
          if (doc.type case final type?) RenumberDoc(doc.docPath, doc.lf, type),
      ],
      _targets = {for (final doc in docs) doc.docPath: doc.target} {
    _index = RenumberIndex(_docs);
  }

  final List<RenumberDoc> _docs;

  /// The code target of each doc, by DocPath; null for a shared doc.
  final Map<String, String?> _targets;
  late final RenumberIndex _index;
  late final Map<String, RenumberDoc> _byPath = {
    for (final doc in _docs) doc.docPath: doc,
  };
  final Map<String, Map<String, String>> _blocks = {};

  /// The docs of each `<doc type>:<Name>`, each named as the index names it,
  /// through its target's pattern set.
  late final Map<String, List<RenumberDoc>> _byTypedName = () {
    final named = <String, List<RenumberDoc>>{};
    for (final doc in _docs) {
      final name = docNameOf(
        doc.docPath,
        doc.type,
        target: _targets[doc.docPath],
      );
      (named['${doc.type.id}:$name'] ??= []).add(doc);
    }
    return named;
  }();

  /// The one doc named [typedName], `<doc type>:<Name>`: of twins, the one of
  /// [target]; null when none or two or more remain.
  RenumberDoc? _named(String typedName, String? target) {
    final docs = _byTypedName[typedName] ?? const <RenumberDoc>[];
    if (docs.length == 1) return docs.single;
    final own = [
      for (final doc in docs)
        if (_targets[doc.docPath] == target) doc,
    ];
    return own.length == 1 ? own.single : null;
  }

  final Map<String, Map<String, String>> _edgeCases = {};
  final Map<String, LineFacts> _facts = {};

  /// The fingerprint of the item the override address [address], written in
  /// the doc at [docPath] of [target], names; null when it names none.
  ///
  /// The item is read from the section the anchor of that doc's override line
  /// for it names, as `check` reads it.
  String? overrideFingerprint(String docPath, String address, String? target) {
    final label = readLinkLabel(address);
    final from = _byPath[docPath];
    if (label is! OverrideLabel || from == null) return null;
    final upstream = _named(label.address.docPart, target);
    if (upstream == null) return null;
    final sectionKey = _overrideSectionKeyOf(from, upstream, label.itemId);
    if (sectionKey == null) return null;
    final text = itemTextIn(
      upstream.content,
      upstream.type,
      sectionKey: sectionKey,
      itemId: label.itemId,
    );
    return text == null ? null : fingerprintOf(text);
  }

  /// The key of the section the anchor of the override line of [from] that
  /// links the item [itemId] of [upstream] names; null when it holds none.
  String? _overrideSectionKeyOf(
    RenumberDoc from,
    RenumberDoc upstream,
    String itemId,
  ) {
    final facts = _factsOf(from);
    final upstreamFacts = _factsOf(upstream);
    for (final (at, _) in from.content.sections.indexed) {
      for (final item in sectionItemsAt(from.content, at, from.type)) {
        if (!isOverrideLine(item)) continue;
        final column = overrideTextStart(from.lines[item.line - 1]);
        final link = overrideLinkIn(facts, item.line, column);
        if (link == null || link.target != upstream.docPath) continue;
        final cite = readOverrideLinkIn(
          link,
          facts: upstreamFacts,
          content: upstream.content,
          type: upstream.type,
        ).cite;
        if (cite is ItemCite && cite.itemId == itemId) return cite.sectionKey;
      }
    }
    return null;
  }

  /// The link and anchor facts of [doc], read once, as the index reads them.
  LineFacts _factsOf(RenumberDoc doc) =>
      _facts[doc.docPath] ??= _lineFactsOf(DocParse.of(doc.lf), doc.docPath);

  LineFacts _lineFactsOf(DocParse parse, String docPath) => lineFactsOf(
    parse: parse,
    counted: parse,
    countedText: parse.lfText,
    docPath: docPath,
    sectionCounts: const [],
    frontmatterErrorLine: null,
    bodyTbrMarkers: const [],
    citeCandidates: const [],
    bareItemIds: const [],
    mermaidBlocks: const [],
    warnings: [],
  );

  /// The fingerprint of the block [row] of the record named [recordName]
  /// records: its FR's contract block, or the edge case it names; null when
  /// the row names no FR or block.
  String? rowFingerprint(String recordName, MatrixRow row) {
    final fr = _named('$frTypeId:$recordName/${row.item}', null);
    if (fr == null) return null;
    final text = switch (row.edgeCase) {
      null => contractBlockIn(fr.content, fr.type)?.text,
      final edgeCase => (_edgeCases[fr.docPath] ??= edgeCaseBlocksIn(
        fr.content,
        fr.type,
      ))[edgeCase],
    };
    return text == null ? null : fingerprintOf(text);
  }

  /// Whether the entry [label] [fingerprint] of the doc at [docPath] equals
  /// the fingerprint of its block.
  bool matches(String docPath, String label, String fingerprint) {
    final block = _blockOf(docPath, label);
    if (block == null) return false;
    return fingerprint == fingerprintOf(block);
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
    final BlockRef(docPath: blockPath, :key) = target;
    final doc = _byPath[blockPath];
    if (doc == null) return null;
    return (_blocks[blockPath] ??= trackedBlocksOf(doc))[key];
  }
}
