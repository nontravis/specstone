/// The reasons an agent file differs from what the CLI writes.
enum AgentDriftKind {
  /// A block, or a rules file, differs from what the CLI writes.
  blockStale,

  /// `.specstone/AGENT.md` holds other bytes.
  agentMdStale,

  /// An import block names a `.specstone/AGENT.md` that is missing.
  agentMdMissing,

  /// A repository top that `agent_file_roots` does not list.
  topUnlisted,

  /// The Specstone marker lines of a file are malformed.
  markersMalformed,

  /// A code fence of a file is still open at its end.
  codeFenceOpen,
}

/// One drift: its path from the project root, `/`-separated, its 1-based
/// line, and its kind.
final class AgentDrift {
  const new({required this.path, required this.line, required this.kind});

  final String path;
  final int line;
  final AgentDriftKind kind;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is AgentDrift &&
      other.path == path &&
      other.line == line &&
      other.kind == kind;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(path, line, kind);
}
