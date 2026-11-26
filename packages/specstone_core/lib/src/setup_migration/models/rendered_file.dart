/// A folder at a project or repository root that one host reads skills or
/// agents from.
enum AgentFolder {
  claudeSkills('.claude/skills', AgentFolderGroup.claudeCode),
  agentsSkills('.agents/skills', AgentFolderGroup.shared),
  claudeAgents('.claude/agents', AgentFolderGroup.claudeCode),
  cursorAgents('.cursor/agents', AgentFolderGroup.cursorAgents),
  codexAgents('.codex/agents', AgentFolderGroup.codexAgents),
  agentsAgents('.agents/agents', AgentFolderGroup.shared);

  new(this.path, this.group);

  /// The folder's path from the root, with `/` separators.
  final String path;

  /// The group that opts in or out as one.
  final AgentFolderGroup group;
}

/// Folders that stay together: a skill copy's relative agent path must resolve.
enum AgentFolderGroup {
  claudeCode,
  shared,
  codexAgents,
  cursorAgents;

  /// The name `agent_file_groups:` lists the group by.
  String get configName => switch (this) {
    claudeCode => 'claude_code',
    shared => 'shared',
    codexAgents => 'codex_agents',
    cursorAgents => 'cursor_agents',
  };

  /// Returns the group [name] is the [configName] of, or null for no group.
  static AgentFolderGroup? ofConfigName(String name) {
    for (final group in values) {
      if (group.configName == name) return group;
    }
    return null;
  }

  /// The group's folders, in [AgentFolder] order.
  List<AgentFolder> get folders => [
    for (final folder in AgentFolder.values)
      if (folder.group == this) folder,
  ];
}

/// One file a host reads: `entry` is the `specstone-<name>` folder or file name
/// in `folder`, and `path` runs from the folder's parent with `/` separators.
final class RenderedFile {
  const new({
    required this.folder,
    required this.entry,
    required this.path,
    required this.text,
  });

  final AgentFolder folder;
  final String entry;
  final String path;
  final String text;
}
