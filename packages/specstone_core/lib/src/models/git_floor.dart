/// The oldest git a check accepts, by major and minor number.
final class GitFloor {
  const new({required this.major, required this.minor});

  final int major;
  final int minor;
}
