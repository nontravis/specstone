import 'dart:io';

final String _separator = Platform.pathSeparator;

/// Returns [path] with every `/` changed to `\` on Windows, else unchanged.
///
/// Windows accepts both separators and Dart keeps whichever was written, so a
/// path that is cut at `\` alone mis-splits when it holds a `/`. Elsewhere `\`
/// is an ordinary file name character, so nothing changes. [isWindows] picks
/// the style; it defaults to the running platform.
String withNativeSeparators(String path, {bool? isWindows}) =>
    (isWindows ?? Platform.isWindows) ? path.replaceAll('/', r'\') : path;

/// Returns the folder that holds [path], keeping a root as a root.
///
/// A path cut at its first separator is the root: `/` on POSIX, and on Windows
/// the drive root `C:\`, never the bare drive `C:`, which Windows resolves to
/// that drive's current folder. [isWindows] picks the style; it defaults to
/// the running platform.
String parentOf(String path, {bool? isWindows}) {
  final windows = isWindows ?? Platform.isWindows;
  final separator = windows ? r'\' : '/';
  final cut = path.lastIndexOf(separator);
  if (cut <= 0) return separator;
  final parent = path.substring(0, cut);
  return windows && _isBareDrive(parent) ? '$parent$separator' : parent;
}

bool _isBareDrive(String path) =>
    path.length == 2 && path[1] == ':' && RegExp('[A-Za-z]').hasMatch(path[0]);

/// Returns [path] with symbolic links resolved.
///
/// The path may not exist: the nearest existing ancestor is resolved and the
/// missing names are appended, so a build output file that is not written yet
/// still compares against canonical roots. A `..` or `.` among the missing
/// names is applied, because nothing missing can be a symbolic link.
String canonicalPath(String path) {
  final missing = <String>[];
  var existing = withoutTrailingSeparator(
    withNativeSeparators(File(path).absolute.path),
  );
  while (FileSystemEntity.typeSync(existing) == FileSystemEntityType.notFound) {
    missing.add(existing.substring(existing.lastIndexOf(_separator) + 1));
    // An absolute path always reaches the file-system root, which exists.
    existing = parentOf(existing);
  }
  var resolved = File(existing).resolveSymbolicLinksSync();
  for (final name in missing.reversed) {
    if (name == '.') continue;
    if (name == '..') {
      resolved = parentOf(resolved);
      continue;
    }
    resolved = resolved.endsWith(_separator)
        ? '$resolved$name'
        : '$resolved$_separator$name';
  }
  return resolved;
}

/// Returns [path] without trailing separators, keeping a root as a root.
///
/// On Windows both `\` and `/` count as separators and the drive root stays
/// `C:\`, never the bare drive `C:`. Elsewhere only `/` counts. [isWindows]
/// picks the style; it defaults to the running platform.
String withoutTrailingSeparator(String path, {bool? isWindows}) {
  final windows = isWindows ?? Platform.isWindows;
  var end = path.length;
  while (end > 1 &&
      (path[end - 1] == '/' || windows && path[end - 1] == r'\')) {
    end--;
  }
  final trimmed = path.substring(0, end);
  return windows && _isBareDrive(trimmed) && end < path.length
      ? '$trimmed\\'
      : trimmed;
}
