import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Sets up a new project: the config and the singular docs as drafts, or the
/// legacy migrate run on a legacy tree.
class InitCommand extends SpecstoneCommand {
  new() {
    argParser.addFlag(
      'yes',
      negatable: false,
      help:
          'Apply the legacy migrate run without the terminal prompt; the '
          'Claude Code plugin asks the Owner first.',
    );
  }

  @override
  String get name => 'init';

  @override
  String get description =>
      'Set up a new project: the config and the singular docs as drafts, or '
      'the legacy migrate run on a legacy tree.';

  @override
  String get invocation => 'specstone init [--yes]';

  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.rest.isNotEmpty) {
      usageException('Expected no argument, got ${args.rest.length}.');
    }
    final runner = specstoneRunner;
    final console = runner.console;
    try {
      return runInit(
        InitRequest(
          workingDirectory: runner.workingDirectory,
          homeDirectory: runner.homeDirectory,
          templates: runner.templates,
          confirmation: OwnerConfirmation.of(
            yes: args.flag('yes'),
            interactive: console.stdinIsTerminal && console.stdoutIsTerminal,
          ),
          readLine: console.readLine,
          out: runner.out,
        ),
      );
    } on SpecstoneFault catch (fault) {
      return fail(fault, asJson: false);
    }
  }
}
