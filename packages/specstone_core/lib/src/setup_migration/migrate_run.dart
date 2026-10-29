import 'dart:io';

import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/setup_migration/git_gate.dart';
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
/// Throws a `SpecstoneFault` for a refused run, before anything prints, except
/// `owner_terminal_required`, which follows the printed plan. A bare legacy run
/// checks git first, prints the plan, and applies it only on the Owner's `y`.
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
      if (!request.dryRun) {
        requireGitWorkTree(root, request.runGit);
        requireCleanWorkTree(root, request.runGit);
      }
      final plan = planLegacyRun(
        root,
        templates: request.templates,
        homeDirectory: request.homeDirectory,
      );
      if (request.dryRun) {
        request.out
          ..write(plan.toText())
          ..writeln('dry run: nothing written');
        return 0;
      }
      request.out.write(plan.toText());
      if (!request.interactive) {
        throw WriteFault(
          WriteFaultCode.ownerTerminalRequired,
          'migrate applies only at an interactive terminal; ask the Owner to '
          'run specstone migrate',
        );
      }
      request.out.write('apply? [y/N] ');
      final answer = request.readLine()?.trim();
      if (answer != 'y') return 0;
      final base = headSha(root, request.runGit);
      MoveJournal(plan.journalSteps(base: base)).run(
        JournalTarget(
          projectRoot: root,
          docsRoot: Directory.fromUri(root.uri.resolve('docs')),
          runGit: request.runGit,
        ),
      );
      var n = plan.moves.isEmpty ? 2 : 1;
      for (final (:sha, :subject) in commitsSince(root, base, request.runGit)) {
        request.out.writeln('commit $n $sha: $subject');
        n++;
      }
      final closingLine = plan.closingLine;
      if (closingLine != null) request.out.writeln(closingLine);
      return 0;
    case RunKind.resume:
      throw StateError('resuming a migration is M4-T14');
    case RunKind.upgrade:
      throw StateError('upgrading pack pins is M5-T18');
  }
}
