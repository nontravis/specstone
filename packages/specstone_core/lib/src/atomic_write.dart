import 'dart:io';

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

/// Writes and flushes [bytes] to a temp sibling of [target] and returns it.
///
/// The temp is `.<target name>.<pid>.specstone.tmp` in [target]'s folder, so
/// the later rename stays on one volume. Creates no parent folder. Deletes the
/// partial temp and rethrows when the write fails.
///
/// Throws [FileSystemException] when the folder is missing or the write fails.
File writeTempSibling(File target, List<int> bytes) {
  final segments = target.uri.pathSegments.where((s) => s.isNotEmpty);
  final temp = File(
    '${target.parent.path}${Platform.pathSeparator}'
    '.${segments.last}.$pid.specstone.tmp',
  );
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
