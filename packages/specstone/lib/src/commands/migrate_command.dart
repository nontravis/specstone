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
      )
      ..addMultiOption(
        'add',
        valueHelp: 'pack',
        help: 'Pin a shipped or personal pack the project does not pin yet.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print the plan as one JSON object.',
      );
  }

  @override
  String get name => 'migrate';

  @override
  String get description =>
      'Migrate a legacy SDD tree, or upgrade the pack pins of a project.';

  @override
  String get invocation =>
      'specstone migrate [--add <pack>]... '
      '[--dry-run | --yes --plan <hash>] [--json]';

  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.rest.isNotEmpty) {
      usageException('Expected no argument, got ${args.rest.length}.');
    }
    final dryRun = args.flag('dry-run');
    final yes = args.flag('yes');
    final planHash = args.option('plan');
    checkPlanFlags(
      yes: yes,
      planHash: planHash,
      planCommand: 'specstone migrate',
      dryRun: dryRun,
    );
    final added = args.multiOption('add');
    if (!added.every(isPackName)) {
      usageException('--add takes a pack name in kebab-case');
    }
    final runner = specstoneRunner;
    final console = runner.console;
    try {
      return await runMigrate(
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
          asJson: args.flag('json'),
          warn: runner.err.writeln,
          environment: runner.environment,
          planHash: planHash,
          addedPacks: added,
        ),
      );
    } on MigrateUsageError catch (error) {
      usageException(error.message);
    } on SpecstoneFault catch (fault) {
      return fail(fault, asJson: false);
    }
  }
}
