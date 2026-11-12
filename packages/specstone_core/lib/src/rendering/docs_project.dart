import 'dart:io';

import 'package:specstone_core/src/canonical_path.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart' show docsFolderName;
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/document_writing/approval.dart' as approval;
import 'package:specstone_core/src/document_writing/journal_bounds.dart'
    show requireWritableTarget;
import 'package:specstone_core/src/document_writing/root_trust.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/code_target.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
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
    required this.trust,
    required this.codeRoot,
    required this.targets,
    required this.stampsHaveRun,
    required this.matcher,
    required this.set,
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
    final trust = RootTrust.locate(
      workingDirectory,
      homeDirectory: homeDirectory,
    );
    final set = templates.resolve(
      workingDirectory: workingDirectory,
      homeDirectory: homeDirectory,
    );
    final projectRoot = trust.projectRoot;
    final config = ProjectConfig.read(projectRoot);
    final targets = List<CodeTarget>.unmodifiable(config.targets);
    return DocsProject._(
      trust: trust,
      codeRoot: Directory(
        canonicalPath('${projectRoot.path}$_separator${config.codeRoot}'),
      ),
      targets: targets,
      stampsHaveRun: approval.stampsHaveRun(config.pins),
      matcher: DocTypeMatcher(set),
      set: set,
    );
  }

  /// Whether the config pins a pack at or above the version whose upgrade
  /// stamps every doc; read once at open.
  final bool stampsHaveRun;

  /// The roots and whether this machine's Owner trusts them for writes.
  final RootTrust trust;

  /// The canonical project root.
  Directory get projectRoot => trust.projectRoot;

  /// The canonical `<project root>/docs/`, which may not exist.
  Directory get docsRoot => trust.docsRoot;

  /// The folder code paths are written from: the project root joined with
  /// `code_root`.
  ///
  /// Canonical when it exists; otherwise the joined path with its existing
  /// part canonical and `..` applied, so a docs-only checkout still opens.
  /// With `targets:` this is the first target's root; [codeRootOf] resolves
  /// each target's own root.
  final Directory codeRoot;

  /// The config's code targets, in config order.
  final List<CodeTarget> targets;

  /// The named targets, in config order; empty with one unnamed target.
  List<String> get targetNames => [
    for (final target in targets)
      if (target.name != null) target.name!,
  ];

  /// Returns [target]'s code root as the project root joined with its
  /// `code_root`, canonical as [codeRoot] is.
  Directory codeRootOf(CodeTarget target) => Directory(
    canonicalPath('${projectRoot.path}$_separator${target.codeRoot}'),
  );

  /// Throws `output_not_writable` unless the Owner trusts the roots and a
  /// write to [path] lands inside the project or docs root and below no `.git`
  /// entry, as the disk stands now.
  ///
  /// The gate of every write outside the journal; see [requireWritableTarget].
  void requireWritablePath(String path) => requireWritableTarget(
    path,
    projectRoot: projectRoot,
    docsRoot: docsRoot,
    trust: trust,
  );

  /// Finds the doc type of a DocPath.
  final DocTypeMatcher matcher;

  /// The merged doc types [matcher] reads.
  final MergedSet set;

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

  /// Returns the DocPath of the file [path] names from [workingDirectory], or
  /// null when it names no existing file inside the docs root.
  ///
  /// Symbolic links and `..` resolve first, as [resolveTarget] resolves them.
  String? docPathAt(String path, {required Directory workingDirectory}) {
    final absolute = _absolute(path, workingDirectory);
    if (!FileSystemEntity.isFileSync(absolute)) return null;
    return _docPathOf(File(absolute).resolveSymbolicLinksSync());
  }

  /// Returns [entity] relative to the project root with `/` separators, or
  /// its absolute path when it lies outside the project root.
  ///
  /// A path in the docs root prints as `docs/...` even when `docs` is a link
  /// to a folder outside the project. [entity] may not exist yet; its nearest
  /// existing ancestor is made canonical first.
  String displayPath(FileSystemEntity entity) {
    final path = canonicalPath(entity.absolute.path);
    final docPath = _docPathOf(path);
    if (docPath != null) {
      return docPath.isEmpty ? docsFolderName : '$docsFolderName/$docPath';
    }
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
      _docPathOf(canonicalPath(entity.absolute.path)) != null;

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
