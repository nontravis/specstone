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
  /// outside [asJson]: its heading, then its text. A [BatchFault] prints the
  /// current text of each stale block the same way, in file order. Under
  /// [asJson] the envelope on `err` carries it and `out` stays empty.
  int failWrite(
    SpecstoneFault fault, {
    required bool asJson,
    List<String> warnings = const [],
  }) {
    if (!asJson) _currentsOf(fault).forEach(_printCurrent);
    return fail(fault, asJson: asJson, warnings: warnings);
  }

  Iterable<CurrentTarget> _currentsOf(SpecstoneFault fault) => switch (fault) {
    WriteFault(:final current) => [?current],
    BatchFault(:final entries) => [for (final entry in entries) ?entry.current],
    _ => const [],
  };

  void _printCurrent(CurrentTarget current) {
    final out = specstoneRunner.out
      ..writeln(current.heading)
      ..write(current.text);
    if (current.text.isNotEmpty && !current.text.endsWith('\n')) {
      out.writeln();
    }
  }

  /// Runs [answer] on the one target the command was given, through
  /// [runWrite].
  ///
  /// No target is `argument_missing` with [example]; more than one is a usage
  /// error.
  Future<int> runWriteOnTarget(
    String example,
    ReadAnswer Function(WriteSession session, String target) answer,
  ) {
    final asJson = argResults!.flag('json');
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      return Future.value(
        fail(missingArgument(name, 'a target', example), asJson: asJson),
      );
    }
    if (rest.length > 1) {
      usageException('Expected one target, got ${rest.length}.');
    }
    return runWrite((session) => answer(session, rest.first), asJson: asJson);
  }

  /// Opens a write session, prints what [answer] returns, and returns its
  /// exit status.
  ///
  /// Prints through [printAnswer], on a [WriteSession]; a [SpecstoneFault]
  /// goes to [failWrite] with the warnings collected so far.
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
    return printAnswer(written, sessionWarnings, asJson: asJson);
  }
}
