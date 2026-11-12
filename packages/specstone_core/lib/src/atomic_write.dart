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
/// create fails rather than reuse a temp that exists. The empty temp takes the
/// permission bits of a [target] that exists before any byte lands, so no
/// other user reads the new text of a private file. Creates no parent folder.
/// Deletes the partial temp and rethrows when the write fails.
///
/// Throws [FileSystemException] when the folder is missing, the mode cannot be
/// copied, or the write fails.
File writeTempSibling(File target, List<int> bytes) {
  final segments = target.uri.pathSegments.where((s) => s.isNotEmpty);
  // Created outside the try: a temp that already exists is another writer's,
  // so the cleanup below must not delete it.
  final temp = File(
    '${target.parent.path}${Platform.pathSeparator}'
    '.${segments.last}.$pid.${_randomHex()}.specstone.tmp',
  )..createSync(exclusive: true);
  try {
    // Opened before the mode narrows, so a read-only mode still takes bytes.
    final sink = temp.openSync(mode: FileMode.writeOnly);
    try {
      _copyMode(target, temp);
      sink
        ..writeFromSync(bytes)
        ..flushSync();
    } finally {
      sink.closeSync();
    }
  } on FileSystemException {
    if (temp.existsSync()) temp.deleteSync();
    rethrow;
  }
  return temp;
}

/// Windows error codes for a denied or shared-violation rename.
const _windowsBlockedByHandle = {5, 32};

/// Pause between two rename tries on Windows.
const _renameRetryPause = Duration(milliseconds: 10);

/// Longest a Windows rename keeps retrying, counted from the first try.
const _renameRetryLimit = Duration(seconds: 1);

/// Whether [error] is a Windows refusal caused by another open handle.
bool _isBlockedByHandle(FileSystemException error) =>
    Platform.isWindows &&
    _windowsBlockedByHandle.contains(error.osError?.errorCode);

/// Renames [entity] to [newPath], returning the renamed entity.
///
/// On Windows a rename fails with error 5 or 32 when another open handle
/// blocks it: a handle on the target being replaced (Windows refuses the
/// replace unless that handle was opened with FILE_SHARE_DELETE), a handle on
/// the source file itself, or a handle on any file inside a moved folder.
/// The rename retries every 10 ms for up to 1 s after the first try, as git
/// for Windows does in `mingw_rename`. Any other error, and every other OS,
/// fails at once.
T renameSyncRetrying<T extends FileSystemEntity>(T entity, String newPath) {
  final clock = Stopwatch()..start();
  while (true) {
    try {
      return entity.renameSync(newPath) as T;
    } on FileSystemException catch (error) {
      final retry =
          _isBlockedByHandle(error) && clock.elapsed < _renameRetryLimit;
      if (retry) {
        sleep(_renameRetryPause);
        continue;
      }
      rethrow;
    }
  }
}

/// Replaces [target] with [bytes] so a reader never sees a partial file.
///
/// A target that exists keeps its permission bits, an executable one included.
/// Deletes the temp sibling and rethrows when the write or the rename fails.
/// Creates no parent folder. On Windows, when another handle holds the temp
/// or the target open, the rename can block for up to 1 s before it succeeds
/// or fails (see [renameSyncRetrying]).
///
/// Throws [FileSystemException] when the folder is missing or the rename fails.
void writeFileAtomic(File target, List<int> bytes) {
  final temp = writeTempSibling(target, bytes);
  try {
    renameSyncRetrying(temp, target.path);
  } on FileSystemException {
    if (temp.existsSync()) temp.deleteSync();
    rethrow;
  }
}

/// The `chmod` the CLI runs, by absolute path so no `PATH` entry stands in.
const chmodPath = '/bin/chmod';

/// The POSIX mode of a folder only its owner may enter.
const _ownerOnlyFolderMode = '700';

/// Narrows [folder] to its owner on POSIX, so other local users cannot read
/// what it holds; Windows has no such mode.
///
/// Throws [FileSystemException] when `chmod` refuses or cannot start.
void restrictToOwner(Directory folder) {
  if (Platform.isWindows) return;
  final ProcessResult result;
  try {
    result = Process.runSync(chmodPath, [_ownerOnlyFolderMode, folder.path]);
  } on ProcessException catch (error) {
    throw FileSystemException(
      'cannot start chmod: ${error.message}',
      folder.path,
    );
  }
  if (result.exitCode != 0) {
    throw FileSystemException('cannot make it private', folder.path);
  }
}

/// The permission bits of a file mode.
const _permissionBits = 0xFFF;

/// Gives [temp] the permission bits of [target] when it exists, so the rename
/// keeps an executable file executable. Windows has no such bits.
///
/// Throws [FileSystemException] when `chmod` refuses or cannot start.
void _copyMode(File target, File temp) {
  if (Platform.isWindows) return;
  final stat = target.statSync();
  if (stat.type != FileSystemEntityType.file) return;
  final mode = stat.mode & _permissionBits;
  if (mode == temp.statSync().mode & _permissionBits) return;
  final ProcessResult result;
  try {
    result = Process.runSync(chmodPath, [mode.toRadixString(8), temp.path]);
  } on ProcessException catch (error) {
    throw FileSystemException(
      'cannot start chmod: ${error.message}',
      target.path,
    );
  }
  if (result.exitCode != 0) {
    throw FileSystemException('cannot copy the file mode', target.path);
  }
}
