import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Prints the docs a work mode needs for one target, within a token budget.
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
        'no-project',
        negatable: false,
        help: 'Leave out the docs that join through `bundle:` lists.',
      )
      ..addFlag('json', negatable: false, help: 'Print JSON instead of text.');
  }

  @override
  String get name => 'context';

  @override
  String get description => 'Print the docs a work mode needs for a target.';

  @override
  String get invocation =>
      'specstone context [<target> | --code <path>] --for <mode> [--budget N] '
      '[--no-project] [--json]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final asJson = args.flag('json');
    final rest = args.rest;
    final code = args.option('code');
    if (code != null && rest.isNotEmpty) {
      return fail(
        IndexFault(
          IndexFaultCode.argumentConflict,
          'give a target or --code, not both',
        ),
        asJson: asJson,
      );
    }
    if (rest.length > 1) {
      usageException('Expected one target, got ${rest.length}.');
    }
    final BundleMode mode;
    final int? budget;
    try {
      if (rest.isEmpty && code == null) {
        throw missingArgument(
          'context',
          'a target or --code',
          'specstone context login --for implement',
        );
      }
      mode = BundleMode.parse(args.option('for'));
      budget = parsePositiveOption('--budget', args.option('budget'));
    } on IndexFault catch (fault) {
      return fail(fault, asJson: asJson);
    }
    final noProject = args.flag('no-project');
    if (code != null) {
      return runRead((session) {
        final codePath = resolveCodePath(
          code,
          workingDirectory: specstoneRunner.workingDirectory,
          projectRoot: session.project.projectRoot,
        );
        return answerContext(
          session.index,
          pickCodeBundle(session.index, codePath, mode, noProject: noProject),
          label: codePath.path,
          byCode: true,
          budget: budget,
        );
      }, asJson: asJson);
    }
    final target = rest.single;
    return runRead(
      (session) => answerContext(
        session.index,
        pickBundle(session.index, target, mode, noProject: noProject),
        label: target,
        byCode: false,
        budget: budget,
      ),
      asJson: asJson,
    );
  }
}
