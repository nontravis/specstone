import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/doc_model/doc_path_shape.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';

/// The docs and files one check run reports on (INV-12).
///
/// A target's scope is, for each doc it resolves to, the unit `delete` takes:
/// the doc's own path segment with every file in it, a feature's spec folder
/// too, and an untyped doc's one file. The whole project has no limit.
final class CheckScope {
  new project() : _docPaths = null, _folders = const [];

  /// Returns the scope of the one doc at [docPath], and nothing under it.
  new doc(String docPath) : _docPaths = {docPath}, _folders = const [];

  /// Returns the scope of [target], resolved as `get` resolves a name.
  factory of(CheckContext context, String target) {
    final docPaths = <String>{};
    final folders = <String>{};
    for (final doc in context.index.resolve(target)) {
      final type = context.typeOf(doc);
      final roots = type == null
          ? null
          : unitRootsOf(context.index.set, type, doc.docPath);
      for (final root in roots ?? [doc.docPath]) {
        (root.endsWith('/') ? folders : docPaths).add(root);
      }
    }
    return CheckScope._(docPaths, folders.toList());
  }

  new _(this._docPaths, this._folders);

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

  /// Whether [doc] is in scope.
  bool containsDoc(IndexedDoc doc) => contains(doc.docPath);
}
