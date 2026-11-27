import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/rendering/format_run.dart';
import 'package:specstone_core/src/rendering/formatter.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';

/// The kind a grouped features doc reports when its group features docs lag.
const _companionLagKind = 'features';

/// Returns the `generated_block_stale` finding of [doc] when `format --check`
/// would list it for its generated blocks.
///
/// The finding sits at the opening marker of the first stale block, else at
/// line 1. A doc whose type lists no generator costs nothing, and a block a
/// generator of [registry] cannot resolve gives none. A doc `format` refuses,
/// or whose group a refused companion blocks, gives none, since `format`
/// would not write it; the refusal has a finding of its own.
Iterable<Finding> checkGeneratedBlocks(
  CheckContext context,
  IndexedDoc doc,
  GeneratorRegistry<DocIndex> registry,
) sync* {
  final type = context.typeOf(doc);
  if (type == null || type.listedGenerators.isEmpty) return;
  final parsed = context.parsedOf(doc);
  // One layout serves the doc's own blocks and its companions.
  final outcome = formatDoc(parsed, type);
  if (outcome is Refused) return;
  final keepsCompanions = type.listedGenerators.any(
    (kind) => registry.companionsOf(kind) != null,
  );
  final companions = keepsCompanions
      ? companionsStateOf(
          context.project,
          doc.docPath,
          registry,
          context.index,
          outcome: outcome,
        )
      : CompanionsState.current;
  if (companions == CompanionsState.blocked) return;
  final own = staleBlockOf(
    parsed,
    type,
    registry,
    context.index,
    docPath: doc.docPath,
  );
  final stale = companions == CompanionsState.lagging
      ? StaleBlock(kind: _companionLagKind, line: own?.line)
      : own;
  if (stale == null) return;
  yield context.finding(
    doc,
    FindingKind.generatedBlockStale,
    line: stale.line ?? 1,
    message:
        'generated block ${stale.kind} is stale; '
        'run specstone format ${doc.docPath}',
  );
}
