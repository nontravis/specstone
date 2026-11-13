import 'dart:io';

final String _separator = Platform.pathSeparator;

/// The most steps one path may take before it counts as a loop: dangling
/// links followed and names that vanished mid-resolve share this budget.
const _maxLinkHops = 40;

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

/// Returns [path] from [root], `/`-separated, when it lies inside [root] and
/// is not [root] itself; else null.
///
/// Both are canonical paths in the platform's separators: `\` on Windows, `/`
/// elsewhere, where `\` is an ordinary name character. [isWindows] picks the
/// style; it defaults to the running platform.
String? pathInside(String root, String path, {bool? isWindows}) {
  final separator = (isWindows ?? Platform.isWindows) ? r'\' : '/';
  final prefix = root.endsWith(separator) ? root : '$root$separator';
  if (path.length <= prefix.length || !path.startsWith(prefix)) return null;
  return path.substring(prefix.length).split(separator).join('/');
}

bool _isBareDrive(String path) => path.length == 2 && _hasDrive(path);

bool _hasDrive(String path) =>
    path.length >= 2 && path[1] == ':' && RegExp('[A-Za-z]').hasMatch(path[0]);

/// Returns [path] with symbolic links resolved.
///
/// The path may not exist: the nearest existing ancestor is resolved and the
/// missing names are appended, so a build output file that is not written yet
/// still compares against canonical roots. Without [strict], a `..` or `.`
/// among the missing names is applied, because nothing missing can be a
/// symbolic link. A link whose target does not exist is followed to where the
/// target would be made, since a write through it creates the target. A name
/// that vanishes while it is resolved counts as missing.
///
/// Links that loop, or a chain of dangling links longer than the OS follows,
/// stay as named, so a write through them fails at the disk. With [strict]
/// they throw a [FileSystemException] instead. A link whose target Windows
/// reads against a drive the link does not name (`X:name`) throws too, since
/// the place it leads to depends on that drive's current folder. A `.` or `..`
/// after a missing name throws too, since that name may become a link. Windows
/// collapses a `..` that lands on an existing folder before the disk sees it;
/// one that lands on a missing name still throws.
///
/// [resolve] reads the real path of an existing name and [readLink] the
/// target of a link; they default to the disk's answers, and a test passes
/// doubles.
String canonicalPath(
  String path, {
  bool strict = false,
  String Function(String path) resolve = realPathOnDisk,
  String Function(String path) readLink = linkTargetOnDisk,
}) {
  final missing = <String>[];
  var existing = withoutTrailingSeparator(
    withNativeSeparators(File(path).absolute.path),
  );
  String resolved;
  for (var hops = 0; ; hops++) {
    while (FileSystemEntity.typeSync(existing, followLinks: false) ==
        FileSystemEntityType.notFound) {
      missing.add(existing.substring(existing.lastIndexOf(_separator) + 1));
      // An absolute path always reaches the file-system root, which exists.
      existing = parentOf(existing);
    }
    if (FileSystemEntity.typeSync(existing) != FileSystemEntityType.notFound) {
      try {
        resolved = resolveExisting(existing, resolve);
        break;
      } on FileSystemException {
        // A name deleted since the check, such as a SQLite side file another
        // connection closed, fails or answers for the deleted file; whatever
        // the code, only a fresh walk tells gone from made again.
        if (hops >= _maxLinkHops) rethrow;
        continue;
      }
    }
    // A link that exists as itself but leads nowhere yet.
    if (hops >= _maxLinkHops) {
      if (strict) {
        throw FileSystemException(
          'too many levels of symbolic links',
          existing,
        );
      }
      missing.add(existing.substring(existing.lastIndexOf(_separator) + 1));
      existing = parentOf(existing);
      continue;
    }
    final String target;
    try {
      target = readLink(existing);
    } on FileSystemException {
      // A link gone or replaced since the check fails whatever the code; walk
      // again from the same name, so it reads as it stands now.
      if (FileSystemEntity.isLinkSync(existing)) rethrow;
      continue;
    }
    existing = withoutTrailingSeparator(linkTargetPath(existing, target));
  }
  if (strict && holdsDotSegment(missing)) {
    throw FileSystemException(
      'a . or .. after a name that does not exist cannot be resolved',
      path,
    );
  }
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

/// Returns the real path of [path] as the disk resolves it.
String realPathOnDisk(String path) => File(path).resolveSymbolicLinksSync();

/// Returns the target the link at [path] names on disk, as written.
String linkTargetOnDisk(String path) => Link(path).targetSync();

/// Returns the real path [resolve] gives for [path], a name just seen to
/// exist.
///
/// Windows answers a name deleted meanwhile, while a handle to it is still
/// open, with a place in the NTFS folder of deleted files
/// (`C:\$Extend\$Deleted\...`) or with an empty path. Either answer throws a
/// [FileSystemException], as a failed resolve does, so a caller walks the
/// path again and reads the name as it stands now: gone, or made again.
String resolveExisting(String path, String Function(String path) resolve) {
  final real = resolve(path);
  if (real.isNotEmpty && !_isNtfsDeletedFile(real)) return real;
  throw FileSystemException('it was deleted while it was resolved', path);
}

/// Whether [real] lies in the folder of deleted files, which on NTFS never
/// holds a file a user makes; NTFS reads its name in any case.
bool _isNtfsDeletedFile(String real) =>
    _hasDrive(real) &&
    real.substring(2).toLowerCase().startsWith(_ntfsDeletedFiles);

/// The folder of deleted files below a drive, in lower case.
const _ntfsDeletedFiles = r'\$extend\$deleted\';

/// Returns the absolute path the link at [linkPath] names with [target], read
/// from the folder of the link.
///
/// On Windows a target that starts with one separator (what git for Windows
/// makes of a committed `/dir/x`) is rooted at the drive or share of the
/// link, not read from the link's folder. A drive-relative target `X:name`
/// throws a [FileSystemException], since it leads wherever drive `X:` is
/// currently set. [isWindows] picks the style; it defaults to the running
/// platform.
String linkTargetPath(String linkPath, String target, {bool? isWindows}) {
  final windows = isWindows ?? Platform.isWindows;
  if (!windows) {
    return target.startsWith('/')
        ? target
        : _joined(parentOf(linkPath, isWindows: false), target, '/');
  }
  final native = withNativeSeparators(target, isWindows: true);
  if (native.startsWith(r'\\')) return native;
  if (_hasDrive(native)) {
    if (native.length > 2 && native[2] == r'\') return native;
    throw FileSystemException(
      'a link target that names a drive without a root cannot be followed',
      linkPath,
    );
  }
  if (native.startsWith(r'\')) {
    final volume = _windowsVolumeOf(linkPath);
    if (volume == null) {
      throw FileSystemException('the drive of the link is unknown', linkPath);
    }
    return '$volume$native';
  }
  return _joined(parentOf(linkPath, isWindows: true), native, r'\');
}

/// Returns the drive (`C:`) or network share (`\\server\share`) that starts
/// the Windows [path], or null when it starts with neither.
String? _windowsVolumeOf(String path) {
  if (_hasDrive(path)) return path.substring(0, 2);
  if (!path.startsWith(r'\\')) return null;
  final names = path.substring(2).split(r'\');
  if (names.length < 2 || names[0].isEmpty || names[1].isEmpty) return null;
  return r'\\'
      '${names[0]}\\${names[1]}';
}

/// Whether any of [names] is `.` or `..`, which a name that does not exist
/// yet cannot stand before, since that name may become a link.
bool holdsDotSegment(Iterable<String> names) =>
    names.any((name) => name == '.' || name == '..');

String _joined(String folder, String name, String separator) =>
    folder.endsWith(separator) ? '$folder$name' : '$folder$separator$name';

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
