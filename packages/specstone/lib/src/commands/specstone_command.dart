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

  /// Opens a read session, prints what [answer] returns, and returns its exit
  /// status.
  ///
  /// Prints through [printAnswer] with the session's warnings. A
  /// [SpecstoneFault] from opening the session or from [answer] goes to
  /// [fail] with the warnings collected so far. [ReadSession.run] closes each
  /// session once and rebuilds an index [answer] finds damaged.
  Future<int> runRead(
    ReadAnswer Function(ReadSession session) answer, {
    required bool asJson,
  }) async {
    final runner = specstoneRunner;
    var sessionWarnings = const <String>[];
    final ReadAnswer read;
    try {
      read = ReadSession.run(
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
      return fail(fault, asJson: asJson, warnings: sessionWarnings);
    }
    return printAnswer(read, sessionWarnings, asJson: asJson);
  }

  /// Prints [answer] and returns its exit status.
  ///
  /// Under [asJson] it prints one object, [ReadAnswer.json] with a `warnings`
  /// array of [warnings] then the answer's, on `out`. Else it warns on `err`
  /// and writes [ReadAnswer.text] on `out`.
  int printAnswer(
    ReadAnswer answer,
    List<String> warnings, {
    required bool asJson,
  }) {
    final out = specstoneRunner.out;
    final allWarnings = [...warnings, ...answer.warnings];
    if (asJson) {
      final printed = {...answer.json, 'warnings': allWarnings};
      out.write('${pretty.convert(printed)}\n');
    } else {
      warn(allWarnings);
      out.write(answer.text);
    }
    return answer.exitStatus;
  }
}
