import 'dart:io';

import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/root_trust.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/project_config.dart';

/// The legacy SDD context doc, relative to the project root.
const legacyContextPath = 'docs/prds/d01_context.md';

/// Returns the migrate root from [workingDirectory] upward, the first project
/// root holding `.specstone/config.yaml`, [legacyContextPath], or a journal
/// file, and the folder whose `docs` link led to it.
///
/// The walk is [matchRootUpward], the one [findProjectRoot] takes. A journal
/// sits beside the linked docs in a linked layout (INV-1), which is the first
/// candidate. `linkFolder` is null when the root is the folder the walk
/// stopped at; both are canonical. Throws [RenderFault] `project_not_found`
/// when no folder up to the file-system root holds one.
({Directory root, Directory? linkFolder}) locateMigrateRoot(
  Directory workingDirectory,
) {
  final match = matchRootUpward(workingDirectory, _isMarked);
  if (match == null) {
    throw RenderFault(
      RenderFaultCode.projectNotFound,
      'no Specstone project: no folder from the working directory upward '
      'holds $projectConfigPath, $legacyContextPath, or a pending '
      '${MoveJournal.journalPath}',
    );
  }
  final (:folder, :root) = match;
  return (root: root, linkFolder: folder.path == root.path ? null : folder);
}

/// Returns the trust of the roots a write command, `init`, or `migrate` run
/// from [workingDirectory] would write into.
///
/// A project with a config is the one every write command opens. Without one,
/// a folder holding the legacy context doc or a journal is the root `migrate`
/// finds; with none, the root is the one `init` takes: [rootThroughDocsLink]
/// of [workingDirectory], no walk up. Never throws `project_not_found`.
RootTrust locateSetupTrust(
  Directory workingDirectory, {
  required Directory? homeDirectory,
}) {
  if (matchProjectRoot(workingDirectory) != null) {
    return RootTrust.locate(workingDirectory, homeDirectory: homeDirectory);
  }
  final found = matchRootUpward(workingDirectory, _isMarked);
  return RootTrust.at(
    folder:
        found?.folder ?? Directory(workingDirectory.resolveSymbolicLinksSync()),
    root: found?.root ?? rootThroughDocsLink(workingDirectory),
    homeDirectory: homeDirectory,
  );
}

/// Returns the `/`-separated path from [from] to [to], `.` for one folder.
///
/// Both are canonical, so their names compare one by one. Null when no
/// relative path exists: two Windows drives or network shares.
String? relativeFolderPath(Directory from, Directory to) {
  final source = _rootedNames(from.path);
  final target = _rootedNames(to.path);
  if (source.root != target.root) return null;
  var shared = 0;
  while (shared < source.names.length &&
      shared < target.names.length &&
      source.names[shared] == target.names[shared]) {
    shared++;
  }
  final steps = [
    for (var i = shared; i < source.names.length; i++) '..',
    ...target.names.skip(shared),
  ];
  return steps.isEmpty ? '.' : steps.join('/');
}

/// Splits an absolute [path] into its root and its folder names.
///
/// On Windows the root is the drive (`c:`) or the share (`\\host\share`),
/// lowercased, as Windows matches them in any case; elsewhere it is `/`.
({String root, List<String> names}) _rootedNames(String path) {
  if (!Platform.isWindows) return (root: '/', names: _namesOf(path.split('/')));
  final parts = path.replaceAll('/', r'\').split(r'\');
  final rootLength = path.startsWith(r'\\') || path.startsWith('//') ? 4 : 1;
  return (
    root: parts.take(rootLength).join(r'\').toLowerCase(),
    names: _namesOf(parts.skip(rootLength)),
  );
}

List<String> _namesOf(Iterable<String> parts) => [
  for (final part in parts)
    if (part.isNotEmpty) part,
];

bool _isMarked(Directory folder) => const [
  projectConfigPath,
  legacyContextPath,
  MoveJournal.journalPath,
].any((marker) => File.fromUri(folder.uri.resolve(marker)).existsSync());
