import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone/src/console.dart';
import 'package:specstone_core/specstone_core.dart';

/// Base class of the commands that write documents.
abstract class WriteCommand extends SpecstoneCommand {
  /// The terminal facts and input of the runner this command runs under.
  Console get console => specstoneRunner.console;

  /// Whether both stdin and stdout are interactive terminals.
  bool get interactive => console.stdinIsTerminal && console.stdoutIsTerminal;

  /// Writes [fault] to `err` and returns its exit status.
  ///
  /// A [WriteFault] that carries the changed target prints it on `out` first
  /// outside [asJson]: its heading, then its text. Under [asJson] the
  /// envelope on `err` carries it and `out` stays empty.
  int failWrite(
    SpecstoneFault fault, {
    required bool asJson,
    List<String> warnings = const [],
  }) {
    if (!asJson && fault is WriteFault) {
      final current = fault.current;
      if (current != null) {
        final out = specstoneRunner.out
          ..writeln(current.heading)
          ..write(current.text);
        if (current.text.isNotEmpty && !current.text.endsWith('\n')) {
          out.writeln();
        }
      }
    }
    return fail(fault, asJson: asJson, warnings: warnings);
  }

  /// Opens a write session, prints what [answer] returns, and returns its
  /// exit status.
  ///
  /// Prints as [runRead] does, on a [WriteSession]; a [SpecstoneFault] goes to
  /// [failWrite] with the warnings collected so far.
  Future<int> runWrite(
    ReadAnswer Function(WriteSession session) answer, {
    required bool asJson,
  }) async {
    final runner = specstoneRunner;
    var sessionWarnings = const <String>[];
    final ReadAnswer written;
    try {
      written = WriteSession.run(
        (session) {
          sessionWarnings = session.warnings;
          return answer(session);
        },
        templates: runner.templates,
        workingDirectory: runner.workingDirectory,
        homeDirectory: runner.homeDirectory,
        busyTimeout: runner.busyTimeout,
      );
    } on SpecstoneFault catch (fault) {
      return failWrite(fault, asJson: asJson, warnings: sessionWarnings);
    }
    final warnings = [...sessionWarnings, ...written.warnings];
    if (asJson) {
      final printed = {...written.json, 'warnings': warnings};
      runner.out.write('${SpecstoneCommand.pretty.convert(printed)}\n');
    } else {
      warn(warnings);
      runner.out.write(written.text);
    }
    return written.exitStatus;
  }
}
