import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/setup_migration/agent_targets.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/version.dart';

const _codeField = 'code';
const _migrateHint = 'run `specstone migrate`';

const Map<AgentDriftKind, String> _messages = {
  AgentDriftKind.blockStale:
      'the Specstone block differs from what the running CLI writes; '
      '$_migrateHint',
  AgentDriftKind.agentMdStale:
      '.specstone/AGENT.md differs from what the running CLI writes; '
      '$_migrateHint',
  AgentDriftKind.agentMdMissing:
      'the block imports .specstone/AGENT.md, which is missing; '
      '$_migrateHint',
  AgentDriftKind.topUnlisted:
      'the repository top is not in agent_file_roots yet; $_migrateHint',
  AgentDriftKind.markersMalformed:
      'the Specstone marker lines are malformed and `specstone migrate` '
      'refuses the file; repair the block by hand',
};

/// Returns one `agent_block_stale` finding per drift `agentFileDrifts` finds.
///
/// Each finding carries the file's path from the project root and no `name`.
/// The code entries come from the index as `uncoveredCode` reads them.
Iterable<Finding> staleAgentBlocks(CheckContext context) sync* {
  final config = ProjectConfig.read(context.projectRoot);
  final drifts = agentFileDrifts(
    AgentFileInputs(
      projectRoot: context.projectRoot,
      cliVersion: specstoneVersion,
      codeRootFolders: codeRootFolders(
        context.projectRoot,
        codeRoot: config.codeRoot,
        codeEntries: _codeEntries(context),
      ),
      agentFileRoots: config.agentFileRoots,
    ),
  );
  for (final (:path, :line, :kind) in drifts) {
    yield Finding(
      kind: FindingKind.agentBlockStale,
      path: path,
      line: line,
      message: _messages[kind]!,
    );
  }
}

Iterable<String> _codeEntries(CheckContext context) sync* {
  for (final doc in context.index.docs) {
    if (!context.typeHoldsField(context.typeOf(doc), _codeField)) continue;
    for (final (:value, line: _, text: _)
        in context.linesOf(doc).entriesOf(_codeField)) {
      if (value is String) yield value;
    }
  }
}
