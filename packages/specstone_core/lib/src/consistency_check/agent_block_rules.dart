import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/setup_migration/agent_targets.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/version.dart';

const _migrateHint = 'run `specstone migrate`';

String _messageOf(AgentDriftKind kind) => switch (kind) {
  AgentDriftKind.blockStale =>
    'the Specstone block differs from what the running CLI writes; '
        '$_migrateHint',
  AgentDriftKind.agentMdStale =>
    '.specstone/AGENT.md differs from what the running CLI writes; '
        '$_migrateHint',
  AgentDriftKind.agentMdMissing =>
    'the block imports .specstone/AGENT.md, which is missing; $_migrateHint',
  AgentDriftKind.topUnlisted =>
    'the repository top is not in agent_file_roots yet; $_migrateHint',
  AgentDriftKind.markersMalformed =>
    'the Specstone marker lines are malformed and `specstone migrate` '
        'refuses the file; repair the block by hand',
  AgentDriftKind.codeFenceOpen =>
    'the code fence that opens on this line is unclosed and `specstone '
        'migrate` refuses the file; close the code fence that opens on this '
        'line',
};

// `migrate` runs on the Owner's word; a malformed marker or an open code fence
// is a hand repair the Agent makes.
WaitsFor _waitsForOf(AgentDriftKind kind) => switch (kind) {
  AgentDriftKind.blockStale ||
  AgentDriftKind.agentMdStale ||
  AgentDriftKind.agentMdMissing ||
  AgentDriftKind.topUnlisted => WaitsFor.owner,
  AgentDriftKind.markersMalformed ||
  AgentDriftKind.codeFenceOpen => WaitsFor.agent,
};

/// Returns one `agent_block_stale` finding per drift `agentFileDrifts` finds.
///
/// Each finding carries the file's path from the project root and no `name`.
/// The code roots come from `codeFoldersOf`, as `migrate` reads them.
Iterable<Finding> staleAgentBlocks(CheckContext context) sync* {
  final config = ProjectConfig.read(context.projectRoot);
  final drifts = agentFileDrifts(
    AgentFileInputs(
      projectRoot: context.projectRoot,
      cliVersion: specstoneVersion,
      codeRootFolders: codeFoldersOf(
        context.projectRoot,
        context.set,
        codeRoot: _codeRootFromProject(context),
      ),
      agentFileRoots: config.agentFileRoots,
    ),
  );
  for (final (:path, :line, :kind) in drifts) {
    yield Finding(
      kind: FindingKind.agentBlockStale,
      path: path,
      line: line,
      message: _messageOf(kind),
      waitsFor: _waitsForOf(kind),
    );
  }
}

/// Returns the code root as a `/`-separated path from the project root.
String _codeRootFromProject(CheckContext context) {
  final project = _segmentsOf(context.projectRoot);
  final code = _segmentsOf(context.codeRoot);
  var shared = 0;
  while (shared < project.length &&
      shared < code.length &&
      project[shared] == code[shared]) {
    shared++;
  }
  final steps = [
    for (var i = shared; i < project.length; i++) '..',
    ...code.skip(shared),
  ];
  return steps.isEmpty ? '.' : steps.join('/');
}

List<String> _segmentsOf(Directory folder) => [
  for (final segment in folder.uri.pathSegments)
    if (segment.isNotEmpty) segment,
];
