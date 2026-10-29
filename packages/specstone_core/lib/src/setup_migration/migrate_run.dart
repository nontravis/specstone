import 'dart:io';

import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/setup_migration/git_gate.dart';
import 'package:specstone_core/src/setup_migration/legacy_plan.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/project_root.dart';
import 'package:specstone_core/src/setup_migration/run_kind.dart';
import 'package:specstone_core/src/setup_migration/upgrade_plan.dart';
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
/// A bare legacy or upgrade run checks git first, prints the plan, and applies
/// it only on the Owner's `y`.
///
/// A pending journal is finished first: an F-02 journal is replayed before the
/// git checks, and a migrate journal is resumed with no second `y`.
///
/// Throws a `SpecstoneFault` for a run refused by the root, the git checks, or
/// the plan, before anything prints. The terminal refusal and the faults of
/// applying (index, render) follow the printed plan or the listed steps. A
/// `git add` or `git commit` that fails throws `MigrateFault` `git_failed`,
/// and the journal stays.
int runMigrate(MigrateRequest request) {
  try {
    return _migrate(request);
  } on GitCommandFailed catch (error) {
    throw MigrateFault(
      MigrateFaultCode.gitFailed,
      'git ${error.verb} failed: ${error.line}; fix the cause, then run '
      'specstone migrate at an interactive terminal to finish the run',
    );
  } on ProcessException {
    throw workTreeRequiredFault();
  }
}

int _migrate(MigrateRequest request) {
  final root = findMigrateRoot(request.workingDirectory);
  if (!request.dryRun &&
      !MoveJournal.pendingMigrate(root) &&
      MoveJournal.pending(root)) {
    MoveJournal.replay(_targetOf(root, request));
    requireGitWorkTree(root, request.runGit);
    requireCleanWorkTree(root, request.runGit);
  }
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
      return runLegacyAt(root, request);
    case RunKind.upgrade:
      return _plannedRun(request, root, kind);
    case RunKind.resume:
      return _resume(request, root);
  }
}

/// Runs the bare legacy migration of [root] from its git checks on.
///
/// Prints the plan, then applies it on the Owner's `y`; `init` enters here
/// when its root holds the legacy context doc (F6-D15).
int runLegacyAt(Directory root, MigrateRequest request) =>
    _plannedRun(request, root, RunKind.legacy);

/// Prints the plan of a legacy or upgrade run, and applies it on the Owner's
/// `y`.
int _plannedRun(MigrateRequest request, Directory root, RunKind kind) {
  if (!request.dryRun) {
    requireGitWorkTree(root, request.runGit);
    requireCleanWorkTree(root, request.runGit);
  }
  final plan = kind == RunKind.upgrade
      ? planUpgradeRun(
          root,
          templates: request.templates,
          homeDirectory: request.homeDirectory,
        )
      : planLegacyRun(
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
  final steps = plan.journalSteps(base: base);
  MoveJournal(steps).run(_targetOf(root, request));
  _printCommits(request, root, steps.whereType<CommitStep>().toList());
  final closingLine = plan.closingLine;
  if (closingLine != null) request.out.writeln(closingLine);
  return 0;
}

/// Finishes the migrate journal a stopped run left, with no second `y`: the
/// Owner's first `y` approved its steps.
int _resume(MigrateRequest request, Directory root) {
  final target = _targetOf(root, request);
  final out = request.out
    ..writeln('pending migration: ${root.path} (${MoveJournal.journalPath})')
    ..writeln('remaining steps:');
  for (final step in MoveJournal.remaining(target)) {
    out.writeln('  ${step.describe()}');
  }
  if (request.dryRun) {
    out.writeln('dry run: nothing written');
    return 0;
  }
  if (!request.interactive) {
    throw WriteFault(
      WriteFaultCode.ownerTerminalRequired,
      'migrate applies only at an interactive terminal; ask the Owner to '
      'run specstone migrate',
    );
  }
  final commits = MoveJournal.read(root)!.whereType<CommitStep>().toList();
  MoveJournal.replay(target);
  _printCommits(request, root, commits);
  if (commits.last.message == legacyCommit2Message) {
    out.writeln(legacyClosingLine);
  }
  return 0;
}

JournalTarget _targetOf(Directory root, MigrateRequest request) =>
    JournalTarget(
      projectRoot: root,
      docsRoot: Directory.fromUri(root.uri.resolve('docs')),
      runGit: request.runGit,
    );

/// Prints a `commit <n> <sha>: <subject>` line per commit of the [steps] since
/// the first one's base, where `n` is the step's place in a two-commit run.
///
/// A commit whose message holds no step's message, such as the Owner's own
/// between two runs, is not listed.
void _printCommits(
  MigrateRequest request,
  Directory root,
  List<CommitStep> steps,
) {
  final firstNumber = 3 - steps.length;
  final commits = commitsSince(root, steps.first.base, request.runGit);
  for (final (:sha, :subject, :message) in commits) {
    final index = steps.indexWhere((step) => step.carriedBy(message));
    if (index < 0) continue;
    request.out.writeln('commit ${firstNumber + index} $sha: $subject');
  }
}
