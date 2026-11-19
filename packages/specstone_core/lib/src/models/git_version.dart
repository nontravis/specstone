/// A version `git --version` names: the full version, such as `2.39.3`, and its
/// major and minor numbers.
final class GitVersion {
  const new({required this.text, required this.major, required this.minor});

  final String text;
  final int major;
  final int minor;
}
