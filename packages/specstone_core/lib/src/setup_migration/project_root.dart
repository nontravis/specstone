import 'dart:io';

import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/project_config.dart';

/// The legacy SDD context doc, relative to the project root.
const legacyContextPath = 'docs/prds/d01_context.md';

/// Returns the project root for a folder holding a `docs` link.
///
/// When `<folder>/docs` is a symbolic link, the root is the parent of the
/// link's resolved target; otherwise [folder]. The result is canonical.
Directory rootThroughDocsLink(Directory folder) {
  final docs = '${folder.path}${Platform.pathSeparator}docs';
  if (FileSystemEntity.isLinkSync(docs)) {
    return Directory(Link(docs).resolveSymbolicLinksSync()).parent;
  }
  return Directory(folder.resolveSymbolicLinksSync());
}

/// Returns the first folder from [workingDirectory] upward holding
/// `.specstone/config.yaml`, [legacyContextPath], or a journal file.
///
/// The result goes through [rootThroughDocsLink]. Throws [RenderFault]
/// `project_not_found` when no folder up to the file-system root holds one.
Directory findMigrateRoot(Directory workingDirectory) {
  var dir = workingDirectory.absolute;
  while (true) {
    if (_isMarked(dir)) return rootThroughDocsLink(dir);
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw RenderFault(
        RenderFaultCode.projectNotFound,
        'no Specstone project: no folder from the working directory upward '
        'holds $projectConfigPath, $legacyContextPath, or a pending '
        '${MoveJournal.journalPath}',
      );
    }
    dir = parent;
  }
}

bool _isMarked(Directory dir) => const [
  projectConfigPath,
  legacyContextPath,
  MoveJournal.journalPath,
].any((marker) => File.fromUri(dir.uri.resolve(marker)).existsSync());
