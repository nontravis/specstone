import 'dart:convert';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/consistency_check/tracked_links.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show
        OverrideLabel,
        ScenarioLabel,
        ScenarioRef,
        edgeCasesSectionKey,
        linkIdentityOf,
        readLinkLabel;
import 'package:specstone_core/src/document_writing/item_moves.dart';
import 'package:specstone_core/src/document_writing/models/path_move.dart';
import 'package:specstone_core/src/document_writing/move_item.dart'
    show ItemLanding;
import 'package:specstone_core/src/document_writing/moved_paths.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/matrix_rows.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/setup_migration/stamp_pass.dart'
    show withEntriesRestamped;
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/template_fault.dart';

const _entryKeys = ['confirmed', 'overrides'];

/// Where each block a restructure call moves sits after the call.
final class BlockMoves {
  /// Moves no block: each keeps its address.
  const new none() : _moves = null;

  /// The blocks an item move lands: a scenario, an edge case, or an item sits
  /// at its landing's doc and ID.
  new of(this._moves);

  final ItemMoves? _moves;

  /// Whether the call moves any block.
  bool get movesBlocks => _moves != null;

  /// Returns the moved block the entry [label] of [holder] names before the
  /// call, in any name form; null when it names none.
  TrackedBlock? namedBy(DocIndex index, IndexedDoc holder, String label) {
    final moves = _moves;
    if (moves == null) return null;
    return switch (readLinkLabel(label)) {
      ScenarioLabel(:final ref) => _scenarioNamed(moves, index, holder, ref),
      OverrideLabel(:final address, :final itemId) => _itemNamed(
        moves,
        index,
        address.docPart,
        itemId,
      ),
      _ => null,
    };
  }

  /// Returns the address [before] has after the call.
  TrackedBlock afterOf(TrackedBlock before) {
    final landing = _landingOf(before);
    if (landing == null) return before;
    return TrackedBlock(
      kind: before.kind,
      upstream: landing.to.docPath,
      key: landing.newId,
      section: before.section,
    );
  }

  ItemLanding? _landingOf(TrackedBlock block) {
    final landing = _moves?.landingOf(block.upstream, block.key);
    if (landing == null) return null;
    return switch (block.kind) {
      TrackedBlockKind.scenario => landing.isScenario ? landing : null,
      TrackedBlockKind.edgeCase =>
        landing.sectionKey == edgeCasesSectionKey ? landing : null,
      TrackedBlockKind.item =>
        landing.sectionKey == block.section ? landing : null,
      TrackedBlockKind.frStatement || TrackedBlockKind.nfrStatement => null,
    };
  }
}

TrackedBlock? _scenarioNamed(
  ItemMoves moves,
  DocIndex index,
  IndexedDoc holder,
  ScenarioRef ref,
) {
  final number = ref.scenario;
  final storyName = ref.storyName;
  final story = storyName == null
      ? (holder.docTypeId == frType ? index.parentOf(holder) : null)
      : _docNamed(index, '$storyType:$storyName');
  if (number == null || story == null) return null;
  final key = 'S$number';
  final landing = moves.landingOf(story.docPath, key);
  if (landing == null || !landing.isScenario) return null;
  return TrackedBlock(
    kind: TrackedBlockKind.scenario,
    upstream: story.docPath,
    key: key,
  );
}

TrackedBlock? _itemNamed(
  ItemMoves moves,
  DocIndex index,
  String address,
  String itemId,
) {
  final doc = _docNamed(index, address);
  final landing = doc == null ? null : moves.landingOf(doc.docPath, itemId);
  if (doc == null || landing == null) return null;
  return TrackedBlock(
    kind: TrackedBlockKind.item,
    upstream: doc.docPath,
    key: itemId,
    section: landing.sectionKey,
  );
}

/// Returns the one doc [address] names, or null.
IndexedDoc? _docNamed(DocIndex index, String address) {
  try {
    final named = index.resolve(address);
    return named.length == 1 ? named.single : null;
  } on IndexFault {
    return null;
  } on TemplateFault {
    return null;
  }
}

/// The one re-stamp pass of a `move`, `rename`, or reorder: each tracked
/// entry that matched its block before the call takes the block's
/// fingerprint after it, when the call changed the block.
///
/// A stale entry, an entry with no fingerprint, and an entry whose block
/// keeps its text keep their value. An entry whose label names a moved block,
/// in any name form, is judged though no tracked link pairs it.
///
/// The call may rewrite an entry's label or a row's item, so an entry is found
/// again in a written text by its place in its doc's key block, kept only while
/// the block holds as many entries as before, and a row, which a call may carry
/// to another record, by its literal and recorded fingerprint. When two rows
/// found so would take two values, both keep their own.
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
      final text =
          before[doc.docPath] ?? toLf(session.index.contentOf(doc).text);
      final written = <String, List<_Written>>{};
      for (final entry in [
        ...trackedEntriesOf(judge.beforeContext, doc),
        ..._namedEntriesOf(blocks, session.index, doc, text, written),
      ]) {
        final recorded = entry.recorded;
        if (recorded == null) continue;
        final locator = _locatorOf(entry, recorded, text, written);
        if (locator == null ||
            (!locator.isRow && values.containsKey(locator))) {
          continue;
        }
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
    final rows = {
      for (final locator in found.keys)
        if (locator.isRow) locator,
    };
    final held = _heldCounts(session, probe, rows, before);
    // A row the pass never judged that shares a locator, such as a row naming
    // no traced edge case, would take the stamp too, so the locator stays.
    final stamps = {
      for (final MapEntry(key: locator, value: stamp) in found.entries)
        if (!locator.isRow || held[locator] == judged[locator]) locator: stamp,
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
      text = _entriesStamped(docPath, text, key, stampOf);
    }
    final recordType = _session.index.set.recordDocType;
    final isRecord =
        recordType != null && _session.docTypeAt(docPath)?.id == recordType.id;
    return isRecord ? _rowsStamped(text, recordType, stampOf) : text;
  }

  String _entriesStamped(
    String docPath,
    String lfText,
    String key,
    String? Function(_Locator locator) stampOf,
  ) {
    final count = _writtenEntriesOf(lfText, key).length;
    String? stamp;
    return withEntriesRestamped(
      lfText,
      key,
      // `after` runs right after `matched` returns true for the same entry.
      matched: (index, _, fingerprint) =>
          (stamp = stampOf(
            _Locator.entry(key, fingerprint, docPath, index, count),
          )) !=
          null,
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
      final locator = _Locator.row(recorded, matrixRowLiteralOf(row));
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

/// Finds an entry in a written text: a `confirmed` or `overrides` entry by its
/// doc, its place in its key block, and the entries that block holds; a row by
/// its literal. Both carry the recorded fingerprint.
final class _Locator {
  const new entry(
    this.entryKey,
    this.recorded,
    String this.docPath,
    int this.index,
    int this.count,
  ) : literal = null;

  const new row(this.recorded, String this.literal)
    : entryKey = verificationMatrixKey,
      docPath = null,
      index = null,
      count = null;

  final String entryKey;
  final String recorded;
  final String? literal;
  final String? docPath;
  final int? index;
  final int? count;

  bool get isRow => literal != null;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is _Locator &&
      other.entryKey == entryKey &&
      other.recorded == recorded &&
      other.literal == literal &&
      other.docPath == docPath &&
      other.index == index &&
      other.count == count;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode =>
      Object.hash(entryKey, recorded, literal, docPath, index, count);
}

/// Returns the entries of [doc], whose text before the call is [lfText], that
/// name a block [blocks] moves, though no tracked link of the doc pairs them.
///
/// [written] holds the entries read so far, by key.
Iterable<TrackedEntry> _namedEntriesOf(
  BlockMoves blocks,
  DocIndex index,
  IndexedDoc doc,
  String lfText,
  Map<String, List<_Written>> written,
) sync* {
  if (!blocks.movesBlocks) return;
  for (final key in _entryKeys) {
    for (final item in written[key] ??= _writtenEntriesOf(lfText, key)) {
      if (blocks.namedBy(index, doc, item.label) case final block?) {
        yield TrackedEntry(
          docPath: doc.docPath,
          entryKey: key,
          label: item.label,
          block: block,
          recorded: item.fingerprint,
        );
      }
    }
  }
}

/// One entry of a `confirmed` or `overrides` block as written.
final class _Written {
  const new(this.label, this.fingerprint);

  final String label;
  final String fingerprint;
}

/// Returns the entries of the frontmatter key [key] of [lfText], in order.
List<_Written> _writtenEntriesOf(String lfText, String key) {
  final written = <_Written>[];
  withEntriesRestamped(
    lfText,
    key,
    matched: (_, label, fingerprint) {
      written.add(_Written(label, fingerprint));
      return false;
    },
    after: (_) => null,
  );
  return written;
}

/// Returns where [entry], recording [recorded], sits in [lfText], its doc
/// before the call; null when no entry of that label and fingerprint is there.
///
/// [written] holds the entries read so far, by key.
_Locator? _locatorOf(
  TrackedEntry entry,
  String recorded,
  String lfText,
  Map<String, List<_Written>> written,
) {
  final literal = entry.literal;
  if (literal != null) return _Locator.row(recorded, literal);
  final held = written[entry.entryKey] ??= _writtenEntriesOf(
    lfText,
    entry.entryKey,
  );
  final identity = linkIdentityOf(entry.label);
  final index = held.indexWhere(
    (item) =>
        item.fingerprint == recorded && linkIdentityOf(item.label) == identity,
  );
  return index < 0
      ? null
      : _Locator.entry(
          entry.entryKey,
          recorded,
          entry.docPath,
          index,
          held.length,
        );
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
