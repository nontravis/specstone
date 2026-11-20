/// One embedded skill or agent file: its `path` under `assets/agent/`, with
/// `/` separators, and its LF `text`.
final class AgentAsset {
  const new({required this.path, required this.text});

  final String path;
  final String text;
}
