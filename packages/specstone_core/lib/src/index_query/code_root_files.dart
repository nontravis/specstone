import 'dart:io';

import 'package:specstone_core/src/canonical_path.dart' show canonicalPath;
import 'package:specstone_core/src/consistency_check/exact_case_path.dart';
import 'package:specstone_core/src/index_query/git_ignore.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/code_target.dart'
    show nestedPathsOf;
import 'package:specstone_core/src/templates/project_config.dart'
    show isPortableCodeEntry;

const _separator = '/';
const _dotName = '.';
const _dotSegment = '.';
const _wholeCodeRoot = '.';
const _parentSegment = '..';

/// Returns [entry], a `code:` or `covers:` entry, in the one form every
/// path compare uses: `.` and empty segments dropped, so the final `/` too,
/// and each `..` kept, never folded into the segment before it. An entry
/// naming the code root itself is `''`.
String normalCodeEntry(String entry) => [
  for (final segment in entry.split(_separator))
    if (segment.isNotEmpty && segment != _dotSegment) segment,
].join(_separator);

/// Whether [entry], a `code:` or `covers:` entry read without the code
/// fingerprint it may end in, names the whole root and no path of its own.
///
/// The one predicate every code-link rule reads: its [normalCodeEntry] form is
/// empty, so it covers no file, matches no code path, takes no fingerprint,
/// and counts as no entry for the shared-doc rule.
bool isEmptyCodeEntry(String entry) => normalCodeEntry(entry).isEmpty;

/// Whether [entry], read as [isEmptyCodeEntry] reads it, leaves the root it is
/// read from: any segment of it is `..`.
///
/// An outside entry is read from no path, so no code-link rule resolves it or
/// takes its fingerprint.
bool isOutsideCodeEntry(String entry) =>
    entry.split(_separator).contains(_parentSegment);

/// Returns the files under the `code:` [entry], as paths from [codeRoot]
/// sorted by code point; an [entry] that names a file lists that file. Every
/// path is in [normalCodeEntry]'s form, spelled as the disk spells it.
///
/// Lists nothing for an entry that is not a relative `/`-separated path
/// ([isPortableCodeEntry]), that leaves the code root, that [ExactCasePaths]
/// finds no file or folder for, or that is or passes a link, so no caller
/// reads or writes a file outside the code root. Below the entry, names
/// starting with a dot and links are skipped, and no file is read. A missing
/// root yields
/// none. A folder that exists but cannot be listed is passed to
/// [onUnlistable], as a path from [codeRoot], and its files are left out.
///
/// A file in a folder of [skipFolders], paths from [codeRoot] in
/// [normalCodeEntry]'s form, is left out: the code root of another target
/// nested in this one owns it. With [skipRepositories], so is a file in a
/// folder below the entry that holds a `.git` entry, a checkout of its own.
/// A file or folder that [GitIgnoreRules] ignore, below [codeRoot] up to the
/// entry or under it, is left out too, tracked or not, each judged by the
/// rules of its own work tree: a folder holding `.git` starts a new one.
List<String> filesUnderCodeRoot(
  Directory codeRoot,
  String entry, {
  void Function(String folder)? onUnlistable,
  List<String> skipFolders = const [],
  bool skipRepositories = false,
}) {
  if (!isPortableCodeEntry(entry) || isOutsideCodeEntry(entry)) {
    return const [];
  }
  final diskEntry = _diskSpellingOf(codeRoot, entry);
  if (diskEntry == null || _passesLink(codeRoot, diskEntry)) return const [];
  final listing = CodeEntryListing(
    codeRoot,
    diskEntry,
    skipFolders: skipFolders,
  );
  final root = listing.entry;
  if (_isUnder(skipFolders, root)) return const [];
  final kind = FileSystemEntity.typeSync(
    '${codeRoot.path}$_separator$root',
    followLinks: false,
  );
  if (kind == FileSystemEntityType.file) return [root];
  if (kind != FileSystemEntityType.directory) return const [];
  final rules = listing._rulesIn(root);
  if (rules == null) return const [];
  final files = <String>[];
  _collect(
    codeRoot,
    root,
    rules,
    files,
    onUnlistable,
    skipFolders,
    skipRepositories,
  );
  return files..sort(compareCodePoints);
}

/// The rule [filesUnderCodeRoot] keeps a file under one `code:` entry by, for
/// a reader of paths another lister gave, such as git, so both keep the same
/// files.
///
/// Reads only `.gitignore` files and `.git` entries, each folder's once; a
/// path that is or passes a link is the caller's to leave out.
final class CodeEntryListing {
  /// Takes [entry] and [skipFolders] as [filesUnderCodeRoot] does.
  new(this.codeRoot, String entry, {this.skipFolders = const []})
    : entry = normalCodeEntry(entry);

  final Directory codeRoot;

  /// The entry in [normalCodeEntry]'s form.
  final String entry;

  /// The folders, paths from [codeRoot], whose files the listing leaves out.
  final List<String> skipFolders;

  final Map<String, GitIgnoreRules?> _rulesByFolder = {};

  /// Whether the listing keeps the file at [path], a path from [codeRoot] in
  /// [normalCodeEntry]'s form.
  bool keeps(String path) {
    final below = _belowEntry(path);
    if (below == null || _isUnder(skipFolders, path)) return false;
    if (below.isEmpty) return true;
    if (below.split(_separator).any(_isDotName)) return false;
    final slash = path.lastIndexOf(_separator);
    final rules = _rulesIn(slash < 0 ? '' : path.substring(0, slash));
    return rules != null &&
        !rules.ignores(path.substring(slash + 1), isFolder: false);
  }

  /// Returns [path] below [entry]; empty when it is [entry], null when it
  /// lies outside it.
  String? _belowEntry(String path) {
    if (entry.isEmpty) return path;
    if (path == entry) return '';
    return path.startsWith('$entry$_separator')
        ? path.substring(entry.length + 1)
        : null;
  }

  /// Returns the rules that apply in [folderPath], a folder path from
  /// [codeRoot]; null when it or a folder on its way from [codeRoot] is
  /// ignored.
  GitIgnoreRules? _rulesIn(String folderPath) {
    if (_rulesByFolder.containsKey(folderPath)) {
      return _rulesByFolder[folderPath];
    }
    return _rulesByFolder[folderPath] = _readRulesIn(folderPath);
  }

  GitIgnoreRules? _readRulesIn(String folderPath) {
    if (folderPath.isEmpty) return GitIgnoreRules.above(codeRoot);
    final slash = folderPath.lastIndexOf(_separator);
    final parent = _rulesIn(slash < 0 ? '' : folderPath.substring(0, slash));
    if (parent == null) return null;
    return _childRules(
      parent,
      folderPath.substring(slash + 1),
      Directory('${codeRoot.path}$_separator$folderPath'),
    );
  }
}

/// Returns the files under every one of [entries], each once, sorted by code
/// point (see [filesUnderCodeRoot], which takes [skipFolders] and
/// [onUnlistable]).
List<String> codeRootFiles(
  Directory codeRoot,
  Iterable<String> entries, {
  List<String> skipFolders = const [],
  void Function(String folder)? onUnlistable,
}) {
  final files = <String>{
    for (final entry in entries)
      ...filesUnderCodeRoot(
        codeRoot,
        entry,
        skipFolders: skipFolders,
        onUnlistable: onUnlistable,
      ),
  };
  return files.toList()..sort(compareCodePoints);
}

/// Returns the files a doc-name scan reads under [codeRoot], as paths from it
/// sorted by code point: the files under the `code:` [entries], or every file
/// under the root when [entries] is empty.
///
/// The whole-root listing leaves out the folders of [nestedRoots], the docs
/// root when it lies inside [codeRoot], and any checkout of its own below the
/// root; a listing of [entries] leaves out [nestedRoots] only. A folder that
/// cannot be listed goes to [onUnlistable]. The one lister of the code files
/// `check` and the rename, move, delete, and migrate mention scans read.
List<String> mentionScanFiles(
  Directory codeRoot,
  Set<String> entries, {
  required Directory docsRoot,
  List<String> nestedRoots = const [],
  void Function(String folder)? onUnlistable,
}) {
  if (entries.isNotEmpty) {
    return codeRootFiles(
      codeRoot,
      entries,
      skipFolders: nestedRoots,
      onUnlistable: onUnlistable,
    );
  }
  final docsFolders = nestedPathsOf(canonicalPath(codeRoot.path), [
    canonicalPath(docsRoot.path),
  ]);
  return filesUnderCodeRoot(
    codeRoot,
    _wholeCodeRoot,
    skipFolders: [...nestedRoots, ...docsFolders],
    skipRepositories: true,
    onUnlistable: onUnlistable,
  );
}

/// Turns the code files of one scan into project paths, resolving the project
/// root, the docs root, and each code folder once.
///
/// The roots and a file's folder are compared at their canonical paths, so a
/// case variant such as `Docs/`, a `lib/../docs` entry, or a `code_root` above
/// the project reads as the folder it names.
final class ProjectPathReader {
  new({required this.projectRoot, required this.docsRoot});

  final Directory projectRoot;
  final Directory docsRoot;

  late final String _realProjectRoot = projectRoot.resolveSymbolicLinksSync();
  late final String? _realDocsRoot = docsRoot.existsSync()
      ? docsRoot.resolveSymbolicLinksSync()
      : null;
  final Map<String, String> _realFolders = {};

  /// Returns the code file [codePath], a path [filesUnderCodeRoot] lists from
  /// [codeRoot], as a `/`-separated path from the project root with `..` for
  /// each folder it leaves; null when it lies in the docs root, whose files
  /// are docs.
  String? projectPathOf(String codePath, Directory codeRoot) {
    final segments = codePath.split(_separator);
    final folder = [
      codeRoot.path,
      ...segments.take(segments.length - 1),
    ].join(Platform.pathSeparator);
    final real = [
      _realFolders.putIfAbsent(
        folder,
        () => Directory(folder).resolveSymbolicLinksSync(),
      ),
      segments.last,
    ].join(Platform.pathSeparator);
    final realDocsRoot = _realDocsRoot;
    if (realDocsRoot != null &&
        real.startsWith('$realDocsRoot${Platform.pathSeparator}')) {
      return null;
    }
    return _relativePath(_realProjectRoot, real);
  }
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

/// Returns [entry] as the disk spells it, `''` for the code root itself;
/// null when [ExactCasePaths] finds no file or folder it names exactly.
String? _diskSpellingOf(Directory codeRoot, String entry) {
  final verdict = ExactCasePaths().resolve(codeRoot, entry);
  return switch (verdict.kind) {
    CodePathKind.empty => '',
    CodePathKind.file || CodePathKind.folder => verdict.diskPath,
    _ => null,
  };
}

/// Whether a folder on the way to [entry], or the entry itself, is a link.
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

/// Whether [name] starts with a dot, which every listing skips.
bool _isDotName(String name) => name.startsWith(_dotName);

/// Whether [folder] holds a `.git` entry, a folder or a file.
bool _holdsGitEntry(Directory folder) =>
    FileSystemEntity.typeSync(
      '${folder.path}$_separator.git',
      followLinks: false,
    ) !=
    FileSystemEntityType.notFound;

/// Returns the last segment of a listed entity's [path], which joins its
/// folder with `/` or the platform separator.
String _nameOf(String path) {
  final slash = path.lastIndexOf(_separator);
  final native = path.lastIndexOf(Platform.pathSeparator);
  return path.substring((slash > native ? slash : native) + 1);
}

/// Returns the rules that apply in [folder], the child [name] of the folder
/// [rules] apply in; null when those rules ignore it.
///
/// A folder holding a `.git` entry tops a work tree of its own, so the outer
/// rules never judge it or anything below it.
GitIgnoreRules? _childRules(
  GitIgnoreRules rules,
  String name,
  Directory folder,
) {
  if (_holdsGitEntry(folder)) return GitIgnoreRules.above(folder);
  if (rules.ignores(name, isFolder: true)) return null;
  return rules.within(folder);
}

/// Adds the files under [folderPath] that [rules], the rules applying in it,
/// leave in.
void _collect(
  Directory codeRoot,
  String folderPath,
  GitIgnoreRules rules,
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
    final name = _nameOf(entity.path);
    if (_isDotName(name)) continue;
    final path = folderPath.isEmpty ? name : '$folderPath$_separator$name';
    switch (entity) {
      case File():
        if (!rules.ignores(name, isFolder: false)) files.add(path);
      case Directory():
        if (_isUnder(skipFolders, path)) break;
        if (skipRepositories && _holdsGitEntry(entity)) break;
        final childRules = _childRules(
          rules,
          name,
          Directory('${codeRoot.path}$_separator$path'),
        );
        if (childRules == null) break;
        _collect(
          codeRoot,
          path,
          childRules,
          files,
          onUnlistable,
          skipFolders,
          skipRepositories,
        );
      case _:
    }
  }
}
