/// One commit `git log` printed: its short sha, its subject (the first
/// paragraph), and its whole message.
final class GitCommit {
  const new({required this.sha, required this.subject, required this.message});

  final String sha;
  final String subject;
  final String message;
}
