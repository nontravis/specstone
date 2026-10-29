import 'dart:io';

import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/setup_migration/legacy_plan.dart';
import 'package:specstone_core/src/setup_migration/project_root.dart';
import 'package:specstone_core/src/setup_migration/run_kind.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';

/// What one `specstone migrate` call runs with.
final class MigrateRequest {
  const new({
    required this.workingDirectory,
    required this.homeDirectory,
    required this.templates,
    required this.dryRun,
    required this.interactive,
    required this.readLine,
    required this.out,
    this.runGit = runRealGit,
  });

  /// The folder the project root is searched from.
  final Directory workingDirectory;

  /// The personal pack home, or null.
  final Directory? homeDirectory;

  /// Loads the carried packs.
  final TemplateResolver templates;

  /// Whether to print the plan and write nothing.
  final bool dryRun;

  /// Whether stdin and stdout are both terminals.
  final bool interactive;

  /// Reads one line of the Owner's answer, or null at the end of input.
  final String? Function() readLine;

  /// Where the plan and the result print.
  final StringSink out;

  /// Starts `git`; replaced in tests.
  final RunGit runGit;
}

/// Runs `specstone migrate` and returns its exit status.
///
/// Throws a `SpecstoneFault` for a refused run, before anything prints.
int runMigrate(MigrateRequest request) {
  final root = findMigrateRoot(request.workingDirectory);
  final kind = chooseRun(
    root,
    templates: request.templates,
    homeDirectory: request.homeDirectory,
  );
  switch (kind) {
    case RunKind.none:
      request.out.writeln('nothing to migrate');
      return 0;
    case RunKind.legacy:
      final plan = planLegacyRun(
        root,
        templates: request.templates,
        homeDirectory: request.homeDirectory,
      );
      if (!request.dryRun) throw StateError('applying a legacy run is M4-T13');
      request.out
        ..write(plan.toText())
        ..writeln('dry run: nothing written');
      return 0;
    case RunKind.resume:
      throw StateError('resuming a migration is M4-T14');
    case RunKind.upgrade:
      throw StateError('upgrading pack pins is M5-T18');
  }
}
