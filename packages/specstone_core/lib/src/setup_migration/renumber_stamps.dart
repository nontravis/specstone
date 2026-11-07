import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/rendering/formatter.dart' show layOutDoc;
import 'package:specstone_core/src/setup_migration/renumber_doc.dart';

// MARK: - Types

/// A `confirmed` entry's fingerprint before the renumber pass and the one a
/// matched entry records.
typedef Stamp = ({String before, String after});

/// The stamps of the run, keyed by the upstream doc and the block's key
/// before the pass.
typedef Stamps = Map<(String, String), Stamp>;

/// A block a link tracks: its key before and after the pass, and its text
/// before.
typedef _TrackedBlock = ({
  TrackedBlockKind kind,
  String key,
  String newKey,
  String before,
});

// MARK: - Stamps

/// Returns the fingerprints of each tracked block of [docs] whose ID tokens
/// the pass rewrites, the renumbered blocks included (R60, P25).
///
/// [rewritten] holds the text after the body rewrite, before layout, of
/// each doc the pass changed. The new fingerprint reads the doc's final text,
/// laid out as `format` lays it out, so the first `check` after the run
/// matches it (P5). Each changed doc is read once more, and once again only
/// when the layout changes it.
Stamps stampsOf(Iterable<RenumberDoc> docs, Map<String, String> rewritten) {
  final stamps = <(String, String), Stamp>{};
  for (final doc in docs) {
    final passedText = rewritten[doc.docPath];
    if (passedText == null || passedText == doc.lf) continue;
    final blocks = _trackedBlocksOf(doc);
    if (blocks.isEmpty) continue;
    final passed = RenumberDoc(doc.docPath, passedText, doc.type);
    final laidOut = layOutDoc(passedText, doc.type);
    final finalDoc = laidOut == passedText
        ? passed
        : RenumberDoc(doc.docPath, laidOut, doc.type);
    for (final (:kind, :key, :newKey, :before) in blocks) {
      final beforeFingerprint = fingerprintOf(before);
      final passedBlock = passed.trackedText(kind, newKey);
      if (fingerprintOf(passedBlock) == beforeFingerprint) continue;
      stamps[(doc.docPath, key)] = (
        before: beforeFingerprint,
        after: fingerprintOf(finalDoc.trackedText(kind, newKey)),
      );
    }
  }
  return stamps;
}

/// The blocks of [doc] a link tracks, each with its key before and after
/// the pass: scenario blocks, `gnfr` NFR Statements, an FR's Statement.
List<_TrackedBlock> _trackedBlocksOf(RenumberDoc doc) => [
  if (doc.holdsScenarios) ..._scenarioBlocksOf(doc),
  if (doc.type.id == gnfrTypeId) ..._nfrStatementsOf(doc),
  if (doc.type.id == frTypeId)
    if (doc.statementBody case final body?)
      (
        kind: TrackedBlockKind.frStatement,
        key: statementSectionId,
        newKey: statementSectionId,
        before: body,
      ),
];

/// The scenario blocks of [doc]; a lettered one is read from its line
/// span (P5), since `check` keys no block for it.
List<_TrackedBlock> _scenarioBlocksOf(RenumberDoc doc) => [
  for (final MapEntry(key: ref, value: text) in doc.scenarioBlocks.entries)
    (kind: TrackedBlockKind.scenario, key: ref, newKey: ref, before: text),
  for (final (:item, :to, from: _, docPath: _) in doc.lettered)
    if (item.prefix == scenarioIdPrefix)
      (
        kind: TrackedBlockKind.scenario,
        key: scenarioBlockKeyOf(item.id!),
        newKey: scenarioBlockKeyOfId(to),
        before: doc.lines.sublist(item.line - 1, item.endLine).join('\n'),
      ),
];

List<_TrackedBlock> _nfrStatementsOf(RenumberDoc doc) {
  final toAt = {
    for (final lettered in doc.lettered) lettered.item.line: lettered.to,
  };
  return [
    for (final item in doc.items)
      if (item.id case final id?)
        (
          kind: TrackedBlockKind.nfrStatement,
          key: id.written,
          newKey: toAt[item.line] ?? id.written,
          before: doc.statementOf(item),
        ),
  ];
}
