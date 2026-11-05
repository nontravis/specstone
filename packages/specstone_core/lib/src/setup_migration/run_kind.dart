import 'dart:io';

import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/setup_migration/agent_targets.dart';
import 'package:specstone_core/src/setup_migration/project_root.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:specstone_core/src/version.dart';

/// What a `specstone migrate` run does at a project root.
enum RunKind {
  /// An unfinished migration journal is replayed.
  resume,

  /// A legacy SDD tree is converted.
  legacy,

  /// At least one pin is older than its available pack version, or an agent
  /// file drifts from what the CLI writes.
  upgrade,

  /// Every pin equals its available pack version and no agent file drifts.
  none,
}

/// Chooses the run for the project at [root].
///
/// [RunKind.resume] when a migrate journal is pending; else [RunKind.legacy]
/// when [legacyContextPath] exists; else the pins are compared, in code point
/// order, with the available pack versions: the first newer pin throws
/// `pack_pin_newer`, any older pin gives [RunKind.upgrade]. With every pin
/// equal, any agent file drift (`agentFileDrifts`, the predicate `check` uses,
/// a malformed marker included) gives [RunKind.upgrade], otherwise
/// [RunKind.none]. [homeDirectory] is the personal pack home, or null.
RunKind chooseRun(
  Directory root, {
  required TemplateResolver templates,
  required Directory? homeDirectory,
}) {
  if (MoveJournal.pendingMigrate(root)) return RunKind.resume;
  if (File.fromUri(root.uri.resolve(legacyContextPath)).existsSync()) {
    return RunKind.legacy;
  }
  final pins = ProjectConfig.read(root).pins;
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
  if (older) return RunKind.upgrade;
  return _hasAgentFileDrift(root, templates, homeDirectory)
      ? RunKind.upgrade
      : RunKind.none;
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
    codeRootFolders: codeRootFolders(
      projectRoot,
      codeRoot: config.codeRoot,
      codeEntries: codeEntriesOnDisk(projectRoot, set),
    ),
    agentFileRoots: config.agentFileRoots,
  );
  return agentFileDrifts(inputs).isNotEmpty;
}
