import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show scenarioIdPrefix;
import 'package:specstone_core/src/setup_migration/renumber_doc.dart';

/// Returns the blocks of [doc] a link tracks, keyed as a `confirmed` label
/// resolves to them: scenario blocks, gnfr NFR Statements, an FR's
/// Statement.
///
/// A lettered scenario is read from its line span (P5), since `check` keys
/// no block for it.
Map<String, String> trackedBlocksOf(RenumberDoc doc) => {
  if (doc.holdsScenarios) ..._scenarioBlocksOf(doc),
  if (doc.type.id == gnfrTypeId) ..._nfrStatementsOf(doc),
  if (doc.type.id == frTypeId) statementSectionId: ?doc.statementBody,
};

Map<String, String> _scenarioBlocksOf(RenumberDoc doc) => {
  ...doc.scenarioBlocks,
  for (final (:item, to: _, from: _, docPath: _) in doc.lettered)
    if (item.prefix == scenarioIdPrefix)
      scenarioBlockKeyOf(item.id!): doc.lines
          .sublist(item.line - 1, item.endLine)
          .join('\n'),
};

Map<String, String> _nfrStatementsOf(RenumberDoc doc) => {
  for (final item in doc.items)
    if (item.id case final id?) id.written: doc.statementOf(item),
};
