/// A draft's `<doc type>:<name>` and the whole-doc `base` hash the call
/// carries for it, taken from `approve --dry-run` or `get --json`.
final class SeenDraft {
  const new({required this.name, required this.hash});

  final String name;
  final String hash;
}
