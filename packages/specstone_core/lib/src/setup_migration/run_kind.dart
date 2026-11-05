import 'dart:io';

import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/format_run.dart';
import 'package:specstone_core/src/setup_migration/project_root.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';

/// What a `specstone migrate` run does at a project root.
enum RunKind {
  /// An unfinished migration journal is replayed.
  resume,

  /// A legacy SDD tree is converted.
  legacy,

  /// At least one pin is older than its available pack version, or every pin
  /// is equal and a typed doc is off the layout `format` writes.
  upgrade,

  /// Every pin equals its available pack version and every typed doc is laid
  /// out.
  none,
}

/// Chooses the run for the project at [root].
///
/// [RunKind.resume] when a migrate journal is pending; else [RunKind.legacy]
/// when [legacyContextPath] exists; else the pins are compared, in code point
/// order, with the available pack versions: the first newer pin throws
/// `pack_pin_newer`, any older pin gives [RunKind.upgrade]. With every pin
/// equal, a doc that `format --check` would rewrite gives [RunKind.upgrade],
/// otherwise [RunKind.none]. [homeDirectory] is the personal pack home, or
/// null.
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
  return _hasDocOffLayout(root, templates, homeDirectory)
      ? RunKind.upgrade
      : RunKind.none;
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
