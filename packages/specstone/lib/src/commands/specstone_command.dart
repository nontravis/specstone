import 'package:args/command_runner.dart';
import 'package:specstone/src/command_runner.dart';

/// Base class of every Specstone command.
///
/// Sends usage to the runner's `out` sink; `Command.printUsage` writes to the
/// process stdout, which bypasses the injected sink. The cast means a
/// [SpecstoneCommand] runs only under a [SpecstoneCommandRunner], never under
/// another `CommandRunner`.
abstract class SpecstoneCommand extends Command<int> {
  @override
  void printUsage() => (runner! as SpecstoneCommandRunner).out.writeln(usage);
}
