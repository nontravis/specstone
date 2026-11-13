import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/doc_model/doc_path_shape.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/code_target.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// The docs and files one check run reports on (INV-12), and the code targets
/// its code rules run on (INV-32).
///
/// A target's scope is, for each doc it resolves to, the unit `delete` takes:
/// the doc's own path segment with every file in it, a feature's spec folder
/// in each code target too, and an untyped doc's one file. The whole project
/// has no limit. A `--target` keeps the shared docs and that target's docs.
final class CheckScope {
  /// Returns the scope of the whole project.
  ///
  /// Throws an `IndexFault` `argument_invalid` for a [codeTarget] the project
  /// does not name.
  new project(CheckContext context, {String? codeTarget})
    : this._(
        targets: _targetsOf(context, codeTarget),
        codeTarget: codeTarget,
        docPaths: null,
        folders: const [],
      );

  /// Returns the scope of the one doc at [docPath], and nothing under it.
  ///
  /// Throws as [CheckScope.project] does.
  new doc(CheckContext context, String docPath, {String? codeTarget})
    : this._(
        targets: _targetsOf(context, codeTarget),
        codeTarget: codeTarget,
        docPaths: {docPath},
        folders: const [],
      );

  /// Returns the scope of [target], resolved as `get` resolves a name.
  ///
  /// Throws as [CheckScope.project] does.
  factory of(CheckContext context, String target, {String? codeTarget}) {
    final targets = _targetsOf(context, codeTarget);
    final docPaths = <String>{};
    final folders = <String>{};
    for (final doc in context.index.resolve(target, codeTarget: codeTarget)) {
      final type = context.typeOf(doc);
      final roots = type == null
          ? null
          : _unitRootsOf(context, doc, type, targets);
      for (final root in roots ?? [doc.docPath]) {
        (root.endsWith('/') ? folders : docPaths).add(root);
      }
    }
    return CheckScope._(
      targets: targets,
      codeTarget: codeTarget,
      docPaths: docPaths,
      folders: folders.toList(),
    );
  }

  new _({
    required this.targets,
    required String? codeTarget,
    required Set<String>? docPaths,
    required List<String> folders,
  }) : _codeTarget = codeTarget,
       _docPaths = docPaths,
       _folders = folders;

  /// The code targets the code rules run on: every target of the project, or
  /// the one `--target` names.
  final List<CodeTarget> targets;

  final String? _codeTarget;
  final Set<String>? _docPaths;
  final List<String> _folders;

  /// Whether the run reports the project-level findings too.
  bool get isProject => _docPaths == null;

  /// Whether the file at [docPath] is in scope, read or not, typed or not.
  bool contains(String docPath) {
    final docs = _docPaths;
    return docs == null ||
        docs.contains(docPath) ||
        _folders.any(docPath.startsWith);
  }

  /// Whether [doc] is in scope: in a scope path, and shared or of the one
  /// code target the run names.
  bool containsDoc(IndexedDoc doc) =>
      contains(doc.docPath) &&
      (_codeTarget == null || doc.target == null || doc.target == _codeTarget);
}

List<CodeTarget> _targetsOf(CheckContext context, String? codeTarget) {
  context.index.checkCodeTarget(codeTarget);
  return [
    for (final target in context.targets)
      if (codeTarget == null || target.name == codeTarget) target,
  ];
}

/// Returns the paths of the unit of [doc], as `delete` takes it: its own
/// segment, then the folders of its spec docs, a per-target spec doc type's
/// folder once for each named one of [targets] when the project names
/// several.
List<String>? _unitRootsOf(
  CheckContext context,
  IndexedDoc doc,
  MergedDocType type,
  List<CodeTarget> targets,
) {
  final set = context.index.set;
  final shape = DocPathShape.ofDoc(type, set, doc.docPath);
  final values = shape?.valuesOf(doc.docPath);
  if (shape == null || values == null) return null;
  final twinned = context.index.targetNames.length > 1;
  return [
    shape.ownPathOf(doc.docPath),
    for (final (child, folder) in specChildrenOf(set, type, shape, values))
      if (child.isPerTarget && twinned)
        for (final name in targetNamesOf(targets)) _inTargetFolder(folder, name)
      else
        folder,
  ];
}

/// Returns [folder] with [target] as the folder right after its first segment,
/// where a per-target doc type's pattern puts it.
String _inTargetFolder(String folder, String target) =>
    folder.replaceFirst('/', '/$target/');
