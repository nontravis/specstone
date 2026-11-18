import 'dart:io';

import 'package:specstone_core/src/canonical_path.dart';
import 'package:specstone_core/src/templates/cleanup_bounds.dart';

const _specstoneFolder = '.specstone';
const _bundlesFolder = 'bundles';
const _reportsFolder = 'reports';

/// How recently a file was last used for the size step to leave it alone.
const _recentUse = Duration(hours: 1);

/// Deletes the files of `.specstone/bundles/` and `reports/` that [bounds]
/// let go, by last use, then trims `bundles/` to its size cap.
///
/// Last use is the later of a file's modification and access time. The size
/// step skips a file in [keep] and one last used within the past hour; a file
/// dated after [now] sorts newest. Folders and links stay, and a folder that
/// is or lies below a link is left alone. What cannot be listed, read, or
/// deleted is skipped silently. [keep] holds canonical paths.
void pruneSpecstoneFolder(
  Directory projectRoot, {
  required Set<String> keep,
  required CleanupBounds bounds,
  required DateTime now,
}) {
  _pruneSubfolder(
    projectRoot,
    _bundlesFolder,
    keep: keep,
    maxAge: bounds.bundlesMaxAge,
    maxBytes: bounds.bundlesMaxBytes,
    now: now,
  );
  _pruneSubfolder(
    projectRoot,
    _reportsFolder,
    keep: keep,
    maxAge: bounds.reportsMaxAge,
    now: now,
  );
}

/// Whether [path] is `.specstone/<folder>` right below [root], both canonical.
///
/// [isWindows] picks the path style; it defaults to the running platform.
bool isSpecstoneSubfolderOf(
  String root,
  String path,
  String folder, {
  bool? isWindows,
}) =>
    pathInside(root, path, isWindows: isWindows) == '$_specstoneFolder/$folder';

/// Deletes the files below [folder] last used more than [maxAge] before [now]
/// and, with [maxBytes], then trims the rest to that many bytes.
///
/// A file whose times lie after [now] is not past [maxAge].
void pruneFolderOf(
  Directory folder, {
  required Set<String> keep,
  required Duration maxAge,
  int? maxBytes,
  required DateTime now,
}) {
  final prune = _FolderPrune(keep: keep, maxAge: maxAge, now: now)
    ..deleteExpired(folder);
  if (maxBytes != null) prune.trimTo(maxBytes);
}

void _pruneSubfolder(
  Directory projectRoot,
  String name, {
  required Set<String> keep,
  required Duration maxAge,
  int? maxBytes,
  required DateTime now,
}) {
  final separator = Platform.pathSeparator;
  final real = canonicalPath(
    '${projectRoot.path}$separator$_specstoneFolder$separator$name',
  );
  if (!isSpecstoneSubfolderOf(canonicalPath(projectRoot.path), real, name)) {
    return;
  }
  pruneFolderOf(
    Directory(real),
    keep: keep,
    maxAge: maxAge,
    maxBytes: maxBytes,
    now: now,
  );
}

/// One folder's prune: the age step's walk and the files it leaves for the
/// size step.
final class _FolderPrune {
  new({required this.keep, required this.maxAge, required this.now});

  final Set<String> keep;
  final Duration maxAge;
  final DateTime now;

  final _left = <_LeftFile>[];

  void deleteExpired(Directory folder) {
    final List<FileSystemEntity> entities;
    try {
      entities = folder.listSync(followLinks: false);
    } on FileSystemException {
      // Missing or not listable: nothing here to prune.
      return;
    }
    for (final entity in entities) {
      if (entity is Directory) {
        deleteExpired(entity);
      } else if (entity is File) {
        _visit(entity);
      }
    }
  }

  /// Deletes files, the least recently used first, until what the age step
  /// left totals [maxBytes] or less, or no file is left to try.
  void trimTo(int maxBytes) {
    var total = _left.fold(0, (sum, file) => sum + file.size);
    final order = [
      for (final file in _left)
        if (file.isTrimmable) file,
    ]..sort(_byLastUseThenPath);
    for (final file in order) {
      if (total <= maxBytes) return;
      if (_isOwn(file.file)) continue;
      if (_deleted(file.file)) total -= file.size;
    }
  }

  // Resolved only for a file about to be deleted: one stat per entry otherwise.
  bool _isOwn(File file) => keep.contains(canonicalPath(file.path));

  void _visit(File file) {
    final FileStat stat;
    try {
      stat = file.statSync();
    } on FileSystemException {
      // Gone or not readable: it counts for nothing and is not tried.
      return;
    }
    if (stat.type != FileSystemEntityType.file) return;
    final lastUse = stat.modified.isAfter(stat.accessed)
        ? stat.modified
        : stat.accessed;
    final age = now.difference(lastUse);
    final isExpired = age > maxAge;
    if (isExpired && !_isOwn(file) && _deleted(file)) return;
    _left.add(
      _LeftFile(
        file: file,
        lastUse: lastUse,
        size: stat.size,
        // A file dated after now is not recent: it sorts newest.
        isTrimmable: !isExpired && (age > _recentUse || age.isNegative),
      ),
    );
  }

  bool _deleted(File file) {
    try {
      file.deleteSync();
      return true;
    } on FileSystemException {
      // Held, not permitted, or already gone: the file stays.
      return false;
    }
  }
}

int _byLastUseThenPath(_LeftFile a, _LeftFile b) {
  final byUse = a.lastUse.compareTo(b.lastUse);
  return byUse != 0 ? byUse : a.file.path.compareTo(b.file.path);
}

/// A file the age step left, with what the size step needs of it.
final class _LeftFile {
  const new({
    required this.file,
    required this.lastUse,
    required this.size,
    required this.isTrimmable,
  });

  final File file;
  final DateTime lastUse;
  final int size;

  /// Whether the size step may try it: not one the age step kept as the run's
  /// own or could not delete, and not used within the past hour.
  final bool isTrimmable;
}
