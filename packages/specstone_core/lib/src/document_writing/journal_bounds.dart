import 'dart:io';

import 'package:specstone_core/src/canonical_path.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
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
  /// Judges paths from a project root against its roots, canonical folders,
  /// and [agentFiles]: the canonical paths of the agent files a migrate
  /// writes outside them.
  new(this._projectRoot, this._roots, {Set<String> agentFiles = const {}})
    : _agentFiles = agentFiles;

  final Directory _projectRoot;
  final List<String> _roots;
  final Set<String> _agentFiles;

  /// The real folder of each folder path asked, by its path from the project
  /// root; null when it cannot be resolved.
  final _realFolders = <String, String?>{};

  /// Whether [path], `/`-separated from the project root, lands inside a root
  /// with no `.git` entry between that root and it, or on one of the agent
  /// files (R49).
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
    final real = '$folder${Platform.pathSeparator}$name';
    return _isInsideRoots(real) || _agentFiles.contains(real);
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
/// system reads it, an NTFS alternate-stream suffix included.
bool _isGitEntry(String segment) {
  // NTFS reads `.git:stream` and `.git::$INDEX_ALLOCATION` as `.git`.
  final stream = segment.indexOf(':');
  final base = stream < 0 ? segment : segment.substring(0, stream);
  final name = base.toLowerCase().replaceFirst(_windowsDroppedEnd, '');
  return name == _gitEntry || name == _gitShortName;
}

// MARK: - Write gate

/// Why a write to a file outside the journal is refused when it leads out.
const _leavesProject = 'it leads outside the project';

/// Why a write below a `.git` entry is refused.
const _underGit = 'it lies under .git';

/// Returns why a write to [path] must be refused, or null when it may go on.
///
/// The one gate every write outside the journal passes: [path] is resolved as
/// the disk stands, through every link on the way and the file itself, and
/// must land inside the canonical [projectRoot] or [docsRoot], below no `.git`
/// entry between that root and it. The `.git` rule is [JournalBounds]'s: case
/// folding, Windows dots, spaces, the 8.3 name, and an NTFS stream suffix cut
/// at its first `:`.
String? writeRefusalOf(
  String path, {
  required Directory projectRoot,
  Directory? docsRoot,
}) {
  final real = canonicalPath(path);
  final separator = Platform.pathSeparator;
  final roots = [
    for (final root in [projectRoot, ?docsRoot]) canonicalPath(root.path),
  ];
  final inside = [
    for (final root in roots)
      if (real.startsWith('$root$separator'))
        real.substring(root.length + 1).split(separator),
  ];
  if (inside.isEmpty) return _leavesProject;
  return inside.any((below) => below.any(_isGitEntry)) ? _underGit : null;
}

/// Throws [RenderFault] `output_not_writable` unless [writeRefusalOf] finds
/// [path] writable; the fault's `file` is [path] from the project root.
///
/// Call it before every write, create, rename, or delete a command makes in a
/// project outside the journal, which checks its own steps.
void requireWritableTarget(
  String path, {
  required Directory projectRoot,
  Directory? docsRoot,
}) {
  final reason = writeRefusalOf(
    path,
    projectRoot: projectRoot,
    docsRoot: docsRoot,
  );
  if (reason == null) return;
  final shown = _projectPathOf(path, projectRoot, docsRoot);
  throw RenderFault(
    RenderFaultCode.outputNotWritable,
    'cannot write $shown: $reason',
    file: shown,
  );
}

/// Returns [path] from the project root, `/`-separated, as `docs/...` under
/// the docs root; a path under neither stays as given.
String _projectPathOf(String path, Directory projectRoot, Directory? docsRoot) {
  final separator = Platform.pathSeparator;
  String below(String root) =>
      path.substring(root.length + 1).split(separator).join('/');
  if (path.startsWith('${projectRoot.path}$separator')) {
    return below(projectRoot.path);
  }
  if (docsRoot != null && path.startsWith('${docsRoot.path}$separator')) {
    return 'docs/${below(docsRoot.path)}';
  }
  return path;
}
