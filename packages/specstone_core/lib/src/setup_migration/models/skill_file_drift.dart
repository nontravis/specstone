/// Why a skill or agent file needs a run.
enum SkillFileDriftKind {
  /// The file's bytes differ from what the CLI writes.
  differs,

  /// The file is missing from a folder of a group in use.
  missing,

  /// The CLI no longer ships the file.
  unshipped,

  /// `.claude/settings.json` or `.codex/hooks.json` does not hold the Specstone
  /// hook groups of its file alone.
  settingsStale,

  /// `.claude/settings.json` is missing from a Claude Code folder group in use,
  /// or `.codex/hooks.json` from a Codex agents group in use.
  settingsMissing,

  /// `.claude/settings.json` or `.codex/hooks.json` is no JSON object a run can
  /// merge into.
  settingsMalformed,
}

/// One drift: its path from the project root, `/`-separated, and its kind.
final class SkillFileDrift {
  const new({required this.path, required this.kind});

  final String path;
  final SkillFileDriftKind kind;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is SkillFileDrift && other.path == path && other.kind == kind;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(path, kind);
}
