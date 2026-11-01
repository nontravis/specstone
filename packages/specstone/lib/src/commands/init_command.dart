import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Sets up a new project: the config and the singular docs as drafts, or the
/// legacy migrate run on a legacy tree.
class InitCommand extends SpecstoneCommand {
  new() {
    argParser
      ..addFlag(
        'yes',
        negatable: false,
        help:
            'Apply the legacy migrate run without the terminal prompt; the '
            "agent runs it after the Owner's ok.",
      )
      ..addOption(
        'plan',
        valueHelp: 'hash',
        help:
            'With --yes: the plan line migrate --dry-run printed; a changed '
            'plan refuses.',
      );
  }

  @override
  String get name => 'init';

  @override
  String get description =>
      'Set up a new project: the config and the singular docs as drafts, or '
      'the legacy migrate run on a legacy tree.';

  @override
  String get invocation => 'specstone init [--yes --plan <hash>]';

  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.rest.isNotEmpty) {
      usageException('Expected no argument, got ${args.rest.length}.');
    }
    final yes = args.flag('yes');
    final planHash = args.option('plan');
    if (yes && planHash == null) {
      usageException(
        '--yes needs --plan <hash>, the plan line specstone migrate --dry-run '
        'prints.',
      );
    }
    if (!yes && planHash != null) {
      usageException('--plan goes only with --yes.');
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
            yes: yes,
            interactive: console.stdinIsTerminal && console.stdoutIsTerminal,
          ),
          readLine: console.readLine,
          out: runner.out,
          planHash: planHash,
        ),
      );
    } on SpecstoneFault catch (fault) {
      return fail(fault, asJson: false);
    }
  }
}
