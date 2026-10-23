import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';

/// Base class of every Specstone command.
///
/// Sends usage to the runner's `out` sink; `Command.printUsage` writes to the
/// process stdout, which bypasses the injected sink. The cast means a
/// [SpecstoneCommand] runs only under a [SpecstoneCommandRunner], never under
/// another `CommandRunner`.
abstract class SpecstoneCommand extends Command<int> {
  /// Encoder for every JSON object a command prints, two-space indented.
  static const JsonEncoder pretty = JsonEncoder.withIndent('  ');

  SpecstoneCommandRunner get _runner => runner! as SpecstoneCommandRunner;

  @override
  void printUsage() => _runner.out.writeln(usage);

  /// Writes [fault] to `err` and returns its exit status.
  ///
  /// Prints the JSON envelope when [asJson], else the text form.
  int fail(SpecstoneFault fault, {required bool asJson}) {
    _runner.err.writeln(
      asJson ? pretty.convert(fault.toJson()) : fault.toText(),
    );
    return fault.exitStatus;
  }

  /// Writes each of [warnings] to `err` as `⚠️ WARNING: <warning>`.
  void warn(Iterable<String> warnings) {
    for (final warning in warnings) {
      _runner.err.writeln('⚠️ WARNING: $warning');
    }
  }
}
