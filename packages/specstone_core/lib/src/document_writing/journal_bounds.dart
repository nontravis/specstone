import 'dart:io';

import 'package:specstone_core/src/canonical_path.dart';
import 'package:specstone_core/src/document_writing/root_trust.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/project_config.dart'
    show isCodeRootValue;

// MARK: - Constants

const _gitEntry = '.git';

/// The 8.3 short name Windows may give a `.git` folder.
const _gitShortName = 'git~1';

/// The most times one folder path is walked again after a link on it failed
/// to resolve.
const _maxResolveAttempts = 40;

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
  /// writes outside them. [resolve] reads the real path of an existing folder;
  /// it defaults to the disk's answer, and a test passes a double.
  new(
    this._projectRoot,
    this._roots, {
    Set<String> agentFiles = const {},
    String Function(String path) resolve = realPathOnDisk,
  }) : _agentFiles = agentFiles,
       _resolve = resolve;

  final Directory _projectRoot;
  final List<String> _roots;
  final Set<String> _agentFiles;
  final String Function(String path) _resolve;

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
  String? _realFolder(List<String> segments) => _realFolders.putIfAbsent(
    segments.join('/'),
    () => _resolvedFolder(segments),
  );

  /// Resolves [segments] against the disk. A name that is no link and fails
  /// to resolve, such as a folder deleted since the check, is placed under
  /// its parent, where it lies whether gone or made again; a link whose
  /// resolve fails walks again.
  String? _resolvedFolder(List<String> segments) {
    var existing = segments.length;
    for (var attempt = 0; attempt < _maxResolveAttempts;) {
      while (existing > 0 && !_exists(segments.take(existing))) {
        existing--;
      }
      final missing = segments.skip(existing);
      if (holdsDotSegment(missing)) {
        return null;
      }
      final folder = _joined(segments.take(existing));
      try {
        final real = resolveExisting(folder, _resolve);
        return [real, ...missing].join(Platform.pathSeparator);
      } on FileSystemException {
        // Asking the name again can meet the same churn every time.
        if (existing > 0 && !FileSystemEntity.isLinkSync(folder)) {
          existing--;
          continue;
        }
        attempt++;
        existing = segments.length;
      }
    }
    return null;
  }

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

/// Opens the reason of a path the disk cannot resolve.
const _unresolved = 'it cannot be resolved';

/// Returns why a write to [path] must be refused, or null when it may go on.
///
/// The one gate every write outside the journal passes: [path] is resolved as
/// the disk stands, through every link on the way and the file itself, a link
/// to a target not made yet included, and must land inside the canonical
/// [projectRoot] or [docsRoot], below no `.git` entry between that root and
/// it. A root counts only when it exists as a folder, as in [JournalBounds]'s
/// roots: a docs link to a folder not made yet is no root. The `.git` rule is
/// [JournalBounds]'s: case folding, Windows dots, spaces, the 8.3 name, and an
/// NTFS stream suffix cut at its first `:`.
///
/// A path the disk cannot resolve (a link loop, a dangling chain longer than
/// the OS follows, a folder it may not enter, a `.` or `..` after a name that
/// does not exist) is refused with its reason, never thrown.
String? writeRefusalOf(
  String path, {
  required Directory projectRoot,
  Directory? docsRoot,
}) {
  final String real;
  final List<String> roots;
  try {
    real = canonicalPath(path, strict: true);
    roots = [
      for (final root in [projectRoot, ?docsRoot])
        if (root.existsSync()) root.resolveSymbolicLinksSync(),
    ];
  } on FileSystemException catch (error) {
    return '$_unresolved: ${error.osError?.message ?? error.message}';
  }
  final separator = Platform.pathSeparator;
  final inside = [
    for (final root in roots)
      if (real.startsWith('$root$separator'))
        real.substring(root.length + 1).split(separator),
  ];
  if (inside.isEmpty) return _leavesProject;
  return inside.any((below) => below.any(_isGitEntry)) ? _underGit : null;
}

/// Returns the warning line for [path], a file a run leaves as it is because
/// [writeRefusalOf] gave [reason]; without one, because its real path lies
/// outside the project root (R99).
String skippedLineOf(String path, [String? reason]) {
  if (reason == _underGit) return '$path lies under .git; left as it is';
  if (reason != null && reason.startsWith(_unresolved)) {
    return '$path cannot be resolved; left as it is';
  }
  return '$path reaches outside the project root; left as it is';
}

/// Throws [RenderFault] `output_not_writable` unless [trust], when given, holds
/// the roots trusted and [writeRefusalOf] finds [path] writable; the fault's
/// `file` is [path] from the project root.
///
/// Call it before every write, create, rename, or delete a command makes in a
/// project outside the journal, which checks its own steps. Pass the [trust]
/// of an opened project: its roots may lead out of the project by a committed
/// `docs` link, and only the Owner's record lets a write follow.
void requireWritableTarget(
  String path, {
  required Directory projectRoot,
  Directory? docsRoot,
  RootTrust? trust,
}) {
  final reason =
      trust?.refusal ??
      writeRefusalOf(path, projectRoot: projectRoot, docsRoot: docsRoot);
  if (reason == null) return;
  final shown = pathFromProjectRoot(path, projectRoot, docsRoot);
  throw RenderFault(
    RenderFaultCode.outputNotWritable,
    'cannot write $shown: $reason',
    file: shown,
  );
}

/// Returns [path] from the project root, `/`-separated, as `docs/...` under
/// the docs root; a path under neither stays as given.
///
/// [path] and the roots are compared with native separators, so a path joined
/// with `/` on Windows still matches. [isWindows] picks the style; it defaults
/// to the running platform.
String pathFromProjectRoot(
  String path,
  Directory projectRoot,
  Directory? docsRoot, {
  bool? isWindows,
}) {
  final windows = isWindows ?? Platform.isWindows;
  final separator = windows ? r'\' : '/';
  final native = withNativeSeparators(path, isWindows: windows);
  String below(String root) =>
      native.substring(root.length + 1).split(separator).join('/');
  bool isBelow(String root) => native.startsWith('$root$separator');
  final project = withNativeSeparators(projectRoot.path, isWindows: windows);
  if (isBelow(project)) return below(project);
  final docs = docsRoot == null
      ? null
      : withNativeSeparators(docsRoot.path, isWindows: windows);
  if (docs != null && isBelow(docs)) return 'docs/${below(docs)}';
  return path;
}
