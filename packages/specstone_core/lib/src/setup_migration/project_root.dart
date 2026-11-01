import 'dart:io';

import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/project_config.dart';

/// The legacy SDD context doc, relative to the project root.
const legacyContextPath = 'docs/prds/d01_context.md';

/// Returns the first folder from [workingDirectory] upward holding
/// `.specstone/config.yaml`, [legacyContextPath], or a journal file, itself
/// or, for the journal, at the root its `docs` link stands for.
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

bool _isMarked(Directory dir) {
  bool holds(Directory folder, String marker) =>
      File.fromUri(folder.uri.resolve(marker)).existsSync();
  const markers = [
    projectConfigPath,
    legacyContextPath,
    MoveJournal.journalPath,
  ];
  if (markers.any((marker) => holds(dir, marker))) return true;
  // A run stopped between its commits has moved the legacy context doc; in a
  // linked layout its journal sits beside the linked docs (INV-1).
  return holds(rootThroughDocsLink(dir), MoveJournal.journalPath);
}
