/// A record to create, as a draft: its DocPath and its laid-out text.
final class NewRecord {
  const new({required this.docPath, required this.text});

  final String docPath;
  final String text;
}
