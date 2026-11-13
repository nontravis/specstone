import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/doc_model/doc_path_shape.dart';
import 'package:specstone_core/src/doc_model/path_pattern.dart';
import 'package:specstone_core/src/templates/code_target.dart';

/// The docs and files one check run reports on (INV-12), and the code targets
/// its code rules run on (INV-32).
///
/// A target's scope is, for each doc it resolves to, the unit `delete` takes:
/// the doc's own path segment with every file in it, a feature's spec folder
/// in each code target too, and an untyped doc's one file. The whole project
/// has no limit. A `--target` keeps the shared docs and that target's docs:
/// a path under another target's folder is out of scope, typed or not.
final class CheckScope {
  /// Returns the scope of the whole project.
  ///
  /// Throws an `IndexFault` for a [codeTarget] the project does not name
  /// (`argument_invalid`) or an empty one (`argument_missing`).
  new project(CheckContext context, {String? codeTarget})
    : this._(
        context,
        codeTarget: codeTarget,
        docPaths: null,
        folders: const [],
      );

  /// Returns the scope of the one doc at [docPath], and nothing under it.
  ///
  /// Throws as [CheckScope.project] does.
  new doc(CheckContext context, String docPath, {String? codeTarget})
    : this._(
        context,
        codeTarget: codeTarget,
        docPaths: {docPath},
        folders: const [],
      );

  /// Returns the scope of [target], resolved as `get` resolves a name.
  ///
  /// Throws as [CheckScope.project] does.
  factory of(CheckContext context, String target, {String? codeTarget}) {
    final names = _twinNamesOf(context, codeTarget);
    final docPaths = <String>{};
    final folders = <String>{};
    for (final doc in context.index.resolve(target, codeTarget: codeTarget)) {
      final type = context.typeOf(doc);
      final roots = type == null
          ? null
          : unitRootsOf(
              context.index.set,
              type,
              doc.docPath,
              targetNames: names,
              target: doc.target,
            );
      for (final root in roots ?? [doc.docPath]) {
        (root.endsWith('/') ? folders : docPaths).add(root);
      }
    }
    return CheckScope._(
      context,
      codeTarget: codeTarget,
      docPaths: docPaths,
      folders: folders.toList(),
    );
  }

  new _(
    CheckContext context, {
    required String? codeTarget,
    required Set<String>? docPaths,
    required List<String> folders,
  }) : targets = _targetsOf(context, codeTarget),
       _otherTargetFolders = _otherTargetFoldersOf(context, codeTarget),
       _docPaths = docPaths,
       _folders = folders;

  /// The code targets the code rules run on: every target of the project, or
  /// the one `--target` names.
  final List<CodeTarget> targets;

  final List<String> _otherTargetFolders;
  final Set<String>? _docPaths;
  final List<String> _folders;

  /// Whether the run reports the project-level findings too.
  bool get isProject => _docPaths == null;

  /// Whether the file at [docPath] is in scope, read or not, typed or not.
  bool contains(String docPath) {
    if (_otherTargetFolders.any(docPath.startsWith)) return false;
    final docs = _docPaths;
    return docs == null ||
        docs.contains(docPath) ||
        _folders.any(docPath.startsWith);
  }
}

List<CodeTarget> _targetsOf(CheckContext context, String? codeTarget) {
  context.index.checkCodeTarget(codeTarget);
  return [
    for (final target in context.targets)
      if (codeTarget == null || target.name == codeTarget) target,
  ];
}

/// Returns the target names a per-target spec folder is read in: those of the
/// scope when the project names several, else none.
List<String> _twinNamesOf(CheckContext context, String? codeTarget) =>
    context.index.targetNames.length > 1
    ? targetNamesOf(_targetsOf(context, codeTarget))
    : const [];

/// Returns the folders, ending in `/`, that per-target doc types give each
/// target the run does not keep; empty without a [codeTarget] or twins.
List<String> _otherTargetFoldersOf(CheckContext context, String? codeTarget) {
  final names = context.index.targetNames;
  if (codeTarget == null || names.length < 2) return const [];
  return [
    for (final type in context.index.set.docTypes)
      if (type.isPerTarget)
        for (final path in type.paths)
          for (final name in names)
            if (name != codeTarget) PathPattern(path).targetFolder(name),
  ];
}
