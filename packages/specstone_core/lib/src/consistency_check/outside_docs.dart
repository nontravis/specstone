import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/doc_model/records_root.dart';

const _parent = '..';

/// Returns [projectPath] when it lies inside the project and outside the
/// checked folders; null otherwise.
///
/// The caller resolves the link to a path from the project root: a doc link
/// by `projectPathOfDocPath`, a file link by `projectFilePathOf`. A path that
/// folds above the project root is outside the project, and the project root
/// itself (an empty path) holds the docs, so it is no file outside them.
String? outsideDocsPathOf(CheckContext context, String projectPath) {
  if (projectPath.isEmpty || _isAboveProject(projectPath)) return null;
  return _isInCheckedFolder(context, projectPath) ? null : projectPath;
}

bool _isAboveProject(String projectPath) =>
    projectPath == _parent || projectPath.startsWith('$_parent/');

bool _isInCheckedFolder(CheckContext context, String projectPath) {
  if (projectPath == recordsFolderDocPath) {
    return context.checkedFolders.contains(recordsFolderDocPath);
  }
  final docPath = docPathOfProjectPath(projectPath);
  return docPath != null && context.isCheckedPath(docPath);
}
