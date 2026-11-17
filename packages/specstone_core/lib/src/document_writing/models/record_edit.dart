/// A record that loses or changes entries: its DocPath, its bytes as read, the
/// items whose entries change, and its text after the change.
final class RecordEdit {
  const new({
    required this.docPath,
    required this.bytes,
    required this.entries,
    required this.lfText,
  });

  final String docPath;
  final List<int> bytes;
  final List<String> entries;
  final String lfText;
}
