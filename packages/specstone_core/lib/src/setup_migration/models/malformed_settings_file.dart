/// A `.claude/settings.json` or `.codex/hooks.json` no run can merge into: its
/// path from the project root, and why it does not parse.
final class MalformedSettingsFile {
  const new({required this.path, required this.failure});

  final String path;
  final String failure;
}
