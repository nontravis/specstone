// dart:mirrors lets one wrapper forward every member it does not override;
// it exists in the VM that runs tests, which is the only place this is used.
import 'dart:io';
import 'dart:mirrors';

/// Makes `renameSync` throw for the one file or folder whose path ends with
/// the path given, as a disk that refuses that one move does.
///
/// Everything else reaches the real file system, so a move that passed a
/// probe can still fail on its own file.
final class FailingRenameHook extends IOOverrides {
  new(this._pathEnd);

  final String _pathEnd;

  @override
  File createFile(String path) => path.endsWith(_pathEnd)
      ? _FailingRenameFile(super.createFile(path))
      : super.createFile(path);

  @override
  Directory createDirectory(String path) => path.endsWith(_pathEnd)
      ? _FailingRenameDirectory(super.createDirectory(path))
      : super.createDirectory(path);
}

final class _FailingRenameFile implements File {
  const new(this._inner);

  final File _inner;

  @override
  File renameSync(String newPath) =>
      throw FileSystemException('Permission denied', _inner.path);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      reflect(_inner).delegate(invocation);
}

final class _FailingRenameDirectory implements Directory {
  const new(this._inner);

  final Directory _inner;

  @override
  Directory renameSync(String newPath) =>
      throw FileSystemException('Permission denied', _inner.path);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      reflect(_inner).delegate(invocation);
}
