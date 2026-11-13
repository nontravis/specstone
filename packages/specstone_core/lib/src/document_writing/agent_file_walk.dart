import 'package:specstone_core/src/setup_migration/agent_files.dart'
    show agentInstructionNames;

const _separator = '/';

/// Folders whose every file is an agent file.
const _agentFolders = {'.claude', '.agents', '.codex', '.cursor'};

/// Whether [projectPath], a `/`-separated path from the project root, is an
/// agent file: an instruction file the CLI writes a block into, or any file
/// under an agent folder.
///
/// A path matches at any depth, since each repository top holds its own.
bool isAgentFile(String projectPath) {
  final segments = projectPath.split(_separator);
  if (agentInstructionNames.any(
    (name) => projectPath == name || projectPath.endsWith('$_separator$name'),
  )) {
    return true;
  }
  return segments.take(segments.length - 1).any(_agentFolders.contains);
}
