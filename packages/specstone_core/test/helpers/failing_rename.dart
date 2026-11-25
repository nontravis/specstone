import 'dart:io';

import 'forwarding_entities.dart';

/// Makes `renameSync` throw for the one file or folder whose path ends with
/// the path given, as a disk that refuses that one move does.
///
/// Everything else reaches the real file system, so a move that passed a
/// probe can still fail on its own file.
final class FailingRenameHook extends IOOverrides {
  new(this._pathEnd);

  final String _pathEnd;

  /// Whether [path] ends with the path given, `\` read as `/` (Windows).
  bool _matches(String path) => path.replaceAll(r'\', '/').endsWith(_pathEnd);

  @override
  File createFile(String path) => _matches(path)
      ? _FailingRenameFile(super.createFile(path))
      : super.createFile(path);

  @override
  Directory createDirectory(String path) => _matches(path)
      ? _FailingRenameDirectory(super.createDirectory(path))
      : super.createDirectory(path);
}

final class _FailingRenameFile extends ForwardingFile {
  const new(super.inner);

  @override
  File renameSync(String newPath) =>
      throw FileSystemException('Permission denied', path);
}

final class _FailingRenameDirectory extends ForwardingDirectory {
  const new(super.inner);

  @override
  Directory renameSync(String newPath) =>
      throw FileSystemException('Permission denied', path);
}
