import 'dart:io';

import 'package:specstone_core/src/release_version.dart';
import 'package:specstone_core/src/setup_migration/agent_targets.dart'
    show AgentFileInputs, agentFileDrifts;
import 'package:specstone_core/src/setup_migration/skill_agent_files.dart'
    show skillAndAgentFileDrifts;
import 'package:specstone_core/src/templates/project_config.dart'
    show
        AgentFilesStampUnreadable,
        AgentFilesStampVersion,
        readAgentFilesVersion;

/// Returns the one line that names the fix when the agent files at
/// [projectRoot] differ from what the binary writes, else null.
///
/// Judges the project root alone, with no code root and so no repository top,
/// and reads only `agent_files_version` from the config. A stamp that does not
/// read gives no line. [runningVersion] is the Version the line names.
String? staleProjectLine(
  Directory projectRoot, {
  required String runningVersion,
}) {
  final stamp = readAgentFilesVersion(projectRoot);
  if (stamp is AgentFilesStampUnreadable) return null;
  final inputs = AgentFileInputs(
    projectRoot: projectRoot,
    cliVersion: runningVersion,
    codeRootFolders: const [],
    agentFileRoots: const [],
  );
  if (agentFileDrifts(inputs).isEmpty &&
      skillAndAgentFileDrifts(inputs).isEmpty) {
    return null;
  }
  final version = switch (stamp) {
    AgentFilesStampVersion(:final version) => version,
    _ => null,
  };
  final running = ReleaseVersion.tryParse(runningVersion);
  final order = version == null || running == null
      ? null
      : version.compareTo(running);
  const lead = "specstone: this project's agent files";
  return switch (order) {
    final order? when order > 0 =>
      '$lead come from specstone $version, newer than this specstone '
          '$runningVersion; run specstone upgrade',
    0 =>
      '$lead differ from what specstone $runningVersion writes; '
          'run specstone migrate',
    _ =>
      '$lead are older than specstone $runningVersion; run specstone migrate',
  };
}
