import 'dart:io';

import 'package:specstone_core/src/canonical_path.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart' show docsFolderName;

/// The DocPath prefix of a record, read from the project root rather than the
/// docs root.
const recordsRootDocPath = '.specstone/records/';

/// [recordsRootDocPath] without its closing `/`: the DocPath of the folder.
const recordsFolderDocPath = '.specstone/records';

/// Returns the records folder of [projectRoot], or null when it is absent or
/// a symbolic link, which no walk follows.
Directory? recordsRootOf(Directory projectRoot) {
  final folder = Directory(
    '${projectRoot.path}${Platform.pathSeparator}'
    '${recordsFolderDocPath.split('/').join(Platform.pathSeparator)}',
  );
  final type = FileSystemEntity.typeSync(folder.path, followLinks: false);
  return type == FileSystemEntityType.directory ? folder : null;
}

/// Whether [docPath] names a file under the records root.
bool isRecordsDocPath(String docPath) => docPath.startsWith(recordsRootDocPath);

/// Returns the folder [docPath] is relative to: [projectRoot] for a records
/// DocPath, else [docsRoot].
Directory rootOfDocPath(
  String docPath, {
  required Directory docsRoot,
  required Directory projectRoot,
}) => isRecordsDocPath(docPath) ? projectRoot : docsRoot;

/// Returns the file [docPath] names, under [rootOfDocPath].
///
/// The path takes the platform's separators.
File fileOfDocPath(
  String docPath, {
  required Directory docsRoot,
  required Directory projectRoot,
}) {
  final root = rootOfDocPath(
    docPath,
    docsRoot: docsRoot,
    projectRoot: projectRoot,
  );
  final separator = Platform.pathSeparator;
  final base = root.path.endsWith(separator)
      ? root.path
      : '${root.path}$separator';
  return File('$base${docPath.split('/').join(separator)}');
}

/// Returns the DocPath of canonical [path], or null when it lies in neither
/// root.
///
/// The docs root itself is `''` and the records folder `.specstone/records`;
/// the records root counts only below `.specstone/records/` of [projectRoot].
String? docPathOfPath(
  String path, {
  required Directory docsRoot,
  required Directory projectRoot,
}) {
  if (path == docsRoot.path) return '';
  final inDocs = pathInside(docsRoot.path, path);
  if (inDocs != null) return inDocs;
  final inProject = pathInside(projectRoot.path, path);
  if (inProject == null) return null;
  final isRecordsFolder = inProject == recordsFolderDocPath;
  return isRecordsFolder || isRecordsDocPath(inProject) ? inProject : null;
}

/// Returns [docPath] as a journal step takes it: relative to the project root
/// and `/`-separated.
String projectPathOfDocPath(String docPath) =>
    isRecordsDocPath(docPath) ? docPath : '$docsFolderName/$docPath';

/// Returns the DocPath of [projectPath], the inverse of
/// [projectPathOfDocPath]; a path under neither root stays as it is.
String docPathOfProjectPath(String projectPath) =>
    projectPath.startsWith('$docsFolderName/')
    ? projectPath.substring(docsFolderName.length + 1)
    : projectPath;
