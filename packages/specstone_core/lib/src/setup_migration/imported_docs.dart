import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/canonical_path.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/setup_migration/agent_files.dart';
import 'package:specstone_core/src/setup_migration/agent_targets.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/version.dart';

/// The variable Claude Code sets in the processes it starts.
const _claudeCodeVariable = 'CLAUDECODE';

/// The instruction file Claude Code loads at the project root and at each
/// repository top.
const _claudeFile = 'CLAUDE.md';

/// Returns the DocPath of each typed doc the Specstone block of a `CLAUDE.md`
/// imports, empty unless [environment] marks a Claude Code session.
///
/// Reads the file at the project root and at each repository top, resolves
/// each `@` path from its file's folder, and keeps a path that names a typed
/// doc under the docs root.
Set<String> importedDocPaths(
  DocsProject project,
  DocIndex index, {
  required Map<String, String> environment,
}) {
  if ((environment[_claudeCodeVariable] ?? '').isEmpty) return const {};
  final inputs = AgentFileInputs(
    projectRoot: project.projectRoot,
    cliVersion: specstoneVersion,
    codeRootFolders: codeFoldersOf(
      project.projectRoot,
      project.set,
      targets: project.targets,
    ),
    agentFileRoots: ProjectConfig.read(project.projectRoot).agentFileRoots,
  );
  final docPaths = <String>{};
  for (final base in agentFileBasesOf(inputs)) {
    final text = _textOf(File('${base.directory.path}/$_claudeFile'));
    if (text == null) continue;
    for (final line in importLinesOf(text)) {
      final docPath = _docPathOf(project, index, base.directory, line);
      if (docPath != null) docPaths.add(docPath);
    }
  }
  return docPaths;
}

/// Returns the text of [file], or null when it is no file.
String? _textOf(File file) {
  if (!file.existsSync()) return null;
  return utf8.decode(file.readAsBytesSync(), allowMalformed: true);
}

/// Returns the DocPath of the typed doc the relative [line] names from
/// [folder], or null; an absolute [line] names no doc.
String? _docPathOf(
  DocsProject project,
  DocIndex index,
  Directory folder,
  String line,
) {
  if (File(line).isAbsolute) return null;
  final path = absoluteFrom(folder, line);
  if (FileSystemEntity.typeSync(path) != FileSystemEntityType.file) return null;
  final docPath = pathInside(project.docsRoot.path, canonicalPath(path));
  if (docPath == null) return null;
  return (index.at(docPath)?.isTyped ?? false) ? docPath : null;
}
