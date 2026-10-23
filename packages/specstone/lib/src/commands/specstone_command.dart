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

  /// The [SpecstoneCommandRunner] this command runs under.
  SpecstoneCommandRunner get specstoneRunner =>
      runner! as SpecstoneCommandRunner;

  @override
  void printUsage() => specstoneRunner.out.writeln(usage);

  /// Writes [fault] to `err` and returns its exit status.
  ///
  /// Prints the JSON envelope when [asJson], else the text form. [warnings]
  /// the run collected before it failed are not lost: the text form prints
  /// them first, and the envelope carries them as a top-level `warnings`
  /// array beside `error`, present only when [warnings] is not empty.
  int fail(
    SpecstoneFault fault, {
    required bool asJson,
    List<String> warnings = const [],
  }) {
    if (asJson) {
      specstoneRunner.err.writeln(
        pretty.convert({
          ...fault.toJson(),
          if (warnings.isNotEmpty) 'warnings': warnings,
        }),
      );
    } else {
      warn(warnings);
      specstoneRunner.err.writeln(fault.toText());
    }
    return fault.exitStatus;
  }

  /// Writes each of [warnings] to `err` as `⚠️ WARNING: <warning>`.
  void warn(Iterable<String> warnings) {
    for (final warning in warnings) {
      specstoneRunner.err.writeln('⚠️ WARNING: $warning');
    }
  }
}
