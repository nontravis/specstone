import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/doc_model/path_pattern.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';

/// The docs and files one check run reports on (INV-12).
///
/// A target's scope is the docs it resolves to, every doc whose parent chain
/// reaches one, and every file at any depth under the folder of each of those
/// docs whose doc type is a folder doc. The whole project has no limit.
final class CheckScope {
  new project() : _docPaths = null, _folders = const [];

  /// Returns the scope of the one doc at [docPath], and nothing under it.
  new doc(String docPath) : _docPaths = {docPath}, _folders = const [];

  /// Returns the scope of [target], resolved as `get` resolves a name.
  factory of(CheckContext context, String target) {
    final docs = context.index.under(target);
    final isFolderDoc = <String, bool>{};
    final folders = <String>{};
    for (final doc in docs) {
      final path = context.typeOf(doc)?.path;
      if (path == null) continue;
      if (isFolderDoc.putIfAbsent(path, () => PathPattern(path).isFolderDoc)) {
        folders.add(_folderOf(doc));
      }
    }
    return CheckScope._({
      for (final doc in docs) doc.docPath,
    }, folders.toList());
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

  static String _folderOf(IndexedDoc doc) =>
      doc.docPath.substring(0, doc.docPath.lastIndexOf('/') + 1);
}
