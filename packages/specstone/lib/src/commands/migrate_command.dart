import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Converts a legacy SDD tree, resumes an unfinished migration, or upgrades
/// the pack pins of a project.
class MigrateCommand extends SpecstoneCommand {
  new() {
    argParser.addFlag(
      'dry-run',
      negatable: false,
      help: 'Print the plan and write nothing.',
    );
  }

  @override
  String get name => 'migrate';

  @override
  String get description =>
      'Migrate a legacy SDD tree, or upgrade the pack pins of a project.';

  @override
  String get invocation => 'specstone migrate [--dry-run]';

  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.rest.isNotEmpty) {
      usageException('Expected no argument, got ${args.rest.length}.');
    }
    final runner = specstoneRunner;
    final console = runner.console;
    try {
      return runMigrate(
        MigrateRequest(
          workingDirectory: runner.workingDirectory,
          homeDirectory: runner.homeDirectory,
          templates: runner.templates,
          dryRun: args.flag('dry-run'),
          interactive: console.stdinIsTerminal && console.stdoutIsTerminal,
          readLine: console.readLine,
          out: runner.out,
        ),
      );
    } on SpecstoneFault catch (fault) {
      return fail(fault, asJson: false);
    }
  }
}
