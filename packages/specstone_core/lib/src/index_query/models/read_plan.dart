/// One read of a read plan: the 1-based lines [first] to [last] of a file.
final class ReadRange {
  const new({required this.first, required this.last});

  final int first;
  final int last;
}

/// The reads that take a read-first file whole.
///
/// The [ranges] run contiguous from line 1 to the file's last line.
/// [overLimitLines] lists each line that alone holds more est. tokens than one
/// read holds; each is a range of its own.
final class ReadPlan {
  const new({required this.ranges, required this.overLimitLines});

  final List<ReadRange> ranges;
  final List<int> overLimitLines;
}
