import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/owner_confirmation.dart';
import 'package:specstone_core/src/document_writing/root_trust.dart';
import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/plan_hash.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/setup_migration/git_gate.dart';
import 'package:specstone_core/src/setup_migration/legacy_plan.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/project_root.dart';
import 'package:specstone_core/src/setup_migration/run_kind.dart';
import 'package:specstone_core/src/setup_migration/run_plan.dart';
import 'package:specstone_core/src/setup_migration/upgrade_plan.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';

/// Opens the `owner_terminal_required` message of an apply.
const _applyRefusal = 'migrate applies only';

/// What one `specstone migrate` call runs with.
final class MigrateRequest {
  const new({
    required this.workingDirectory,
    required this.homeDirectory,
    required this.templates,
    required this.dryRun,
    required this.confirmation,
    required this.readLine,
    required this.out,
    this.asJson = false,
    this.planHash,
    this.runGit = runMigrateGit,
    this.warn = warnOnStderr,
  });

  /// The folder the project root is searched from.
  final Directory workingDirectory;

  /// The personal pack home, or null.
  final Directory? homeDirectory;

  /// Loads the carried packs.
  final TemplateResolver templates;

  /// Whether to print the plan and write nothing.
  final bool dryRun;

  /// How the Owner confirms the apply: at the terminal's `y`, or `--yes`.
  final OwnerConfirmation confirmation;

  /// Reads one line of the Owner's answer, or null at the end of input.
  final String? Function() readLine;

  /// Where the plan and the result print.
  final StringSink out;

  /// Whether the plan prints as one JSON object on [out]; the prompt, the
  /// commit lines, and the closing line then go to [warn].
  final bool asJson;

  /// The hash on the `plan <hash>` line of the dry run the Owner saw; under
  /// `--yes` the run applies only a plan with this hash.
  final String? planHash;

  /// Starts `git`; replaced in tests.
  final RunGit runGit;

  /// Reports one warning line, such as an agent file the run leaves outside
  /// the project root; writes it to stderr unless replaced.
  final void Function(String line) warn;
}

/// Runs `specstone migrate` and returns its exit status.
///
/// A legacy or upgrade run, with or without `--dry-run`, checks trust and git
/// first, then prints the plan; bare `migrate` applies it on the Owner's `y`,
/// or under `--yes` with no prompt, after checking git again.
///
/// A pending journal is finished first: a `document_writing` journal is
/// replayed before the git checks, and a migrate journal is resumed with no
/// second `y`. A dry run replays nothing: it refuses a `document_writing`
/// journal the replay would refuse, and refuses `working_tree_dirty` while one
/// has a step left; a journal with none left goes on to the git checks.
///
/// Throws a `SpecstoneFault` for a run refused by the root, the git checks, or
/// the plan, before anything prints. The terminal refusal, the git checks
/// after the `y`, and the faults of applying (index, render) follow the
/// printed plan or the listed steps. A `git add` or `git commit` that fails,
/// or a git that cannot start past the git checks, throws `MigrateFault`
/// `git_failed`, and the journal stays.
int runMigrate(MigrateRequest request) =>
    _mappingGitFailures(() => _migrate(request));

/// Runs [run], mapping a git failure to the fault a migrate run raises.
///
/// A [GitCommandFailed], or a [ProcessException] from a git that cannot start
/// past the git checks, becomes `git_failed`; the checks map their own to
/// `git_work_tree_required`.
int _mappingGitFailures(int Function() run) {
  try {
    return run();
  } on GitCommandFailed catch (error) {
    throw _gitFailed('git ${error.verb}', error.line);
  } on ProcessException catch (error) {
    throw _gitFailed(
      ['git', ...error.arguments.take(1)].join(' '),
      'cannot start git: ${error.message}',
    );
  }
}

MigrateFault _gitFailed(String command, String line) => MigrateFault(
  MigrateFaultCode.gitFailed,
  '$command failed: $line; fix the cause, then run specstone migrate '
  '$ownerConfirmationWays, to finish the run',
);

int _migrate(MigrateRequest request) {
  final (:root, :linkFolder) = locateMigrateRoot(request.workingDirectory);
  final trust = _trustOf(root, linkFolder, request);
  requireSpecstoneFolder(root);
  if (!MoveJournal.pendingMigrate(root) && MoveJournal.pending(root)) {
    final target = _targetOf(root, request, trust)..requireTrusted();
    if (request.dryRun) {
      // Reads the journal and its cursor only, so a dry run refuses one that
      // does not parse as the replay does, and writes nothing.
      if (MoveJournal.remaining(target).isNotEmpty) {
        throw MigrateFault(
          MigrateFaultCode.workingTreeDirty,
          'the move journal (${MoveJournal.journalPath}) has steps left; run '
          'specstone migrate to finish the move, commit it, and plan again',
        );
      }
    } else {
      MoveJournal.replay(target);
    }
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
    case RunKind.upgrade:
      return _plannedRun(request, root, kind, linkFolder: linkFolder);
    case RunKind.resume:
      return _resume(request, root, trust);
  }
}

/// Runs the bare legacy migration of [root] from its git checks on.
///
/// Prints the plan, then applies it on the Owner's `y`; `init` enters here
/// when its root holds the legacy context doc (F6-D15). [linkFolder] is the
/// canonical folder whose `docs` link led to [root], or null. Maps git
/// failures as [runMigrate] does.
int runLegacyAt(
  Directory root,
  MigrateRequest request, {
  Directory? linkFolder,
}) => _mappingGitFailures(
  () => _plannedRun(request, root, RunKind.legacy, linkFolder: linkFolder),
);

/// Returns the trust of [root], reached through the `docs` link of
/// [linkFolder], or found itself when that is null.
RootTrust _trustOf(
  Directory root,
  Directory? linkFolder,
  MigrateRequest request,
) => RootTrust.at(
  folder: linkFolder ?? root,
  root: root,
  homeDirectory: request.homeDirectory,
);

/// Prints the plan of a legacy or upgrade run after the preflight, and applies
/// it on the Owner's `y`, or under `--yes` with no prompt.
///
/// After the `y` or the `--plan` check the run checks the clean tree again and
/// plans again, since the Owner may read the plan for minutes: a dirty tree, or
/// a new plan that hashes differently from the one shown (an input edited,
/// deleted, or added), refuses `working_tree_dirty` with nothing written. A
/// commit that leaves every input as it was does not refuse; the run then
/// reads HEAD as each commit step's `base`. A legacy plan reads [linkFolder].
int _plannedRun(
  MigrateRequest request,
  Directory root,
  RunKind kind, {
  required Directory? linkFolder,
}) {
  final trust = _trustOf(root, linkFolder, request);
  _preflight(request, root, trust, checksCleanTree: true);
  final plan = _planOf(request, root, kind, linkFolder);
  _nameSkipped(request, plan);
  final planText = plan.toText();
  if (request.dryRun) {
    _printDryRun(request, planText, plan.inputs, plan.lists);
    return 0;
  }
  _printPlan(request, planText, plan.lists);
  request.confirmation.refuseIfMissing(_applyRefusal);
  if (request.confirmation.prompts) {
    MoveJournal.requireHomeFolder(request.homeDirectory, root);
    _say(request, 'apply? [y/N] ', endsLine: false);
    final answer = request.readLine()?.trim();
    if (answer != 'y') return 0;
  } else {
    _requireSeenPlan(request, planText, plan.inputs);
  }
  requireCleanWorkTree(root, request.runGit);
  final applied = _replanMatching(request, root, kind, linkFolder, plan);
  final base = headSha(root, request.runGit);
  final steps = applied.journalSteps(base: base, projectRoot: root);
  MoveJournal(steps).run(
    _targetOf(root, request, trust, agentFiles: applied.agentFiles?.writeSet),
  );
  _printCommits(request, root, steps.whereType<CommitStep>().toList());
  _printClosingLine(request, root);
  return 0;
}

/// Plans again and returns the new plan when it hashes as [shown] does.
///
/// Throws [MigrateFault] `working_tree_dirty` otherwise, naming the first
/// input that differs, or the plan alone when only its text does. A new plan
/// that cannot read an input, a [FileSystemException], [TemplateFault], or
/// [RenderFault], refuses the same way, naming the path or file the failure
/// gives, else the first input whose read failed, else the plan alone: an
/// unreadable doc's [RenderFault] carries no file. A [MigrateFault] from the
/// planner passes unchanged, with its own code as the first plan would: "A new
/// plan that E06 refuses refuses as E06 says".
RunPlan _replanMatching(
  MigrateRequest request,
  Directory root,
  RunKind kind,
  Directory? linkFolder,
  RunPlan shown,
) {
  final recorder = PlanInputs(root);
  final RunPlan fresh;
  try {
    fresh = recorder.collect(() => _planOf(request, root, kind, linkFolder));
  } on FileSystemException catch (error) {
    throw _inputChanged(_fromRoot(root, error.path));
  } on TemplateFault catch (fault) {
    throw _inputChanged(fault.file ?? recorder.firstUnreadable);
  } on RenderFault catch (fault) {
    throw _inputChanged(fault.file ?? recorder.firstUnreadable);
  }
  final freshHash = planHashOf(fresh.toText(), fresh.inputs);
  if (freshHash == planHashOf(shown.toText(), shown.inputs)) return fresh;
  throw _inputChanged(shown.inputs.firstDifferenceFrom(fresh.inputs));
}

/// Returns the refusal for a plan whose [input] changed while it was shown,
/// or the plan itself when [input] is null or empty.
MigrateFault _inputChanged(String? input) {
  final changed = input == null || input.isEmpty
      ? 'the plan'
      : '$input, an input of the plan,';
  return MigrateFault(
    MigrateFaultCode.workingTreeDirty,
    '$changed changed while the plan was shown; run specstone migrate again '
    'to plan from it',
  );
}

/// Returns the `/`-separated path of [absolute] from [root], [absolute] itself
/// when it lies outside, or null when it is null.
String? _fromRoot(Directory root, String? absolute) =>
    absolute == null ? null : pathFromRoots(absolute, [root.absolute.path]);

/// Refuses, in order and before any plan, roots that wait for the Owner's
/// trust record, a [root] outside a git work tree, and, when [checksCleanTree],
/// a dirty work tree.
///
/// The dry run and the apply of a legacy run, an upgrade, and a resume share
/// it; a resume leaves the clean-tree check off, since its stopped run left
/// the tree dirty.
void _preflight(
  MigrateRequest request,
  Directory root,
  RootTrust trust, {
  required bool checksCleanTree,
}) {
  trust.requireTrusted(MoveJournal.journalPath);
  requireGitWorkTree(root, request.runGit);
  if (checksCleanTree) requireCleanWorkTree(root, request.runGit);
}

/// Names on [request]'s warnings each agent file [plan] leaves because its
/// real path lies outside the project root (R99), one line per file.
void _nameSkipped(MigrateRequest request, RunPlan plan) {
  plan.agentFiles?.skipped.forEach(request.warn);
}

RunPlan _planOf(
  MigrateRequest request,
  Directory root,
  RunKind kind,
  Directory? linkFolder,
) => kind == RunKind.upgrade
    ? planUpgradeRun(
        root,
        templates: request.templates,
        homeDirectory: request.homeDirectory,
      )
    : planLegacyRun(
        root,
        templates: request.templates,
        homeDirectory: request.homeDirectory,
        linkFolder: linkFolder,
      );

/// Finishes the migrate journal a stopped run left, with no second `y`: the
/// Owner's first `y` approved its steps.
///
/// A resume, bare or dry, checks trust, the git work tree, and the version
/// first, as its commits need them; the stopped run leaves the tree dirty, so
/// it is not checked.
int _resume(MigrateRequest request, Directory root, RootTrust trust) {
  _preflight(request, root, trust, checksCleanTree: false);
  final target = _targetOf(root, request, trust);
  final inputs = PlanInputs(root);
  final planText = inputs.collect(() {
    final listing = StringBuffer()
      ..writeln('pending migration: ${root.path} (${MoveJournal.journalPath})')
      ..writeln('remaining steps:');
    for (final step in MoveJournal.remaining(target)) {
      listing.writeln('  ${step.describe()}');
    }
    return listing.toString();
  });
  if (request.dryRun) {
    _printDryRun(request, planText, inputs, const PlanLists());
    return 0;
  }
  _printPlan(request, planText, const PlanLists());
  request.confirmation.refuseIfMissing(_applyRefusal);
  if (!request.confirmation.prompts) {
    _requireSeenPlan(request, planText, inputs);
  }
  final commits = MoveJournal.read(target)!.whereType<CommitStep>().toList();
  MoveJournal.replay(target);
  _printCommits(request, root, commits);
  _printClosingLine(request, root);
  return 0;
}

/// Prints the plan: [planText], or under `--json` one object holding it and
/// the path [lists] the count lines leave out.
void _printPlan(MigrateRequest request, String planText, PlanLists lists) {
  if (!request.asJson) {
    request.out.write(planText);
    return;
  }
  request.out.writeln(
    const JsonEncoder.withIndent('  ')
        .convert({'plan': planText, ...lists.toJson()}),
  );
}

/// Prints the plan as [_printPlan] does, closed by its `plan <hash>` line
/// over [inputs]; as text, the dry-run closing line follows.
void _printDryRun(
  MigrateRequest request,
  String planText,
  PlanInputs inputs,
  PlanLists lists,
) {
  final hashLine = 'plan ${planHashOf(planText, inputs)}\n';
  _printPlan(request, '$planText$hashLine', lists);
  if (!request.asJson) request.out.writeln('dry run: nothing written');
}

/// Says [text] after the plan: on [MigrateRequest.out], or under `--json` on
/// its warnings, so the object stays alone on `out`.
void _say(MigrateRequest request, String text, {bool endsLine = true}) {
  if (request.asJson) {
    request.warn(text.trimRight());
  } else if (endsLine) {
    request.out.writeln(text);
  } else {
    request.out.write(text);
  }
}

/// Says how many findings a whole-project `check` reports at [root] after the
/// last commit.
void _printClosingLine(MigrateRequest request, Directory root) {
  final findings = ReadSession.run(
    (session) => runCheck(session).findings.length,
    templates: request.templates,
    workingDirectory: root,
    homeDirectory: request.homeDirectory,
  );
  _say(
    request,
    'check: $findings findings left; run specstone check to see them',
  );
}

/// Refuses a `--yes` run whose plan is not the one the Owner saw.
///
/// Throws [MigrateFault] `plan_mismatch` when [planText] and [inputs] do not
/// hash to the request's plan hash, or the request carries none.
void _requireSeenPlan(
  MigrateRequest request,
  String planText,
  PlanInputs inputs,
) {
  if (request.planHash == planHashOf(planText, inputs)) return;
  throw MigrateFault(
    MigrateFaultCode.planMismatch,
    'the plan is not the one the Owner saw in the dry run; run specstone '
    'migrate --dry-run again, show it, and ask for a new ok',
  );
}

/// Returns the journal target of the migrate run at [root].
///
/// A run passes its plan's `AgentWritePlan.writeSet` as [agentFiles], which
/// the journal record keeps, so a replay admits them (R49).
JournalTarget _targetOf(
  Directory root,
  MigrateRequest request,
  RootTrust trust, {
  Set<String>? agentFiles,
}) => JournalTarget(
  projectRoot: root,
  docsRoot: Directory.fromUri(root.uri.resolve(docsFolderName)),
  homeDirectory: request.homeDirectory,
  trust: trust,
  agentFiles: agentFiles ?? const {},
  runGit: request.runGit,
  warn: request.warn,
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
    _say(request, 'commit ${firstNumber + index} $sha: $subject');
  }
}
