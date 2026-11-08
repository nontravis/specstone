import 'dart:io';

import 'package:specstone_core/src/templates/code_point_order.dart';

const _separator = '/';
const _dotName = '.';
const _dotSegment = '.';

/// Returns [entry], a `code:` entry, with its final `/` dropped.
String withoutFinalSlash(String entry) =>
    entry.endsWith(_separator) ? entry.substring(0, entry.length - 1) : entry;

/// Returns the files under the `code:` [entry], as paths from [codeRoot]
/// sorted by code point; an [entry] that names a file lists that file.
/// `.` segments of [entry] are dropped, so every path is in one form.
///
/// Names starting with a dot and links are skipped, and no file is read. A
/// missing root yields none. A folder that exists but cannot be listed is
/// passed to [onUnlistable], as a path from [codeRoot], and its files are
/// left out.
List<String> filesUnderCodeRoot(
  Directory codeRoot,
  String entry, {
  void Function(String folder)? onUnlistable,
}) {
  final root = _withoutDotSegments(withoutFinalSlash(entry));
  final kind = FileSystemEntity.typeSync(
    '${codeRoot.path}$_separator$root',
    followLinks: false,
  );
  if (kind == FileSystemEntityType.file) return [root];
  final files = <String>[];
  _collect(codeRoot, root, files, onUnlistable);
  return files..sort(compareCodePoints);
}

/// Returns the files under every one of [entries], each once, sorted by code
/// point (see [filesUnderCodeRoot]).
List<String> codeRootFiles(Directory codeRoot, Iterable<String> entries) {
  final files = <String>{
    for (final entry in entries) ...filesUnderCodeRoot(codeRoot, entry),
  };
  return files.toList()..sort(compareCodePoints);
}

/// Returns [path] without its `.` segments, so `./lib` and `lib` list the same
/// paths and `.` names the code root itself.
String _withoutDotSegments(String path) => path
    .split(_separator)
    .where((segment) => segment != _dotSegment && segment.isNotEmpty)
    .join(_separator);

void _collect(
  Directory codeRoot,
  String folderPath,
  List<String> files,
  void Function(String folder)? onUnlistable,
) {
  final folder = Directory('${codeRoot.path}$_separator$folderPath');
  final List<FileSystemEntity> entities;
  try {
    entities = folder.listSync(followLinks: false);
  } on FileSystemException {
    if (folder.existsSync()) onUnlistable?.call(folderPath);
    return;
  }
  for (final entity in entities) {
    final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (name.startsWith(_dotName)) continue;
    final path = folderPath.isEmpty ? name : '$folderPath$_separator$name';
    switch (entity) {
      case File():
        files.add(path);
      case Directory():
        _collect(codeRoot, path, files, onUnlistable);
      case _:
    }
  }
}
