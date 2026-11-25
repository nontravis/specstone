/// The stat values of a file that stand in for its content between refreshes.
///
/// - `size`: in bytes.
/// - `modified`: the mtime, in microseconds since the epoch.
/// - `changed`: the ctime on POSIX, the creation time on Windows, in
///   microseconds since the epoch.
/// - `mode`: the permission and type bits.
final class FileStatKey {
  const new({
    required this.size,
    required this.modified,
    required this.changed,
    required this.mode,
  });

  final int size;
  final int modified;
  final int changed;
  final int mode;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is FileStatKey &&
      other.size == size &&
      other.modified == modified &&
      other.changed == changed &&
      other.mode == mode;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(size, modified, changed, mode);
}
