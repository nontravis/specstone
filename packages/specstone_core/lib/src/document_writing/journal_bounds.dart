import 'dart:io';

import 'package:specstone_core/src/templates/project_config.dart'
    show isCodeRootValue;

// MARK: - Constants

const _gitEntry = '.git';

/// The 8.3 short name Windows may give a `.git` folder.
const _gitShortName = 'git~1';

/// The dots and spaces Windows drops from the end of a file name.
final _windowsDroppedEnd = RegExp(r'[. ]+$');

// MARK: - JournalBounds

/// Decides whether a journal step path lands inside the folders a run may
/// touch: the canonical roots it is given.
///
/// A path is judged by where the disk takes it, so a `..` or a link on the
/// way that leaves every root fails, and so does a path below a `.git` entry,
/// whose files git runs or reads as its own.
final class JournalBounds {
  /// Judges paths from a project root against its roots, canonical folders.
  new(this._projectRoot, this._roots);

  final Directory _projectRoot;
  final List<String> _roots;

  /// The real folder of each folder path asked, by its path from the project
  /// root; null when it cannot be resolved.
  final _realFolders = <String, String?>{};

  /// Whether [path], `/`-separated from the project root, lands inside a root
  /// with no `.git` entry between that root and it.
  ///
  /// The last segment is not followed, since a step moves or replaces a link
  /// as itself. A folder on the way that does not exist yet may hold no `.`
  /// or `..` segment, and an absolute path or a `\` never holds.
  bool holds(String path) {
    final segments = path.split('/');
    if (!isCodeRootValue(path) ||
        segments.any((segment) => segment.isEmpty || _isGitEntry(segment))) {
      return false;
    }
    final name = segments.removeLast();
    if (name == '.' || name == '..') return false;
    final folder = _realFolder(segments);
    if (folder == null) return false;
    return _isInsideRoots('$folder${Platform.pathSeparator}$name');
  }

  /// Returns the real path of the folder [segments] name from the project
  /// root, or null when it cannot be resolved.
  String? _realFolder(List<String> segments) =>
      _realFolders.putIfAbsent(segments.join('/'), () {
        var existing = segments.length;
        while (existing > 0 && !_exists(segments.take(existing))) {
          existing--;
        }
        final missing = segments.skip(existing);
        if (missing.any((segment) => segment == '.' || segment == '..')) {
          return null;
        }
        try {
          final real = Directory(_joined(segments.take(existing)))
              .resolveSymbolicLinksSync();
          return [real, ...missing].join(Platform.pathSeparator);
        } on FileSystemException {
          return null;
        }
      });

  bool _exists(Iterable<String> segments) =>
      FileSystemEntity.typeSync(_joined(segments)) !=
      FileSystemEntityType.notFound;

  String _joined(Iterable<String> segments) =>
      [_projectRoot.path, ...segments].join(Platform.pathSeparator);

  /// Whether [real] lies inside a root, and below no `.git` entry inside any
  /// root that holds it.
  bool _isInsideRoots(String real) {
    final separator = Platform.pathSeparator;
    final holding = [
      for (final root in _roots)
        if (real.startsWith('$root$separator'))
          real.substring(root.length + 1).split(separator),
    ];
    return holding.isNotEmpty &&
        holding.every((inside) => !inside.any(_isGitEntry));
  }
}

/// Whether [segment] names a `.git` entry, as a case-folding or Windows file
/// system reads it.
bool _isGitEntry(String segment) {
  final name = segment.toLowerCase().replaceFirst(_windowsDroppedEnd, '');
  return name == _gitEntry || name == _gitShortName;
}
