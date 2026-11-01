import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Converts a legacy SDD tree, resumes an unfinished migration, or upgrades
/// the pack pins of a project.
class MigrateCommand extends SpecstoneCommand {
  new() {
    argParser
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Print the plan and write nothing.',
      )
      ..addFlag(
        'yes',
        negatable: false,
        help:
            'Apply the plan without the terminal prompt; the agent runs it '
            "after the Owner's ok.",
      )
      ..addOption(
        'plan',
        valueHelp: 'hash',
        help:
            'With --yes: the plan line --dry-run printed; a changed plan '
            'refuses.',
      );
  }

  @override
  String get name => 'migrate';

  @override
  String get description =>
      'Migrate a legacy SDD tree, or upgrade the pack pins of a project.';

  @override
  String get invocation =>
      'specstone migrate [--dry-run | --yes --plan <hash>]';

  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.rest.isNotEmpty) {
      usageException('Expected no argument, got ${args.rest.length}.');
    }
    final dryRun = args.flag('dry-run');
    final yes = args.flag('yes');
    if (dryRun && yes) usageException('--yes cannot go with --dry-run.');
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
      return runMigrate(
        MigrateRequest(
          workingDirectory: runner.workingDirectory,
          homeDirectory: runner.homeDirectory,
          templates: runner.templates,
          dryRun: dryRun,
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
