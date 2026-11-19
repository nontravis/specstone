/// The one file a fault names, the latest loaded, and the other files it names,
/// ascending; `file` is null when it names none.
final class RankedFaultFiles {
  const new({required this.file, required this.related});

  final String? file;
  final List<String> related;
}
