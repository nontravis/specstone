import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Sets up a new project: the config and the singular docs as drafts.
class InitCommand extends SpecstoneCommand {
  @override
  String get name => 'init';

  @override
  String get description =>
      'Set up a new project: the config and the singular docs as drafts.';

  @override
  String get invocation => 'specstone init';

  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.rest.isNotEmpty) {
      usageException('Expected no argument, got ${args.rest.length}.');
    }
    final runner = specstoneRunner;
    try {
      return await runInit(
        InitRequest(
          workingDirectory: runner.workingDirectory,
          homeDirectory: runner.homeDirectory,
          templates: runner.templates,
          out: runner.out,
        ),
      );
    } on SpecstoneFault catch (fault) {
      return fail(fault, asJson: false);
    }
  }
}
