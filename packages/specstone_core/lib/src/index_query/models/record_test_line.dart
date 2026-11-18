/// The item and test path of an `item:<test path>[:<test name>]` line.
final class RecordTestLine {
  const new({required this.item, required this.path});

  final String item;
  final String path;
}
