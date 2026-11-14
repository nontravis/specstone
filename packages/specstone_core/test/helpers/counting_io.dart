import 'dart:io';

import 'forwarding_entities.dart';

/// Returns how many real-path resolves of a file or folder [body] makes.
int countRealPathResolves(void Function() body) {
  final hook = _CountingHook();
  IOOverrides.runWithIOOverrides(body, hook);
  return hook.resolves;
}

final class _CountingHook extends IOOverrides {
  int resolves = 0;

  @override
  File createFile(String path) =>
      _CountingFile(super.createFile(path), () => resolves++);

  @override
  Directory createDirectory(String path) =>
      _CountingDirectory(super.createDirectory(path), () => resolves++);
}

final class _CountingFile extends ForwardingFile {
  const new(super.inner, this._count);

  final void Function() _count;

  @override
  String resolveSymbolicLinksSync() {
    _count();
    return super.resolveSymbolicLinksSync();
  }
}

final class _CountingDirectory extends ForwardingDirectory {
  const new(super.inner, this._count);

  final void Function() _count;

  @override
  String resolveSymbolicLinksSync() {
    _count();
    return super.resolveSymbolicLinksSync();
  }
}
