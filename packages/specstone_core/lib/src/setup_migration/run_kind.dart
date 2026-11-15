import 'dart:io';

import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/release_version.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/format_run.dart';
import 'package:specstone_core/src/setup_migration/agent_targets.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/project_root.dart';
import 'package:specstone_core/src/setup_migration/skill_agent_files.dart';
import 'package:specstone_core/src/setup_migration/tree_move.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/code_target.dart' show twinNamesOf;
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:specstone_core/src/version.dart';

/// What a `specstone migrate` run does at a project root.
enum RunKind {
  /// An unfinished migration journal is replayed.
  resume,

  /// A legacy SDD tree is converted.
  legacy,

  /// At least one pin is older than its available pack version, or every pin
  /// is equal and a typed doc is off the layout `format` writes, an agent
  /// file or `specstone-*` skill or agent file drifts from what the CLI
  /// writes, or a per-target doc sits at a one-target path under two or more
  /// code targets.
  upgrade,

  /// Every pin equals its available pack version, every typed doc is laid
  /// out, no agent, skill, or agent-folder file drifts, and no per-target doc
  /// needs the tree move.
  none,
}

/// Chooses the run for the project at [root].
///
/// [RunKind.resume] when a migrate journal is pending; else [RunKind.legacy]
/// when [legacyContextPath] exists; else the pins are compared, in code point
/// order, with the available pack versions: the first newer pin throws
/// `pack_pin_newer`. After the pin refusal and before any [RunKind.upgrade]
/// or [RunKind.none] result, an `agent_files_version` above the running
/// Version throws `agent_files_newer`, whatever the older pins and agent
/// files hold. Then any older pin gives [RunKind.upgrade]. With every pin
/// equal, a doc off its layout, generated blocks aside, then any agent file
/// drift (`agentFileDrifts`, the predicate `check` uses, a malformed marker
/// included) or skill and agent file drift (`skillAndAgentFileDrifts`), then
/// two or more code targets over a per-target doc at a one-target path
/// (`treeMovesOf`), gives [RunKind.upgrade], otherwise [RunKind.none].
/// [homeDirectory] is the personal pack home, or null.
RunKind chooseRun(
  Directory root, {
  required TemplateResolver templates,
  required Directory? homeDirectory,
}) {
  if (MoveJournal.pendingMigrate(root)) return RunKind.resume;
  if (File.fromUri(root.uri.resolve(legacyContextPath)).existsSync()) {
    return RunKind.legacy;
  }
  final config = ProjectConfig.read(root);
  final pins = config.pins;
  final available = templates.availableManifests(
    pins.keys,
    homeDirectory: homeDirectory,
  );
  var older = false;
  for (final name in pins.keys.toList()..sort(compareCodePoints)) {
    final pin = pins[name]!;
    final carried = available[name]!.version;
    final compare = pin.compareTo(carried);
    if (compare > 0) throw pinNewerFault(name, pin, carried);
    if (compare < 0) older = true;
  }
  final stamp = config.agentFilesVersion;
  if (stamp != null && stamp.compareTo(runningVersion) > 0) {
    throw _agentFilesNewerFault(stamp);
  }
  if (older) return RunKind.upgrade;
  if (_hasDocOffLayout(root, templates, homeDirectory)) return RunKind.upgrade;
  if (_hasAgentFileDrift(root, templates, homeDirectory)) {
    return RunKind.upgrade;
  }
  return _hasTreeMove(root, templates, homeDirectory)
      ? RunKind.upgrade
      : RunKind.none;
}

/// Returns the `agent_files_newer` fault for a [stamp] above the running
/// Version.
MigrateFault _agentFilesNewerFault(ReleaseVersion stamp) => MigrateFault(
  MigrateFaultCode.agentFilesNewer,
  'the agent files were written by Specstone $stamp, and this Specstone is '
  '$runningVersion; run specstone upgrade, then run specstone migrate again',
  file: projectConfigPath,
  key: 'agent_files_version',
);

bool _hasTreeMove(
  Directory root,
  TemplateResolver templates,
  Directory? homeDirectory,
) {
  if (twinNamesOf(ProjectConfig.read(root).targetNames).isEmpty) return false;
  final project = DocsProject.open(
    templates: templates,
    workingDirectory: root,
    homeDirectory: homeDirectory,
  );
  return treeMovesOf(
    docPathsOf(project.docsRoot),
    project.set,
    targetNames: project.targetNames,
  ).isNotEmpty;
}

bool _hasDocOffLayout(
  Directory root,
  TemplateResolver templates,
  Directory? homeDirectory,
) {
  final project = DocsProject.open(
    templates: templates,
    workingDirectory: root,
    homeDirectory: homeDirectory,
  );
  final report = runFormat<void>(
    project,
    Target(project.docsRoot, ''),
    check: true,
  );
  return report.files.any((file) => file.status == FileStatus.formatted);
}

bool _hasAgentFileDrift(
  Directory root,
  TemplateResolver templates,
  Directory? homeDirectory,
) {
  final projectRoot = Directory(root.resolveSymbolicLinksSync());
  final config = ProjectConfig.read(projectRoot);
  final set = templates.resolve(
    workingDirectory: projectRoot,
    homeDirectory: homeDirectory,
  );
  final inputs = AgentFileInputs(
    projectRoot: projectRoot,
    cliVersion: specstoneVersion,
    codeRootFolders: codeFoldersOf(projectRoot, set, targets: config.targets),
    agentFileRoots: config.agentFileRoots,
  );
  return agentFileDrifts(inputs).isNotEmpty ||
      skillAndAgentFileDrifts(inputs).isNotEmpty;
}
