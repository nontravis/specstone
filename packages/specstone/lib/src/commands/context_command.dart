import 'dart:io';

import 'package:args/args.dart';
import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Returns [args] with each bare `--out` of a call whose command [parser]
/// declares `out` written as a hidden flag, since `package:args` gives an
/// option no optional value.
///
/// `--out` is bare when it is the last argument before any `--`, or the next
/// one starts with `-`; any other next argument, `""` included, is its path.
List<String> withBareOut(Iterable<String> args, ArgParser parser) {
  final list = args.toList();
  final command = list.indexWhere((arg) => !arg.startsWith('-'));
  if (command < 0 ||
      parser.commands[list[command]]?.options.containsKey('out') != true) {
    return list;
  }
  final end = list.indexOf('--');
  final limit = end < 0 ? list.length : end;
  bool isBare(int i) => i + 1 >= limit || list[i + 1].startsWith('-');
  return [
    for (final (i, arg) in list.indexed)
      if (arg == '--out' && i > command && i < limit && isBare(i))
        '--$bareOutFlag'
      else
        arg,
  ];
}

/// Prints the docs a work mode needs for one or more targets, within a token
/// budget, or writes them to a file and prints its index.
class ContextCommand extends SpecstoneCommand {
  new() {
    argParser
      ..addOption(
        'code',
        help:
            'A file or folder of the project to bundle the docs of, '
            'in place of a target.',
      )
      ..addOption(
        'for',
        help:
            'The work the docs are picked for: query, implement, design, '
            'sync, or review.',
      )
      ..addOption(
        'budget',
        help: 'Print no doc text when the bundle exceeds this many tokens.',
      )
      ..addFlag(
        'summary',
        negatable: false,
        help: 'With a feature and --for design, print every story in summary.',
      )
      ..addFlag(
        'no-project',
        negatable: false,
        help: 'Leave out the docs that join through `bundle:` lists.',
      )
      ..addFlag(
        'groups',
        negatable: false,
        help:
            'With --out and --for implement or design, split the targets into '
            'work groups and write one file pair per group.',
      )
      ..addFlag('json', negatable: false, help: 'Print JSON instead of text.');
    addOutOption();
    addTargetOption();
  }

  @override
  bool get writesOwnOut => true;

  @override
  String get name => 'context';

  @override
  String get description => 'Print the docs a work mode needs for a target.';

  @override
  String get invocation =>
      'specstone context [<target> ... | --code <path>] --for <mode> '
      '[--budget N | --out [<path>]] [--summary] [--no-project] '
      '[--target <name>] [--groups] [--json]';

  /// Runs the argument checks in the order the refusals rank: each
  /// `argument_invalid` check, then `argument_conflict`, then
  /// `argument_missing`; the first failed check alone is thrown. A `--for sync`
  /// target that is no top-level feature needs the index, so it ranks last,
  /// with target resolution. A `--for review` call refuses the inputs it never
  /// takes, then names a missing `--out` or target, before it opens the index.
  @override
  Future<int> run() async {
    final args = argResults!;
    final asJson = args.flag('json');
    final rest = args.rest;
    final summary = args.flag('summary');
    final groups = args.flag('groups');
    final code = args.option('code');
    final forWord = args.option('for');
    final writesFile = writesOut(args);
    final BundleMode mode;
    final int? budget;
    final String? out;
    try {
      // The first mode check only judges the value; a missing one comes last.
      if (rest.length > 1) {
        _refuseSeveralTargets(rest.length, forWord: forWord, summary: summary);
      }
      final named = forWord == null ? null : BundleMode.parse(forWord);
      final isSync = named == BundleMode.sync;
      final isReview = named == BundleMode.review;
      budget = parsePositiveOption('--budget', args.option('budget'));
      out = outPathOf(args);
      if (isSync && out != null) {
        throw IndexFault(
          IndexFaultCode.argumentInvalid,
          '--for sync writes its files by name; give --out bare, not $out',
        );
      }
      // An empty shell variable must not bundle the whole project.
      if (code != null && code.isEmpty) {
        throw IndexFault(
          IndexFaultCode.argumentInvalid,
          '--code takes a file or folder, not ""',
        );
      }
      if (isReview) _refuseReviewConflicts(args);
      if (code != null && rest.isNotEmpty) {
        throw IndexFault(
          IndexFaultCode.argumentConflict,
          'give a target or --code, not both',
        );
      }
      if (writesFile && args.option('budget') != null) {
        throw IndexFault(
          IndexFaultCode.argumentConflict,
          'give --out or --budget, not both',
        );
      }
      if (summary && forWord != BundleMode.design.wire) {
        throw IndexFault(
          IndexFaultCode.argumentConflict,
          '--summary works only with --for design',
        );
      }
      if (summary && code != null) {
        throw IndexFault(
          IndexFaultCode.argumentConflict,
          'give --summary with a target, not --code',
        );
      }
      if (groups) _refuseGroupsConflicts(args, named);
      if (isSync) _refuseSyncArguments(args, writesFile: writesFile);
      if (isReview) _refuseMissingReviewArguments(args, writesFile: writesFile);
      if (rest.isEmpty && code == null && !isSync) {
        throw missingArgument(
          'context',
          'a target or --code',
          'specstone context login --for implement',
        );
      }
      if (groups && !writesFile) {
        throw missingArgument(
          'context',
          '--out',
          'specstone context login/email_login login/reset_password '
              '--for implement --out --groups',
        );
      }
      mode = BundleMode.parse(forWord);
    } on IndexFault catch (fault) {
      return fail(fault, asJson: asJson);
    }
    if (mode == BundleMode.sync) return _runSync(args, asJson: asJson);
    if (mode == BundleMode.review) {
      return _runReview(args, asJson: asJson, out: out);
    }
    final noProject = args.flag('no-project');
    final splits = writesFile && mode != BundleMode.query;
    final workingDirectory = specstoneRunner.workingDirectory;

    /// Returns the bare `--out` file; a `--code` path is named from the
    /// project root, so every folder names one file for it.
    File bareFile(DocsProject project) {
      final name = bundleFileName(
        targets: code == null ? rest : const [],
        codePath: code == null
            ? null
            : project.displayPath(File(absoluteFrom(workingDirectory, code))),
        mode: mode,
        summary: summary,
        noProject: noProject,
        codeTarget: targetOf(args),
      );
      return bareBundleFile(project.projectRoot, name);
    }

    ReadAnswer answered(ReadSession session, ContextAnswer answer) {
      if (!writesFile) return answer;
      return answerBundleFile(
        answer,
        out == null
            ? bareFile(session.project)
            : File(absoluteFrom(workingDirectory, out)),
        project: session.project,
        isBare: out == null,
      );
    }

    if (code != null) {
      return runRead((session) {
        final given = targetOf(args);
        session.index.checkCodeTarget(given);
        final codePath = resolveCodePath(
          code,
          workingDirectory: specstoneRunner.workingDirectory,
          targets: session.project.targets,
          codeRootOf: session.project.codeRootOf,
          projectRoot: session.project.projectRoot,
          reachedFromProjectRoot: (projectPath) =>
              projectRootMatch(session.index, projectPath).isNotEmpty,
        );
        if (given != null && given != codePath.target.name) {
          throw IndexFault(
            IndexFaultCode.argumentConflict,
            'the code path $code lies in the code target '
            '${codePath.target.name}, not $given',
          );
        }
        final answer = answerCodeContext(
          session.index,
          pickCodeBundle(
            session.index,
            codePath,
            mode,
            noProject: noProject,
            importedPaths: importedDocPaths(
              session.project,
              session.index,
              environment: specstoneRunner.environment,
            ),
          ),
          label: codePath.label,
          budget: budget,
          split: splits,
        );
        return answered(session, answer);
      }, asJson: asJson);
    }
    return runRead((session) {
      final codeTarget = targetOf(args);
      final importedPaths = importedDocPaths(
        session.project,
        session.index,
        environment: specstoneRunner.environment,
      );
      if (groups) {
        final pick = pickWorkGroups(
          session.index,
          rest,
          mode,
          noProject: noProject,
          codeTarget: codeTarget,
          importedPaths: importedPaths,
        );
        if (pick.groups.length == 1) return answered(session, pick.answer);
        return answerGroupFiles(
          session.index,
          pick,
          project: session.project,
          outPath: out == null ? null : absoluteFrom(workingDirectory, out),
        );
      }
      final answer = answerContext(
        session.index,
        pickBundle(
          session.index,
          rest,
          mode,
          noProject: noProject,
          summary: summary,
          codeTarget: codeTarget,
          importedPaths: importedPaths,
        ),
        targets: rest,
        budget: budget,
        split: splits,
      );
      return answered(session, answer);
    }, asJson: asJson);
  }

  /// Lists the sync groups of the changed code and writes one file per group;
  /// the work list comes from a check run in the same session.
  Future<int> _runSync(ArgResults args, {required bool asJson}) async {
    final runner = specstoneRunner;
    var sessionWarnings = const <String>[];
    final ReadAnswer answer;
    try {
      answer = await ReadSession.runAsync(
        (session) {
          sessionWarnings = session.warnings;
          return answerSyncWork(
            session,
            feature: args.rest.firstOrNull,
            codeTarget: targetOf(args),
          );
        },
        templates: runner.templates,
        workingDirectory: runner.workingDirectory,
        homeDirectory: runner.homeDirectory,
        busyTimeout: runner.busyTimeout,
      );
    } on SpecstoneFault catch (fault) {
      return fail(fault, asJson: asJson, warnings: sessionWarnings);
    }
    return printAnswer(answer, sessionWarnings, asJson: asJson);
  }

  /// Writes the read-first and refs files of the drafts [args] name, and
  /// prints their index; [out] is the `--out` path, null when bare.
  ///
  /// The dry-run views come first, so a root awaiting the trust record or a
  /// target no doc carries refuses before any file is written.
  Future<int> _runReview(
    ArgResults args, {
    required bool asJson,
    required String? out,
  }) {
    final targets = args.rest;
    final noProject = args.flag('no-project');
    final codeTarget = targetOf(args);
    return runRead((session) {
      final parts = pickReviewParts(
        session.index,
        targets,
        draftViewsOf(session, names: targets, codeTarget: codeTarget),
        codeTarget: codeTarget,
      );
      final file = out == null
          ? bareBundleFile(
              session.project.projectRoot,
              bundleFileName(
                targets: targets,
                mode: BundleMode.review,
                summary: false,
                noProject: noProject,
                codeTarget: codeTarget,
              ),
            )
          : File(absoluteFrom(specstoneRunner.workingDirectory, out));
      return answerReviewFiles(
        session.index,
        parts,
        file,
        project: session.project,
        isBare: out == null,
        noProject: noProject,
        codeTarget: codeTarget,
        importedPaths: importedDocPaths(
          session.project,
          session.index,
          environment: specstoneRunner.environment,
        ),
      );
    }, asJson: asJson);
  }

  /// Throws `argument_conflict` for the first of `--code`, `--summary`, and
  /// `--budget` that `--for review` never takes.
  void _refuseReviewConflicts(ArgResults args) {
    final given = [
      if (args.option('code') != null) '--code',
      if (args.flag('summary')) '--summary',
      if (args.option('budget') != null) '--budget',
    ];
    if (given.isEmpty) return;
    throw IndexFault(
      IndexFaultCode.argumentConflict,
      '--for review takes no ${given.first}',
    );
  }

  /// Throws `argument_missing` for the `--out` `--for review` requires, then
  /// for the target it requires.
  void _refuseMissingReviewArguments(
    ArgResults args, {
    required bool writesFile,
  }) {
    const example = 'specstone context login/email_login --for review --out';
    if (!writesFile) throw missingArgument('context', '--out', example);
    if (args.rest.isEmpty) {
      throw missingArgument('context', 'a target', example);
    }
  }

  /// Throws `argument_conflict` for the [mode] `--groups` never takes, then for
  /// the first of `--code`, `--summary`, and `--budget`.
  void _refuseGroupsConflicts(ArgResults args, BundleMode? mode) {
    if (mode != null &&
        mode != BundleMode.implement &&
        mode != BundleMode.design) {
      throw IndexFault(
        IndexFaultCode.argumentConflict,
        '--groups works only with --for implement or --for design',
      );
    }
    final given = [
      if (args.option('code') != null) '--code',
      if (args.flag('summary')) '--summary',
      if (args.option('budget') != null) '--budget',
    ];
    if (given.isEmpty) return;
    throw IndexFault(
      IndexFaultCode.argumentConflict,
      '--groups takes no ${given.first}',
    );
  }

  /// Throws `argument_conflict` for what `--for sync` never takes, then
  /// `argument_missing` for the bare `--out` it requires.
  void _refuseSyncArguments(ArgResults args, {required bool writesFile}) {
    final given = [
      if (args.flag('no-project')) '--no-project',
      if (args.option('code') != null) '--code',
      if (args.option('budget') != null) '--budget',
    ];
    if (given.isNotEmpty) {
      throw IndexFault(
        IndexFaultCode.argumentConflict,
        '--for sync takes no ${given.first}',
      );
    }
    if (!writesFile) {
      throw missingArgument(
        'context',
        '--out',
        'specstone context --for sync --out',
      );
    }
  }

  /// Throws `argument_invalid` for [count] target arguments given with
  /// `--for query`, `--for sync`, or `--summary`, which take one; the `--for`
  /// words rank first.
  void _refuseSeveralTargets(
    int count, {
    required String? forWord,
    required bool summary,
  }) {
    final takesOne =
        forWord == BundleMode.query.wire || forWord == BundleMode.sync.wire;
    final option = takesOne ? '--for $forWord' : (summary ? '--summary' : null);
    if (option == null) return;
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      '$option takes one target; got $count',
    );
  }
}
