import 'dart:convert';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/consistency_check/tracked_links.dart';
import 'package:specstone_core/src/document_writing/models/path_move.dart';
import 'package:specstone_core/src/document_writing/moved_paths.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/matrix_rows.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/setup_migration/stamp_pass.dart'
    show withEntriesRestamped;
import 'package:specstone_core/src/templates/merged_doc_type.dart';

const _entryKeys = ['confirmed', 'overrides'];

/// Where each block a restructure call moves sits after the call.
final class BlockMoves {
  /// Moves no block: each keeps its address.
  const new none();

  /// Returns the address [before] has after the call.
  TrackedBlock afterOf(TrackedBlock before) => before;
}

/// The one re-stamp pass of a `move`, `rename`, or reorder: each tracked
/// entry that matched its block before the call takes the block's
/// fingerprint after it, when the call changed the block.
///
/// A stale entry, an entry with no fingerprint, and an entry whose block
/// keeps its text keep their value. An entry is found again in a written text
/// by its key, its recorded fingerprint, and a row's literal, since the call
/// may rewrite its label or item; when two entries found so would take two
/// values, both keep their own.
final class RestampPass {
  new _(this._session, this._stamps, this.onlyRestamped);

  /// Plans the pass over [before] and [after], the text of each doc the call
  /// rewrites before and after its rewrite, laid out, keyed by its DocPath
  /// before the call, in LF.
  ///
  /// Every doc that can hold an entry is read; only an entry whose block
  /// sits in a doc the call writes or moves is judged.
  factory plan(
    WriteSession session, {
    required Map<String, String> before,
    required Map<String, String> after,
    required List<PathMove> moves,
    BlockMoves blocks = const BlockMoves.none(),
  }) {
    final changed = {
      ...after.keys,
      for (final doc in session.index.docs)
        if (movedPath(doc.docPath, moves) != doc.docPath) doc.docPath,
    };
    final judge = _Judge(
      beforeContext: session.checkContext(
        contents: _contentsOf(session, before),
      ),
      afterContext: session.checkContext(contents: _contentsOf(session, after)),
      changed: changed,
      blocks: blocks,
    );
    final values = <_Locator, Set<String>>{};
    final holders = <_Locator, Set<String>>{};
    final judged = <_Locator, int>{};
    for (final doc in session.index.docs) {
      for (final entry in trackedEntriesOf(judge.beforeContext, doc)) {
        final recorded = entry.recorded;
        if (recorded == null) continue;
        final locator = _Locator(entry.entryKey, recorded, entry.literal);
        (values[locator] ??= {}).add(judge.valueAfter(entry, recorded));
        (holders[locator] ??= {}).add(entry.docPath);
        judged[locator] = (judged[locator] ?? 0) + 1;
      }
    }
    final found = {
      for (final MapEntry(key: locator, value: afters) in values.entries)
        if (afters.length == 1 && afters.single != locator.recorded)
          locator: afters.single,
    };
    final probe = RestampPass._(session, const {}, const []);
    final held = _heldCounts(session, probe, found.keys.toSet(), before);
    // An entry the pass never judged that shares a locator, such as an entry
    // naming no traced link, would take the stamp too, so the locator stays.
    final stamps = {
      for (final MapEntry(key: locator, value: stamp) in found.entries)
        if (held[locator] == judged[locator]) locator: stamp,
    };
    final pass = RestampPass._(session, stamps, const []);
    return RestampPass._(session, stamps, [
      for (final docPath in {
        for (final locator in stamps.keys) ...holders[locator]!,
      })
        if (!after.containsKey(docPath) && pass._changes(docPath)) docPath,
    ]);
  }

  final WriteSession _session;
  final Map<_Locator, String> _stamps;

  /// The DocPaths, before the call, of the docs the pass alone changes.
  final List<String> onlyRestamped;

  /// Returns [lfText], the text of the doc at [docPath] before the call, with
  /// each entry the pass re-stamps set to its new fingerprint.
  String apply(String docPath, String lfText) => _stamps.isEmpty
      ? lfText
      : _withStamps(docPath, lfText, (locator) => _stamps[locator]);

  bool _changes(String docPath) {
    final bytes = _session.readDocBytes(docPath);
    if (bytes == null) return false;
    final lfText = toLf(utf8.decode(bytes));
    return apply(docPath, lfText) != lfText;
  }

  /// Returns [lfText] with each `confirmed` or `overrides` entry, and each
  /// row of a record, set to the value [stampOf] gives its locator.
  String _withStamps(
    String docPath,
    String lfText,
    String? Function(_Locator locator) stampOf,
  ) {
    var text = lfText;
    for (final key in _entryKeys) {
      text = _entriesStamped(text, key, stampOf);
    }
    final recordType = _session.index.set.recordDocType;
    final isRecord =
        recordType != null && _session.docTypeAt(docPath)?.id == recordType.id;
    return isRecord ? _rowsStamped(text, recordType, stampOf) : text;
  }

  String _entriesStamped(
    String lfText,
    String key,
    String? Function(_Locator locator) stampOf,
  ) {
    String? stamp;
    return withEntriesRestamped(
      lfText,
      key,
      // `after` runs right after `matched` returns true for the same entry.
      matched: (_, _, fingerprint) =>
          (stamp = stampOf(_Locator(key, fingerprint, null))) != null,
      after: (_) => stamp,
    ).lfText;
  }

  String _rowsStamped(
    String lfText,
    MergedDocType recordType,
    String? Function(_Locator locator) stampOf,
  ) {
    final lines = lfText.split('\n');
    for (final row in matrixLinesIn(
      lfText,
      recordType,
    ).whereType<MatrixRow>()) {
      final recorded = row.fingerprint;
      if (recorded == null) continue;
      final locator = _Locator(
        verificationMatrixKey,
        recorded,
        matrixRowLiteralOf(row),
      );
      final stamp = stampOf(locator);
      if (stamp == null) continue;
      final line = lines[row.line - 1];
      final at = line.lastIndexOf(recorded);
      lines[row.line - 1] = line.replaceRange(at, at + recorded.length, stamp);
    }
    return lines.join('\n');
  }
}

/// Judges one entry: its value after the call.
final class _Judge {
  new({
    required this.beforeContext,
    required this.afterContext,
    required Set<String> changed,
    required BlockMoves blocks,
  }) : _changed = changed,
       _blocks = blocks;

  final CheckContext beforeContext;
  final CheckContext afterContext;
  final Set<String> _changed;
  final BlockMoves _blocks;
  final _beforeTexts = <TrackedBlock, String?>{};
  final _afterTexts = <TrackedBlock, String?>{};

  /// Returns the fingerprint [entry], recording [recorded], holds after the
  /// call: its block's after the call when it matched the block before it.
  String valueAfter(TrackedEntry entry, String recorded) {
    final block = entry.block;
    final moved = _blocks.afterOf(block);
    if (!_changed.contains(block.upstream) &&
        !_changed.contains(moved.upstream)) {
      return recorded;
    }
    final beforeText = _beforeTexts.putIfAbsent(
      block,
      () => trackedBlockTextOf(beforeContext, block),
    );
    if (beforeText == null || fingerprintOf(beforeText) != recorded) {
      return recorded;
    }
    final afterText = _afterTexts.putIfAbsent(
      moved,
      () => trackedBlockTextOf(afterContext, moved),
    );
    return afterText == null ? recorded : fingerprintOf(afterText);
  }
}

/// Finds an entry in a written text: its key, its recorded fingerprint, and
/// a row's literal.
final class _Locator {
  const new(this.entryKey, this.recorded, this.literal);

  final String entryKey;
  final String recorded;
  final String? literal;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is _Locator &&
      other.entryKey == entryKey &&
      other.recorded == recorded &&
      other.literal == literal;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(entryKey, recorded, literal);
}

/// Returns how many entries and rows of each of [locators] every doc holds
/// before the call: each indexed doc, and each doc of [before] the index
/// lacks.
///
/// A doc's text is its [before] text, else its indexed text; a doc whose text
/// holds none of the locators' fingerprints is not parsed.
Map<_Locator, int> _heldCounts(
  WriteSession session,
  RestampPass probe,
  Set<_Locator> locators,
  Map<String, String> before,
) {
  final counts = <_Locator, int>{};
  if (locators.isEmpty) return counts;
  final fingerprints = {for (final locator in locators) locator.recorded};
  void count(String docPath, String lfText) {
    if (!fingerprints.any(lfText.contains)) return;
    probe._withStamps(docPath, lfText, (locator) {
      if (locators.contains(locator)) {
        counts[locator] = (counts[locator] ?? 0) + 1;
      }
      return null;
    });
  }

  for (final doc in session.index.docs) {
    count(
      doc.docPath,
      before[doc.docPath] ?? toLf(session.index.contentOf(doc).text),
    );
  }
  for (final MapEntry(key: docPath, value: lfText) in before.entries) {
    if (session.index.at(docPath) == null) count(docPath, lfText);
  }
  return counts;
}

/// Returns the content of each of [texts], parsed as the doc at its DocPath.
Map<String, DocContent> _contentsOf(
  WriteSession session,
  Map<String, String> texts,
) => {
  for (final MapEntry(key: docPath, value: lfText) in texts.entries)
    docPath: parseIndexedDoc(
      docPath: docPath,
      bytes: utf8.encode(lfText),
      match: session.project.matcher.match(docPath),
      statusesOutside: session.project.statusesOutsideApproval,
    ).content,
};
