import 'dart:io';

import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';

final String _separator = Platform.pathSeparator;

/// The file or folder a `format` or `build` run works on.
///
/// Its [entity] is canonical, so it compares against the docs root without
/// symbolic links in the way.
final class Target {
  new(this.entity, this.docPath);

  /// The existing file or folder, at its canonical path.
  final FileSystemEntity entity;

  /// The path relative to the docs root, `/`-separated; `''` for the root.
  final String docPath;

  /// Whether the target is the docs root itself.
  bool get isDocsRoot => docPath.isEmpty;
}

/// A Specstone project opened for rendering: its root, docs root, and the
/// doc types its path patterns come from.
///
/// Every path it holds or compares is canonical, because a working directory
/// may sit behind a symbolic link (macOS temp folders do) and "inside the
/// docs root" must hold through it.
final class DocsProject {
  new _({
    required this.projectRoot,
    required this.docsRoot,
    required this.matcher,
  });

  /// Opens the project holding [workingDirectory] and loads its doc types.
  ///
  /// Throws `project_not_found` before any pack is read when no folder from
  /// [workingDirectory] upward holds `.specstone/config.yaml`; a
  /// `TemplateFault` from [templates] propagates unchanged.
  static DocsProject open({
    required TemplateResolver templates,
    required Directory workingDirectory,
    required Directory? homeDirectory,
  }) {
    final found = findProjectRoot(workingDirectory);
    if (found == null) {
      throw RenderFault(
        RenderFaultCode.projectNotFound,
        'no Specstone project: no folder from the working directory upward '
        'holds $projectConfigPath',
      );
    }
    final set = templates.resolve(
      workingDirectory: workingDirectory,
      homeDirectory: homeDirectory,
    );
    final projectRoot = Directory(found.resolveSymbolicLinksSync());
    return DocsProject._(
      projectRoot: projectRoot,
      docsRoot: Directory(
        _canonicalPath('${projectRoot.path}${_separator}docs'),
      ),
      matcher: DocTypeMatcher(set),
    );
  }

  /// The canonical project root.
  final Directory projectRoot;

  /// The canonical `<project root>/docs/`, which may not exist.
  final Directory docsRoot;

  /// Finds the doc type of a DocPath.
  final DocTypeMatcher matcher;

  /// Resolves [target] from [workingDirectory] to an existing file or folder
  /// inside the docs root.
  ///
  /// A null [target] takes the docs root when [defaultsToDocsRoot] is set and
  /// is `target_missing` otherwise. Throws `target_not_found` for a path that
  /// does not exist and `target_outside_docs_root` for one whose canonical
  /// path is neither the docs root nor below it.
  Target resolveTarget(
    String? target, {
    required Directory workingDirectory,
    required bool defaultsToDocsRoot,
  }) {
    if (target != null) {
      return _targetAt(_absolute(target, workingDirectory), asGiven: target);
    }
    if (!defaultsToDocsRoot) {
      throw RenderFault(
        RenderFaultCode.targetMissing,
        'no target given: name a file or folder under the docs root to build',
      );
    }
    return _targetAt(docsRoot.path, asGiven: 'docs/');
  }

  /// Returns [entity] relative to the project root with `/` separators, or
  /// its absolute path when it lies outside the project root.
  ///
  /// A path in the docs root prints as `docs/...` even when `docs` is a link
  /// to a folder outside the project. [entity] may not exist yet; its nearest
  /// existing ancestor is made canonical first.
  String displayPath(FileSystemEntity entity) {
    final path = _canonicalPath(entity.absolute.path);
    final docPath = _docPathOf(path);
    if (docPath != null) return docPath.isEmpty ? 'docs' : 'docs/$docPath';
    final root = projectRoot.path;
    if (path == root) return '.';
    final prefix = root.endsWith(_separator) ? root : '$root$_separator';
    if (!path.startsWith(prefix)) return path;
    return path.substring(prefix.length).split(_separator).join('/');
  }

  /// Whether [entity] is the docs root or lies below it.
  ///
  /// [entity] may not exist yet. Symbolic links and `..` segments are resolved
  /// first, so no spelling of a path inside the docs root compares as outside.
  bool isInsideDocsRoot(FileSystemEntity entity) =>
      _docPathOf(_canonicalPath(entity.absolute.path)) != null;

  Target _targetAt(String path, {required String asGiven}) {
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.notFound) {
      throw RenderFault(
        RenderFaultCode.targetNotFound,
        'the target $asGiven does not exist',
      );
    }
    final canonical = File(path).resolveSymbolicLinksSync();
    final docPath = _docPathOf(canonical);
    if (docPath == null) {
      throw RenderFault(
        RenderFaultCode.targetOutsideDocsRoot,
        'the target $asGiven lies outside the docs root docs/',
      );
    }
    final entity = type == FileSystemEntityType.directory
        ? Directory(canonical)
        : File(canonical);
    return Target(entity, docPath);
  }

  /// Returns [canonical] relative to the docs root, or null when outside.
  String? _docPathOf(String canonical) {
    final root = docsRoot.path;
    if (canonical == root) return '';
    final prefix = root.endsWith(_separator) ? root : '$root$_separator';
    if (!canonical.startsWith(prefix)) return null;
    return canonical.substring(prefix.length).split(_separator).join('/');
  }
}

String _absolute(String path, Directory workingDirectory) {
  if (File(path).isAbsolute) return path;
  return '${workingDirectory.absolute.path}$_separator$path';
}

/// Returns [path] with every `/` changed to `\` on Windows, else unchanged.
///
/// Windows accepts both separators and Dart keeps whichever was written, so a
/// path that is cut at `\` alone mis-splits when it holds a `/`. Elsewhere `\`
/// is an ordinary file name character, so nothing changes. [isWindows] picks
/// the style; it defaults to the running platform.
String withNativeSeparators(String path, {bool? isWindows}) =>
    (isWindows ?? Platform.isWindows) ? path.replaceAll('/', r'\') : path;

/// Returns [path] with symbolic links resolved.
///
/// The path may not exist: the nearest existing ancestor is resolved and the
/// missing names are appended, so a build output file that is not written yet
/// still compares against canonical roots. A `..` or `.` among the missing
/// names is applied, because nothing missing can be a symbolic link.
String _canonicalPath(String path) {
  final missing = <String>[];
  var existing = _withoutTrailingSeparator(
    withNativeSeparators(File(path).absolute.path),
  );
  while (FileSystemEntity.typeSync(existing) == FileSystemEntityType.notFound) {
    final cut = existing.lastIndexOf(_separator);
    missing.add(existing.substring(cut + 1));
    // An absolute path always reaches the file-system root, which exists.
    existing = cut <= 0 ? _separator : existing.substring(0, cut);
  }
  var resolved = File(existing).resolveSymbolicLinksSync();
  for (final name in missing.reversed) {
    if (name == '.') continue;
    if (name == '..') {
      final cut = resolved.lastIndexOf(_separator);
      resolved = cut <= 0 ? _separator : resolved.substring(0, cut);
      continue;
    }
    resolved = resolved.endsWith(_separator)
        ? '$resolved$name'
        : '$resolved$_separator$name';
  }
  return resolved;
}

String _withoutTrailingSeparator(String path) {
  var end = path.length;
  while (end > 1 && (path[end - 1] == _separator || path[end - 1] == '/')) {
    end--;
  }
  return path.substring(0, end);
}
