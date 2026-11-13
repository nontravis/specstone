import 'dart:io';

import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/setup_migration/agent_files.dart'
    show agentFilePaths, agentInstructionNames;
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/project_config.dart';

const _separator = '/';

/// The project root as a repository top.
const _projectTop = '.';

/// Separates the paths `git ls-files -z` prints.
const _listSeparator = '\x00';

/// Folders whose every file is an agent file.
const _agentFolders = {'.claude', '.agents', '.codex', '.cursor'};

/// Whether [projectPath], a `/`-separated path from the project root, is an
/// agent file: an instruction file the CLI writes a block into, or any file
/// under an agent folder.
///
/// A file named for an agent, `CLAUDE.md`, `AGENTS.md`, or `GEMINI.md`,
/// matches at any depth; the Copilot file, which has a folder in its path,
/// matches at the project root only.
bool isAgentFile(String projectPath) {
  final segments = projectPath.split(_separator);
  final isInstruction = agentInstructionNames.any(
    (name) =>
        name.contains(_separator) ? projectPath == name : segments.last == name,
  );
  return isInstruction ||
      segments.take(segments.length - 1).any(_agentFolders.contains);
}

/// Returns the agent files a path-moving command reads for mentions, by their
/// `/`-separated path from [projectRoot], in code point order.
///
/// A work tree with a first commit gives the files its repository tracks, plus
/// the instruction files at each top [config] lists, tracked or not. Without
/// one, or when git cannot start or refuses its git dir, only the instruction
/// files at the project root and at each listed top.
///
/// Throws `MigrateFault` `git_failed` when `git ls-files` fails in a work tree.
List<String> agentFilesOf(
  Directory projectRoot,
  ProjectConfig config,
  RunGit runGit,
) {
  final files = <String>{};
  for (final top in [_projectTop, ...config.agentFileRoots]) {
    final folder = top == _projectTop
        ? projectRoot
        : Directory('${projectRoot.path}$_separator$top');
    final tracked = _trackedAgentFiles(folder, runGit);
    final instruction = tracked == null || top != _projectTop
        ? _instructionFiles(folder)
        : const <String>[];
    for (final path in [...?tracked, ...instruction]) {
      files.add(top == _projectTop ? path : '$top$_separator$path');
    }
  }
  return files.toList()..sort(compareCodePoints);
}

/// Returns the instruction files [folder] holds, by their path from it.
List<String> _instructionFiles(Directory folder) => [
  for (final path in agentFilePaths)
    if (_isFileIn(folder, path)) path,
];

/// Returns the agent files [folder]'s repository tracks under it, by their
/// path from [folder]; null when [folder] is no work tree with a first commit
/// or git cannot read it.
List<String>? _trackedAgentFiles(Directory folder, RunGit runGit) {
  try {
    final head = runGit([
      'rev-parse',
      '--verify',
      '-q',
      'HEAD',
    ], workingDirectory: folder.path);
    if (head.exitCode != 0) return null;
    final listing = runGit(['ls-files', '-z'], workingDirectory: folder.path);
    if (listing.exitCode != 0) throw _listFailed(listing);
    return [
      for (final path in (listing.stdout as String).split(_listSeparator))
        if (isAgentFile(path) && _isFileIn(folder, path)) path,
    ];
  } on ProcessException {
    return null;
  } on MigrateFault catch (fault) {
    if (fault.code != MigrateFaultCode.gitWorkTreeRequired) rethrow;
    return null;
  }
}

MigrateFault _listFailed(ProcessResult listing) => MigrateFault(
  MigrateFaultCode.gitFailed,
  'git ls-files failed: ${'${listing.stderr}'.trim()}; fix the cause, then '
  'run the command again',
);

bool _isFileIn(Directory folder, String path) =>
    File('${folder.path}$_separator$path').existsSync();
