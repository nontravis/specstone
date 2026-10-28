import 'dart:io';
import 'dart:math';

/// Source of the random part of a temp name; one per isolate.
final _random = Random.secure();

/// The owner write bit of a file mode.
const _ownerWriteBit = 0x80;

/// Whether the owner write bit of [file] is off, so an in-place write fails.
///
/// A rename replaces such a file whatever its mode, which is why a caller that
/// must keep a read-only file read-only checks first. The Dart VM maps the
/// Windows read-only attribute onto the same bit, so one check serves both.
/// A file that does not exist is not read-only.
bool isReadOnly(File file) {
  final stat = file.statSync();
  return stat.type != FileSystemEntityType.notFound &&
      stat.mode & _ownerWriteBit == 0;
}

/// Returns 64 random bits as 16 hex digits.
String _randomHex() => [
  for (var i = 0; i < 2; i++)
    _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0'),
].join();

/// Writes and flushes [bytes] to a temp sibling of [target] and returns it.
///
/// The temp is `.<target name>.<pid>.<random hex>.specstone.tmp` in [target]'s
/// folder, so the later rename stays on one volume. The random part keeps two
/// isolates of one process, which share a pid, off one temp, and the exclusive
/// create fails rather than reuse a temp that exists. Creates no parent folder.
/// Deletes the partial temp and rethrows when the write fails.
///
/// Throws [FileSystemException] when the folder is missing or the write fails.
File writeTempSibling(File target, List<int> bytes) {
  final segments = target.uri.pathSegments.where((s) => s.isNotEmpty);
  // Created outside the try: a temp that already exists is another writer's,
  // so the cleanup below must not delete it.
  final temp = File(
    '${target.parent.path}${Platform.pathSeparator}'
    '.${segments.last}.$pid.${_randomHex()}.specstone.tmp',
  )..createSync(exclusive: true);
  try {
    temp.writeAsBytesSync(bytes, flush: true);
  } on FileSystemException {
    if (temp.existsSync()) temp.deleteSync();
    rethrow;
  }
  return temp;
}

/// Replaces [target] with [bytes] so a reader never sees a partial file.
///
/// Deletes the temp sibling and rethrows when the write or the rename fails.
/// Creates no parent folder.
///
/// Throws [FileSystemException] when the folder is missing or the rename fails.
void writeFileAtomic(File target, List<int> bytes) {
  final temp = writeTempSibling(target, bytes);
  try {
    temp.renameSync(target.path);
  } on FileSystemException {
    if (temp.existsSync()) temp.deleteSync();
    rethrow;
  }
}
