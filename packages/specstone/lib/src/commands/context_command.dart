import 'dart:io';

import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// The commands whose bare `--out` names its own file.
const _outCommands = {'context', 'check', 'guide', 'get'};

/// Returns [args] with each bare `--out` of a `context`, `check`, `guide`, or
/// `get` call written as a hidden flag, since `package:args` gives an option
/// no optional value.
///
/// `--out` is bare when it is the last argument before any `--`, or the next
/// one starts with `-`; any other next argument, `""` included, is its path.
List<String> withBareOut(Iterable<String> args) {
  final list = args.toList();
  final command = list.indexWhere((arg) => !arg.startsWith('-'));
  if (command < 0 || !_outCommands.contains(list[command])) return list;
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
        help: 'The work the docs are picked for: query, implement, or design.',
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
      ..addFlag('json', negatable: false, help: 'Print JSON instead of text.');
    addOutOption();
    addTargetOption();
  }

  @override
  String get name => 'context';

  @override
  String get description => 'Print the docs a work mode needs for a target.';

  @override
  String get invocation =>
      'specstone context [<target> ... | --code <path>] --for <mode> '
      '[--budget N | --out [<path>]] [--summary] [--no-project] '
      '[--target <name>] [--json]';

  /// Runs the argument checks in the order the refusals rank: each
  /// `argument_invalid` check, then `argument_conflict`, then
  /// `argument_missing`; the first failed check alone is thrown.
  @override
  Future<int> run() async {
    final args = argResults!;
    final asJson = args.flag('json');
    final rest = args.rest;
    final summary = args.flag('summary');
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
      if (forWord != null) BundleMode.parse(forWord);
      budget = parsePositiveOption('--budget', args.option('budget'));
      out = outPathOf(args);
      // An empty shell variable must not bundle the whole project.
      if (code != null && code.isEmpty) {
        throw IndexFault(
          IndexFaultCode.argumentInvalid,
          '--code takes a file or folder, not ""',
        );
      }
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
      if (rest.isEmpty && code == null) {
        throw missingArgument(
          'context',
          'a target or --code',
          'specstone context login --for implement',
        );
      }
      mode = BundleMode.parse(forWord);
    } on IndexFault catch (fault) {
      return fail(fault, asJson: asJson);
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
        final answer = answerContext(
          session.index,
          pickCodeBundle(session.index, codePath, mode, noProject: noProject),
          label: codePath.label,
          byCode: true,
          budget: budget,
          split: splits,
        );
        return answered(session, answer);
      }, asJson: asJson);
    }
    return runRead((session) {
      final answer = answerContext(
        session.index,
        pickBundle(
          session.index,
          rest,
          mode,
          noProject: noProject,
          summary: summary,
          codeTarget: targetOf(args),
        ),
        label: rest.join(' '),
        byCode: false,
        targets: rest,
        budget: budget,
        split: splits,
      );
      return answered(session, answer);
    }, asJson: asJson);
  }

  /// Throws `argument_invalid` for [count] target arguments given with
  /// `--for query` or `--summary`, which take one; `--for query` ranks first.
  void _refuseSeveralTargets(
    int count, {
    required String? forWord,
    required bool summary,
  }) {
    final option = forWord == BundleMode.query.wire
        ? '--for query'
        : (summary ? '--summary' : null);
    if (option == null) return;
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      '$option takes one target; got $count',
    );
  }
}
