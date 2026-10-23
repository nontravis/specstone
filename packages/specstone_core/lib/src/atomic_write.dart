import 'dart:io';

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
