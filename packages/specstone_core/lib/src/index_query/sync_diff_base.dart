import 'dart:io';
import 'dart:math';

import 'package:specstone_core/src/consistency_check/code_fingerprint.dart';
import 'package:specstone_core/src/consistency_check/code_link_rules.dart';
import 'package:specstone_core/src/consistency_check/models/file_fingerprint.dart';
import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/index_query/code_root_files.dart'
    show CodeEntryListing, isOutsideCodeEntry, normalCodeEntry;
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/project_config.dart'
    show isPortableCodeEntry;

/// The most commits of a code link's history the base walk reads.
const syncBaseWalkLimit = 50;

const _separator = '/';
const _dotName = '.';
const _gitDir = '.git';
const _literalPathspecs = '--literal-pathspecs';
const _symlinkMode = '120000';
const _blobType = 'blob';
const _notARepository = 'not a git repository';
const _head = 'HEAD';

/// The most characters of pathspecs one git call takes, so the command line
/// stays within the Windows limit.
const _pathspecCharsPerCall = 16000;

const _commitMark = '\u0001';
const _rawMark = ':';
final RegExp _objectId = RegExp(r'^(?:[0-9a-f]{40}|[0-9a-f]{64})$');
final RegExp _noObject = RegExp(r'^0+$');
final RegExp _mode = RegExp(r'^[0-7]{6}$');

/// The commit a code link's diff is taken from, and the repository that holds
/// it.
final class SyncDiffBase {
  const new({
    required this.commit,
    required this.repo,
    required this.repoPath,
    this.isWorkingTree = false,
    this.folder,
  });

  /// The newest commit whose content gives the link's recorded fingerprint.
  final String commit;

  /// The top level of the repository that holds the code.
  final Directory repo;

  /// The path of the link's code from [repo], `/`-separated; empty when the
  /// code is the whole repository.
  final String repoPath;

  /// Whether the code at [commit] is the working tree's, content and mode, so
  /// its diff is empty.
  final bool isWorkingTree;

  /// The listing of a folder's code, whose diff keeps only the files it
  /// keeps; null for a file.
  final FolderListing? folder;

  /// Whether the code is a folder.
  bool get isFolder => folder != null;
}

/// The files a folder link's listing keeps, judged from its code root by
/// [CodeEntryListing], for paths git gives from the repository's top.
final class FolderListing {
  new(this.place, this.listing);

  /// Where the repository lies from [listing]'s code root.
  final CodePlace place;
  final CodeEntryListing listing;

  /// Whether the listing keeps the file at [repoPath], a path from [place]'s
  /// top.
  bool keepsRepoPath(String repoPath) {
    final path = place.rootPathOf(repoPath);
    return path != null && listing.keeps(path);
  }
}

// MARK: - Repositories

/// The repository that holds some code of a code root, and how a path from the
/// code root maps to a path from the repository's top.
///
/// The repository may hold the code root, or lie nested inside it.
final class CodePlace {
  const new({
    required this.top,
    required this.rootPrefix,
    required this.topPrefix,
  });

  /// The repository's top level.
  final String top;

  /// The code root's path from [top], ending in `/`; empty when the code root
  /// is [top] or lies above it.
  final String rootPrefix;

  /// [top]'s path from the code root, ending in `/`; empty when [top] is the
  /// code root or lies above it.
  final String topPrefix;

  /// Returns [rootPath], a path from the code root, as a path from [top];
  /// null when it lies outside the repository.
  String? repoPathOf(String rootPath) =>
      _moved(rootPath, from: topPrefix, to: rootPrefix);

  /// Returns [repoPath], a path from [top], as a path from the code root; null
  /// when it lies outside the code root.
  String? rootPathOf(String repoPath) =>
      _moved(repoPath, from: rootPrefix, to: topPrefix);

  static String? _moved(
    String path, {
    required String from,
    required String to,
  }) {
    final slashed = path.isEmpty ? '' : '$path$_separator';
    if (!slashed.startsWith(from)) return null;
    final moved = '$to${slashed.substring(from.length)}';
    return moved.isEmpty ? '' : moved.substring(0, moved.length - 1);
  }
}

/// Finds the repository that holds each code path, asking git once per
/// repository.
///
/// A code path belongs to the nearest repository above it, which need not be
/// the one that holds its code root: a repository that ignores a folder can
/// hold another repository there.
final class CodeRepos {
  new({RunGit git = runRealGitBytes}) : _git = git;

  final RunGit _git;
  final Map<String, Map<String, CodePlace?>> _placesByRoot = {};

  /// Returns the repository that holds [entry], a path from [root]; null when
  /// it lies in none.
  ///
  /// A missing [entry] is placed by the nearest folder above it that exists.
  CodePlace? placeOf(Directory root, String entry) {
    final places = _placesByRoot.putIfAbsent(root.path, () => {});
    final folder = _existingFolderOf(root, normalCodeEntry(entry));
    for (String? at = folder; at != null; at = _parentOf(at)) {
      if (places.containsKey(at)) return places[at];
      if (FileSystemEntity.typeSync(_join(root.path, _join(at, _gitDir))) !=
          FileSystemEntityType.notFound) {
        break;
      }
    }
    final place = _askedPlaceOf(root, folder);
    places[folder] = place;
    if (place != null) places[_folderOf(place.topPrefix)] = place;
    return place;
  }

  CodePlace? _askedPlaceOf(Directory root, String folder) {
    final result = _git([
      'rev-parse',
      '--show-toplevel',
      '--show-prefix',
    ], workingDirectory: _join(root.path, folder));
    if (result.exitCode != 0) return null;
    final lines = gitStdoutText(result.stdout).split('\n');
    final prefix = lines.length > 1 ? lines[1] : '';
    final slashed = folder.isEmpty ? '' : '$folder$_separator';
    if (prefix.endsWith(slashed)) {
      return CodePlace(
        top: lines[0],
        rootPrefix: prefix.substring(0, prefix.length - slashed.length),
        topPrefix: '',
      );
    }
    if (slashed.endsWith(prefix)) {
      return CodePlace(
        top: lines[0],
        rootPrefix: '',
        topPrefix: slashed.substring(0, slashed.length - prefix.length),
      );
    }
    return null;
  }
}

/// Returns [entry], a path from [root], when it is a folder, else the nearest
/// folder above it that exists; empty for [root] itself.
String _existingFolderOf(Directory root, String entry) {
  for (String? at = entry; at != null; at = _parentOf(at)) {
    if (at.isEmpty || FileSystemEntity.isDirectorySync(_join(root.path, at))) {
      return at;
    }
  }
  return '';
}

/// Returns the folder above [path]; empty above a top-level name, null above
/// the root itself.
String? _parentOf(String path) {
  if (path.isEmpty) return null;
  final slash = path.lastIndexOf(_separator);
  return slash < 0 ? '' : path.substring(0, slash);
}

String _folderOf(String prefix) =>
    prefix.isEmpty ? '' : prefix.substring(0, prefix.length - 1);

String _join(String folder, String path) =>
    path.isEmpty ? folder : (folder.isEmpty ? path : '$folder$_separator$path');

/// Returns [repoPath] as a pathspec; `.` for the whole repository.
String _pathspecOf(String repoPath) => repoPath.isEmpty ? _dotName : repoPath;

// MARK: - Diff bases

/// Returns the newest of the last [limit] commits touching [link]'s code whose
/// content fingerprints as [CodeLink.recorded]; null when none does, or the
/// link records no fingerprint, or its code lies in no repository.
///
/// The repository is the one that holds the link's code itself, which need not
/// hold its code root or the docs. [nestedRoots] are the code roots of the
/// other targets nested in this one, which a folder entry leaves out.
SyncDiffBase? diffBaseOf(
  CodeLink link, {
  RunGit git = runRealGitBytes,
  int limit = syncBaseWalkLimit,
  List<String> nestedRoots = const [],
}) => SyncDiffBases(
  [link],
  git: git,
  limit: limit,
).of(link, nestedRoots: nestedRoots);

/// The diff bases of a set of code links, each as [diffBaseOf] gives it.
///
/// Git runs once per repository to find it, once for the history of every
/// file link it holds, once per folder link, and once per blob whose content
/// the working tree does not already hold; a link that repeats another's code
/// and fingerprint reuses its base.
final class SyncDiffBases {
  /// Takes the [links] whose histories are read together; [limit] is the most
  /// commits of one link's history the walk reads.
  new(
    Iterable<CodeLink> links, {
    RunGit git = runRealGitBytes,
    int limit = syncBaseWalkLimit,
  }) : _links = links.toList(),
       _git = git,
       _limit = limit,
       _repos = CodeRepos(git: git);

  final List<CodeLink> _links;
  final RunGit _git;
  final int _limit;
  final CodeRepos _repos;
  final Map<String, _RepoHistory> _histories = {};
  final Map<String, SyncDiffBase?> _bases = {};

  /// Returns the diff base of [link], one of the links this was made with;
  /// [nestedRoots] are as [diffBaseOf] takes them. Null when git cannot run,
  /// so the code prints whole.
  SyncDiffBase? of(CodeLink link, {List<String> nestedRoots = const []}) {
    try {
      return _baseOf(link, nestedRoots);
    } on ProcessException {
      return null;
    }
  }

  SyncDiffBase? _baseOf(CodeLink link, List<String> nestedRoots) {
    final recorded = link.recorded;
    final code = _codeOf(link);
    if (recorded == null || code == null) return null;
    final key = [
      code.place.top,
      code.repoPath,
      '${code.isFile}',
      recorded,
      ...nestedRoots,
    ].join('\u0000');
    return _bases.putIfAbsent(key, () {
      final history = _historyOf(code.place.top);
      if (!code.isFile) {
        final commit = history.folderBaseOf(code, recorded, nestedRoots);
        return commit == null
            ? null
            : SyncDiffBase(
                commit: commit,
                repo: Directory(code.place.top),
                repoPath: code.repoPath,
                folder: code.folderListing(nestedRoots),
              );
      }
      final version = history.fileBaseOf(code, recorded);
      return version == null
          ? null
          : SyncDiffBase(
              commit: version.commit,
              repo: Directory(code.place.top),
              repoPath: code.repoPath,
              isWorkingTree: history.isWorkingTree(code.repoPath, version),
            );
    });
  }

  /// Returns where [link]'s code lies; null when the walk reads none of it.
  _Code? _codeOf(CodeLink link) {
    final entry = normalCodeEntry(link.readPath);
    if (entry.isEmpty ||
        !isPortableCodeEntry(entry) ||
        isOutsideCodeEntry(entry) ||
        !link.root.existsSync()) {
      return null;
    }
    final place = _repos.placeOf(link.root, entry);
    final repoPath = place?.repoPathOf(entry);
    if (place == null || repoPath == null) return null;
    return _Code(
      root: link.root,
      place: place,
      entry: entry,
      repoPath: repoPath,
      isFile:
          FileSystemEntity.typeSync(_join(link.root.path, entry)) ==
          FileSystemEntityType.file,
    );
  }

  _RepoHistory _historyOf(String top) => _histories.putIfAbsent(top, () {
    final files = <String>{};
    final folders = <String>{};
    for (final link in _links) {
      if (link.recorded == null) continue;
      final code = _codeOf(link);
      if (code == null || code.place.top != top) continue;
      (code.isFile ? files : folders).add(code.repoPath);
    }
    return _RepoHistory(
      git: _git,
      top: top,
      limit: _limit,
      files: files,
      folders: folders,
    );
  });
}

/// Where one code link's code lies.
final class _Code {
  const new({
    required this.root,
    required this.place,
    required this.entry,
    required this.repoPath,
    required this.isFile,
  });

  final Directory root;
  final CodePlace place;

  /// The path from [root].
  final String entry;

  /// The path from [place]'s top.
  final String repoPath;
  final bool isFile;

  /// Returns the listing of the folder at [entry], leaving out the code roots
  /// of [nestedRoots], paths from [root].
  FolderListing folderListing(List<String> nestedRoots) => FolderListing(
    place,
    CodeEntryListing(root, entry, skipFolders: nestedRoots),
  );
}

/// One version of a file in its history: a commit that changed it and the
/// blob it holds there.
final class _Version {
  const new({required this.commit, required this.blob, required this.mode});

  final String commit;

  /// Null when the commit removed the file.
  final String? blob;
  final String? mode;
}

/// The commits of one pathspec chunk of file links read so far.
final class _FileLog {
  new(this.paths);

  final List<String> paths;
  int commitsRead = 0;

  /// Whether the log holds no commit past [commitsRead].
  bool isRead = false;
}

/// The history of the code links one repository holds, read together.
final class _RepoHistory {
  new({
    required this.git,
    required this.top,
    required this.limit,
    required Set<String> files,
    required Set<String> folders,
  }) : _files = files,
       _folders = folders;

  final RunGit git;
  final String top;
  final int limit;
  final Set<String> _files;
  final Set<String> _folders;

  late final Map<String, _FileLog> _logsByFile = {
    for (final log in _chunked(_files).map(_FileLog.new))
      for (final path in log.paths) path: log,
  };
  final Map<String, List<_Version>> _fileVersions = {};
  late final Map<String, _ListedBlob> _headBlobs = _readHeadBlobs();
  late final Set<String>? _changedSinceHead = _readChangedSinceHead();
  final Map<String, String?> _fingerprints = {};

  /// Returns the newest version of the file at [code] whose content gives
  /// [recorded]; null when none of its last [limit] versions does.
  _Version? fileBaseOf(_Code code, String recorded) {
    for (var at = 0; ; at++) {
      final version = _versionAt(code.repoPath, at);
      if (version == null) return null;
      final blob = version.blob;
      if (blob != null &&
          _fingerprintOf(blob, code.repoPath, code.entry) == recorded) {
        return version;
      }
    }
  }

  /// Returns the version at [index], newest first, of the file at [repoPath];
  /// null past its last [limit] versions.
  ///
  /// Its log is read a page at a time, only as far as a walk asks, so the
  /// cost follows the walk and not the repository's whole history.
  _Version? _versionAt(String repoPath, int index) {
    final log = _logsByFile[repoPath];
    if (log == null || index >= limit) return null;
    while (index >= (_fileVersions[repoPath]?.length ?? 0) && !log.isRead) {
      _readPage(log);
    }
    return _fileVersions[repoPath]?.elementAtOrNull(index);
  }

  /// Whether [version] of the file at [repoPath] has the content and mode the
  /// working tree holds.
  bool isWorkingTree(String repoPath, _Version version) {
    final blob = version.blob;
    return blob != null &&
        _isInWorkingTree(blob, repoPath) &&
        _headBlobs[repoPath]?.mode == version.mode;
  }

  /// Returns the newest of the last [limit] commits touching the folder at
  /// [code] whose listed files fingerprint as [recorded].
  String? folderBaseOf(_Code code, String recorded, List<String> nestedRoots) {
    final result = _run([
      'log',
      '--format=%H',
      '-n',
      '$limit',
      '--',
      _pathspecOf(code.repoPath),
    ]);
    if (result.exitCode != 0) return null;
    final listing = code.folderListing(nestedRoots);
    for (final commit in gitStdoutText(result.stdout).split('\n')) {
      if (commit.isEmpty) continue;
      if (_folderFingerprintAt(commit, code, listing) == recorded) {
        return commit;
      }
    }
    return null;
  }

  String? _folderFingerprintAt(
    String commit,
    _Code code,
    FolderListing listing,
  ) {
    final result = _run([
      'ls-tree',
      '-r',
      '-z',
      commit,
      '--',
      _pathspecOf(code.repoPath),
    ]);
    if (result.exitCode != 0) return folderCodeFingerprint(const []);
    final files = <FileFingerprint>[];
    for (final field in _nulFields(gitStdoutText(result.stdout))) {
      final listed = _listedBlobOf(field);
      if (listed == null) continue;
      final path = code.place.rootPathOf(listed.repoPath);
      if (path == null || !listing.listing.keeps(path)) continue;
      final fingerprint = _fingerprintOf(listed.blob, listed.repoPath, path);
      if (fingerprint == null) return null;
      files.add(FileFingerprint(path: path, fingerprint: fingerprint));
    }
    files.sort((a, b) => compareCodePoints(a.path, b.path));
    return folderCodeFingerprint(files);
  }

  /// Returns the fingerprint of [blob], the content of the file at [repoPath],
  /// [path] from the code root; null when it cannot be read.
  ///
  /// A blob the working tree still holds unchanged since `HEAD` is read from
  /// the working tree, with no git call.
  String? _fingerprintOf(String blob, String repoPath, String path) =>
      _fingerprints.putIfAbsent('$blob\u0000$path', () {
        final bytes = _isInWorkingTree(blob, repoPath)
            ? _workingBytesOf(repoPath)
            : null;
        final read = bytes ?? _blobBytesOf(blob);
        return read == null ? null : fileCodeFingerprint(read, path: path);
      });

  bool _isInWorkingTree(String blob, String repoPath) {
    final changed = _changedSinceHead;
    return changed != null &&
        !changed.contains(repoPath) &&
        _headBlobs[repoPath]?.blob == blob;
  }

  List<int>? _workingBytesOf(String repoPath) {
    try {
      return File(_join(top, repoPath)).readAsBytesSync();
    } on FileSystemException {
      return null;
    }
  }

  List<int>? _blobBytesOf(String blob) {
    final result = _run(['cat-file', _blobType, blob]);
    return result.exitCode == 0 ? result.stdout as List<int> : null;
  }

  /// Reads the next page of [log]'s commits, with merges where they changed a
  /// file against every parent.
  ///
  /// The first page holds [limit] commits per file, enough for every file's
  /// walk when the files change about as often; each later page doubles the
  /// commits read.
  void _readPage(_FileLog log) {
    final count = max(limit * log.paths.length, log.commitsRead);
    final result = _run([
      'log',
      '--no-renames',
      '-c',
      '--raw',
      '--no-abbrev',
      '--format=$_commitMark%H',
      '-z',
      '--skip=${log.commitsRead}',
      '-n',
      '$count',
      '--',
      ...log.paths,
    ]);
    if (result.exitCode != 0) {
      log.isRead = true;
      return;
    }
    final commits = _addVersions(gitStdoutText(result.stdout));
    log
      ..commitsRead += commits
      ..isRead = commits < count;
  }

  /// Adds each file version of a `git log --raw -z` [output] to the versions,
  /// up to [limit] per file, and returns how many commits it holds.
  int _addVersions(String output) {
    var commits = 0;
    String? commit;
    String? blob;
    String? mode;
    var hasBlob = false;
    for (final field in output.split('\u0000')) {
      // A commit's raw lines start on the line after its format line.
      final text = field.startsWith('\n') ? field.substring(1) : field;
      if (text.startsWith(_commitMark)) {
        commit = text.substring(_commitMark.length);
        commits++;
      } else if (text.startsWith(_rawMark)) {
        blob = _resultBlobOf(text);
        mode = _resultModeOf(text);
        hasBlob = true;
      } else if (hasBlob && commit != null && _files.contains(text)) {
        final list = _fileVersions.putIfAbsent(text, () => []);
        if (list.length < limit && list.lastOrNull?.commit != commit) {
          list.add(_Version(commit: commit, blob: blob, mode: mode));
        }
        hasBlob = false;
      } else {
        hasBlob = false;
      }
    }
    return commits;
  }

  /// Returns the file mode a raw line ends at, its last mode.
  static String? _resultModeOf(String raw) => raw
      .split(' ')
      .map((name) => name.replaceAll(_rawMark, ''))
      .where(_mode.hasMatch)
      .lastOrNull;

  /// Returns the blob a raw line ends at, its last object name; null when the
  /// file is gone there.
  static String? _resultBlobOf(String raw) {
    final names = raw.split(' ').where(_objectId.hasMatch);
    final blob = names.lastOrNull;
    return blob == null || _noObject.hasMatch(blob) ? null : blob;
  }

  Map<String, _ListedBlob> _readHeadBlobs() {
    final blobs = <String, _ListedBlob>{};
    for (final chunk in _chunked({..._files, ..._folders})) {
      final result = _run([
        'ls-tree',
        '-r',
        '-z',
        _head,
        '--',
        for (final path in chunk) _pathspecOf(path),
      ]);
      if (result.exitCode != 0) continue;
      for (final field in _nulFields(gitStdoutText(result.stdout))) {
        if (_listedBlobOf(field) case final listed?) {
          blobs[listed.repoPath] = listed;
        }
      }
    }
    return blobs;
  }

  /// Returns the files changed since `HEAD`, staged or not; null when git
  /// cannot tell, so every blob is read from git.
  Set<String>? _readChangedSinceHead() {
    final changed = <String>{};
    for (final chunk in _chunked({..._files, ..._folders})) {
      final result = _run([
        'diff',
        '--name-only',
        '--no-renames',
        '-z',
        _head,
        '--',
        for (final path in chunk) _pathspecOf(path),
      ]);
      if (result.exitCode != 0) return null;
      changed.addAll(_nulFields(gitStdoutText(result.stdout)));
    }
    return changed;
  }

  ProcessResult _run(List<String> arguments) =>
      git([_literalPathspecs, ...arguments], workingDirectory: top);
}

/// A file an `ls-tree` field names, and its blob.
final class _ListedBlob {
  const new({required this.repoPath, required this.blob, required this.mode});

  final String repoPath;
  final String blob;
  final String mode;
}

/// Returns the file of an `ls-tree` [field], which reads `mode type object TAB
/// path`; null for anything but a file that is no link.
_ListedBlob? _listedBlobOf(String field) {
  final tab = field.indexOf('\t');
  if (tab < 0) return null;
  final meta = field.substring(0, tab).split(' ');
  if (meta.length < 3 || meta[0] == _symlinkMode || meta[1] != _blobType) {
    return null;
  }
  return _ListedBlob(
    repoPath: field.substring(tab + 1),
    blob: meta[2],
    mode: meta[0],
  );
}

/// Splits [paths] into sorted runs whose characters stay within one call's
/// budget.
List<List<String>> _chunked(Set<String> paths) {
  final chunks = <List<String>>[];
  var chunk = <String>[];
  var length = 0;
  for (final path in paths.toList()..sort(compareCodePoints)) {
    if (chunk.isNotEmpty && length + path.length > _pathspecCharsPerCall) {
      chunks.add(chunk);
      chunk = [];
      length = 0;
    }
    chunk.add(path);
    length += path.length + 1;
  }
  return [...chunks, if (chunk.isNotEmpty) chunk];
}

// MARK: - Diffs and untracked files

/// Returns the diff of [base]'s code between its commit and the working tree;
/// empty with no git call when the commit holds the working tree's code.
///
/// A folder's diff leaves out what its listing leaves out, as [untrackedUnder]
/// does. Throws [ProcessException] when git fails.
String diffSince(SyncDiffBase base, {RunGit git = runRealGitBytes}) {
  if (base.isWorkingTree) return '';
  final whole = [_pathspecOf(base.repoPath)];
  final folder = base.folder;
  if (folder == null) return _diffText(base, const [], whole, git);
  final changed = _nulFields(
    _diffText(base, const ['--name-only', '--no-renames', '-z'], whole, git),
  );
  final listed = {
    for (final path in changed)
      if (folder.keepsRepoPath(path)) path,
  };
  if (listed.isEmpty) return '';
  if (listed.length == changed.length) {
    return _diffText(base, const [], whole, git);
  }
  return [
    for (final chunk in _chunked(listed)) _diffText(base, const [], chunk, git),
  ].join();
}

/// Returns git's diff of [pathspecs] since [base]'s commit, with [options].
String _diffText(
  SyncDiffBase base,
  List<String> options,
  List<String> pathspecs,
  RunGit git,
) {
  final arguments = [
    _literalPathspecs,
    'diff',
    '--no-color',
    '--no-ext-diff',
    '--no-textconv',
    ...options,
    base.commit,
    '--',
    ...pathspecs,
  ];
  final result = git(arguments, workingDirectory: base.repo.path);
  if (result.exitCode != 0) {
    throw ProcessException(
      'git',
      arguments,
      '${result.stderr}'.trim(),
      result.exitCode,
    );
  }
  return gitStdoutText(result.stdout);
}

/// Returns the untracked files under [prefix], a file or folder from [root],
/// as paths from [root] sorted by code point; none when it lies in no
/// repository. Throws [ProcessException] on any other git failure.
///
/// Git runs in the nearest folder of [prefix] that exists, so the repository
/// that holds it lists them. Leaves out what a folder entry leaves out:
/// ignored files, names starting with a dot, links, and the code roots of
/// [nestedRoots].
List<String> untrackedUnder(
  Directory root,
  String prefix, {
  RunGit git = runRealGitBytes,
  List<String> nestedRoots = const [],
}) {
  final entry = normalCodeEntry(prefix);
  if (isOutsideCodeEntry(entry)) return const [];
  final folder = _existingFolderOf(root, entry);
  final below = folder.isEmpty
      ? entry
      : (entry == folder ? '' : entry.substring(folder.length + 1));
  final result = git([
    _literalPathspecs,
    'ls-files',
    '--others',
    '--exclude-standard',
    '-z',
    if (below.isNotEmpty) ...['--', below],
  ], workingDirectory: _join(root.path, folder));
  if (result.exitCode != 0) {
    final reason = '${result.stderr}'.trim();
    if (reason.contains(_notARepository)) return const [];
    throw ProcessException('git', ['ls-files'], reason, result.exitCode);
  }
  final listing = CodeEntryListing(root, entry, skipFolders: nestedRoots);
  return [
    for (final listed in _nulFields(gitStdoutText(result.stdout)))
      if (_join(folder, listed) case final path
          when listing.keeps(path) &&
              !FileSystemEntity.isLinkSync(_join(root.path, path)))
        path,
  ]..sort(compareCodePoints);
}

List<String> _nulFields(String text) => [
  for (final field in text.split('\u0000'))
    if (field.isNotEmpty) field,
];
