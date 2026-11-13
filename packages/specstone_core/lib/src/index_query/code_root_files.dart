import 'dart:io';

import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/project_config.dart'
    show isPortableCodeEntry;

const _separator = '/';
const _dotName = '.';
const _dotSegment = '.';
const _parentSegment = '..';

/// Returns [entry], a `code:` or `covers:` entry, in the one form every
/// path compare uses: `.` segments and the final `/` dropped, and each `..`
/// applied to the segment before it; a `..` with none before it stays. An
/// entry naming the code root itself is `''`.
String normalCodeEntry(String entry) {
  final segments = <String>[];
  for (final segment in entry.split(_separator)) {
    if (segment.isEmpty || segment == _dotSegment) continue;
    if (segment == _parentSegment &&
        segments.isNotEmpty &&
        segments.last != _parentSegment) {
      segments.removeLast();
    } else {
      segments.add(segment);
    }
  }
  return segments.join(_separator);
}

/// Returns the files under the `code:` [entry], as paths from [codeRoot]
/// sorted by code point; an [entry] that names a file lists that file. Every
/// path is in [normalCodeEntry]'s form.
///
/// Lists nothing for an entry that is not a relative `/`-separated path
/// ([isPortableCodeEntry]), that leaves the code root, or that is or passes a
/// link, so no caller reads or
/// writes a file outside the code root. Below the entry, names starting with
/// a dot and links are skipped, and no file is read. A missing root yields
/// none. A folder that exists but cannot be listed is passed to
/// [onUnlistable], as a path from [codeRoot], and its files are left out.
///
/// A file in a folder of [skipFolders], paths from [codeRoot] in
/// [normalCodeEntry]'s form, is left out: the code root of another target
/// nested in this one owns it. With [skipRepositories], so is a file in a
/// folder below the entry that holds a `.git` entry, a checkout of its own.
List<String> filesUnderCodeRoot(
  Directory codeRoot,
  String entry, {
  void Function(String folder)? onUnlistable,
  List<String> skipFolders = const [],
  bool skipRepositories = false,
}) {
  if (!isPortableCodeEntry(entry) || _passesLink(codeRoot, entry)) {
    return const [];
  }
  final root = normalCodeEntry(entry);
  if (root == _parentSegment ||
      root.startsWith('$_parentSegment/') ||
      _isUnder(skipFolders, root)) {
    return const [];
  }
  final kind = FileSystemEntity.typeSync(
    '${codeRoot.path}$_separator$root',
    followLinks: false,
  );
  if (kind == FileSystemEntityType.file) return [root];
  final files = <String>[];
  _collect(codeRoot, root, files, onUnlistable, skipFolders, skipRepositories);
  return files..sort(compareCodePoints);
}

/// Returns the files under every one of [entries], each once, sorted by code
/// point (see [filesUnderCodeRoot], which takes [skipFolders]).
List<String> codeRootFiles(
  Directory codeRoot,
  Iterable<String> entries, {
  List<String> skipFolders = const [],
}) {
  final files = <String>{
    for (final entry in entries)
      ...filesUnderCodeRoot(codeRoot, entry, skipFolders: skipFolders),
  };
  return files.toList()..sort(compareCodePoints);
}

/// Returns the code file [codePath], a path [filesUnderCodeRoot] lists from
/// [codeRoot], as a `/`-separated path from [projectRoot] with `..` for each
/// folder it leaves; null when it lies in [docsRoot], whose files are docs.
///
/// The three roots and the file's folder are compared at their canonical
/// paths, so a case variant such as `Docs/`, a `lib/../docs` entry, or a
/// `code_root` above the project reads as the folder it names.
String? projectPathOfCodeFile(
  String codePath, {
  required Directory projectRoot,
  required Directory docsRoot,
  required Directory codeRoot,
}) {
  final segments = codePath.split(_separator);
  final folder = [
    codeRoot.path,
    ...segments.take(segments.length - 1),
  ].join(Platform.pathSeparator);
  final real = [
    Directory(folder).resolveSymbolicLinksSync(),
    segments.last,
  ].join(Platform.pathSeparator);
  if (docsRoot.existsSync() &&
      real.startsWith(
        '${docsRoot.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
      )) {
    return null;
  }
  return _relativePath(projectRoot.resolveSymbolicLinksSync(), real);
}

/// Returns [path] from the folder [from], both canonical, `/`-separated.
String _relativePath(String from, String path) {
  final fromSegments = _segmentsOf(from);
  final pathSegments = _segmentsOf(path);
  var shared = 0;
  while (shared < fromSegments.length &&
      shared < pathSegments.length &&
      fromSegments[shared] == pathSegments[shared]) {
    shared++;
  }
  return [
    for (var i = shared; i < fromSegments.length; i++) _parentSegment,
    ...pathSegments.skip(shared),
  ].join(_separator);
}

List<String> _segmentsOf(String path) =>
    path.split(Platform.pathSeparator).where((s) => s.isNotEmpty).toList();

/// Whether a folder on the way to [entry] as written, or the entry itself,
/// is a link.
bool _passesLink(Directory codeRoot, String entry) {
  final segments = entry.split(_separator).where((s) => s.isNotEmpty).toList();
  for (var count = 1; count <= segments.length; count++) {
    final path = [
      codeRoot.path,
      ...segments.take(count),
    ].join(Platform.pathSeparator);
    if (FileSystemEntity.typeSync(path, followLinks: false) ==
        FileSystemEntityType.link) {
      return true;
    }
  }
  return false;
}

/// Whether [path] is one of [folders] or lies below one.
bool _isUnder(List<String> folders, String path) => folders.any(
  (folder) => path == folder || path.startsWith('$folder$_separator'),
);

/// Whether [folder] holds a `.git` entry, a folder or a file.
bool _holdsGitEntry(Directory folder) =>
    FileSystemEntity.typeSync(
      '${folder.path}$_separator.git',
      followLinks: false,
    ) !=
    FileSystemEntityType.notFound;

void _collect(
  Directory codeRoot,
  String folderPath,
  List<String> files,
  void Function(String folder)? onUnlistable,
  List<String> skipFolders,
  bool skipRepositories,
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
        if (_isUnder(skipFolders, path)) break;
        if (skipRepositories && _holdsGitEntry(entity)) break;
        _collect(
          codeRoot,
          path,
          files,
          onUnlistable,
          skipFolders,
          skipRepositories,
        );
      case _:
    }
  }
}
