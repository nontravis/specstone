import 'dart:io';

import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/project_config.dart';

/// The legacy SDD context doc, relative to the project root.
const legacyContextPath = 'docs/prds/d01_context.md';

/// Returns the first project root from [workingDirectory] upward holding
/// `.specstone/config.yaml`, [legacyContextPath], or a journal file.
///
/// The walk is [findRootUpward], the one [findProjectRoot] takes. A journal
/// sits beside the linked docs in a linked layout (INV-1), which is the first
/// candidate. Throws [RenderFault] `project_not_found` when no folder up to the
/// file-system root holds one.
Directory findMigrateRoot(Directory workingDirectory) {
  final root = findRootUpward(workingDirectory, _isMarked);
  if (root != null) return root;
  throw RenderFault(
    RenderFaultCode.projectNotFound,
    'no Specstone project: no folder from the working directory upward '
    'holds $projectConfigPath, $legacyContextPath, or a pending '
    '${MoveJournal.journalPath}',
  );
}

bool _isMarked(Directory folder) => const [
  projectConfigPath,
  legacyContextPath,
  MoveJournal.journalPath,
].any((marker) => File.fromUri(folder.uri.resolve(marker)).existsSync());
