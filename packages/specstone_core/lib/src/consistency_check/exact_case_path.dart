import 'dart:io';

const _separator = '/';
const _parentSegment = '..';

/// Resolves paths by exact letter case, on every platform.
///
/// `FileSystemEntity.typeSync` resolves `TOOL/build.dart` to `Tool/build.dart`
/// on a case-insensitive disk. This walks each segment against the folder's
/// listing, so a segment that differs by letter case names nothing. It reads
/// each folder's listing once per instance.
final class ExactCasePaths {
  new();

  final Map<String, Set<String>?> _listings = {};

  /// Returns the type of [normalPath] under [base], `notFound` unless each
  /// segment equals a name in its folder exactly.
  ///
  /// [normalPath] is in `normalCodeEntry`'s form: `/`-separated, with no `.`
  /// or empty segment. A leading `..` leaves [base] and is not matched by name.
  FileSystemEntityType typeOf(Directory base, String normalPath) {
    var current = base.path;
    if (normalPath.isNotEmpty) {
      for (final segment in normalPath.split(_separator)) {
        final next = [current, segment].join(_separator);
        if (segment != _parentSegment && !_hasName(current, segment, next)) {
          return FileSystemEntityType.notFound;
        }
        current = next;
      }
    }
    return FileSystemEntity.typeSync(current);
  }

  /// Whether [segment] is a name in [folder]; [path] is the two joined.
  ///
  /// A folder that cannot be listed, such as one searchable but not readable,
  /// cannot show a letter-case difference, so the disk answers for [path].
  bool _hasName(String folder, String segment, String path) {
    final names = _namesIn(folder);
    return names == null
        ? FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound
        : names.contains(segment);
  }

  Set<String>? _namesIn(String folder) => _listings.putIfAbsent(folder, () {
    try {
      return {
        for (final entity in Directory(folder).listSync(followLinks: false))
          _nameOf(entity.path),
      };
    } on FileSystemException {
      return null;
    }
  });

  static String _nameOf(String path) {
    final slash = path.lastIndexOf(_separator);
    final backslash = Platform.isWindows ? path.lastIndexOf(r'\') : -1;
    final cut = slash > backslash ? slash : backslash;
    return path.substring(cut + 1);
  }
}
