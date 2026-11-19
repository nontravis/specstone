import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/mermaid_node_run.dart';
import 'package:specstone_core/src/consistency_check/mermaid_parser.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/index_query/diagram_parse.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/mermaid_blocks.dart';
import 'package:specstone_core/src/index_query/models/mermaid_block.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';

const _skipPrefix = 'Mermaid parse skipped: ';
const _notStoredPrefix = 'Mermaid parse results not stored: ';

final _whitespaceRun = RegExp(r'\s+');

/// The `diagram_parse_failed` findings of one run and the warnings its parse
/// adds.
final class MermaidParseReport {
  const new({required this.findings, required this.warnings});

  final List<Finding> findings;

  /// The skip warning, then the not-stored warning, each at most once.
  final List<String> warnings;
}

/// Returns a `diagram_parse_failed` finding for each Mermaid block of [docs]
/// the bundled parser refuses.
///
/// Stored results answer first; the blocks with none go, one per text, to a
/// single [runner] call, Node by default, whose answers are stored through
/// [session]. An Index that refuses the write keeps the findings and adds the
/// not-stored warning.
Future<MermaidParseReport> checkMermaidParses(
  ReadSession session,
  CheckContext context,
  List<IndexedDoc> docs, {
  MermaidNodeRun? runner,
}) async {
  final hashes = {
    for (final doc in docs) ..._blocksOf(context, doc).map((b) => b.hash),
  };
  final stored = session.store.diagramParsesOf(
    hashes,
    parserHash: mermaidParserHash,
  );
  final pending = _pendingBlocks(
    context,
    docs,
    hashes.difference(stored.keys.toSet()),
  );
  final fresh = pending.isEmpty
      ? const _FreshParse(rows: {}, warnings: [])
      : await _parseFresh(session, pending, runner ?? MermaidNodeRun());
  final results = {...stored, ...fresh.rows};
  return MermaidParseReport(
    findings: [for (final doc in docs) ..._findingsOf(context, doc, results)],
    warnings: fresh.warnings,
  );
}

/// Returns [raw] on one line: each whitespace run, line breaks included, made
/// one space, and the ends trimmed.
String oneLineMessage(String raw) => raw.trim().replaceAll(_whitespaceRun, ' ');

/// The rows one runner call answered, and the warnings it gave.
final class _FreshParse {
  const new({required this.rows, required this.warnings});

  final Map<String, DiagramParse> rows;
  final List<String> warnings;
}

List<MermaidBlock> _blocksOf(CheckContext context, IndexedDoc doc) =>
    context.contentOf(doc).lineFacts.mermaidBlocks;

/// Returns one block per text of [missing], read from the docs that hold it.
List<PendingBlock> _pendingBlocks(
  CheckContext context,
  List<IndexedDoc> docs,
  Set<String> missing,
) {
  if (missing.isEmpty) return const [];
  final pending = <String, PendingBlock>{};
  for (final doc in docs) {
    if (!_blocksOf(context, doc).any((b) => missing.contains(b.hash))) {
      continue;
    }
    final text = toLf(context.contentOf(doc).text);
    for (final source in mermaidSourcesOf(Doc.parse(text), text)) {
      final hash = source.hash;
      if (!missing.contains(hash)) continue;
      pending.putIfAbsent(
        hash,
        () => PendingBlock(hash: hash, text: source.text),
      );
    }
  }
  return [...pending.values];
}

Future<_FreshParse> _parseFresh(
  ReadSession session,
  List<PendingBlock> pending,
  MermaidNodeRun runner,
) async {
  final outcome = await runner.parse(pending);
  final rows = [for (final row in outcome.answered.values) _oneLined(row)];
  final notStored = rows.isEmpty ? null : _storeOf(session, rows);
  return _FreshParse(
    rows: {for (final row in rows) row.blockHash: row},
    warnings: [
      if (outcome.skipReason case final reason?) '$_skipPrefix$reason',
      ?notStored,
    ],
  );
}

/// Stores [rows] in one transaction; returns the not-stored warning when the
/// Index refuses the write.
String? _storeOf(ReadSession session, List<DiagramParse> rows) {
  try {
    session.writeIndex(
      (store) => store.putDiagramParses(rows, parserHash: mermaidParserHash),
    );
    return null;
  } on IndexFault catch (fault) {
    return '$_notStoredPrefix${fault.code.wire}';
  }
}

DiagramParse _oneLined(DiagramParse row) {
  final message = row.message;
  return DiagramParse(
    blockHash: row.blockHash,
    diagram: row.diagram,
    parses: row.parses,
    message: message == null ? null : oneLineMessage(message),
    blockLine: row.blockLine,
  );
}

Iterable<Finding> _findingsOf(
  CheckContext context,
  IndexedDoc doc,
  Map<String, DiagramParse> results,
) sync* {
  for (final block in _blocksOf(context, doc)) {
    final row = results[block.hash];
    if (row == null || row.parses) continue;
    yield context.finding(
      doc,
      FindingKind.diagramParseFailed,
      line: block.fenceLine + (row.blockLine ?? 0),
      message: row.message ?? '',
      keys: {'diagram': ?row.diagram},
    );
  }
}
