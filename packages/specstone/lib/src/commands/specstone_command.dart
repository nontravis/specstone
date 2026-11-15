import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';

/// The hidden flag a bare `--out` is read as; see `withBareOut`.
const bareOutFlag = 'bare-out';

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

  /// Adds the shared `--target` option a command that resolves a doc address
  /// takes: the code target its names stay in.
  void addTargetOption() {
    argParser.addOption(
      'target',
      help: "Keep names to one code target's docs and the shared docs.",
    );
  }

  /// Adds the shared `--out` option a command that can save its output to a
  /// file takes, and the hidden flag `withBareOut` turns a bare `--out` into.
  void addOutOption() {
    argParser
      ..addOption(
        'out',
        valueHelp: 'path',
        help:
            'Write the output to this file, or under .specstone/ when given '
            'no path, and print its header.',
      )
      ..addFlag(bareOutFlag, negatable: false, hide: true);
  }

  /// Whether [args] carry `--out`, with a path or bare.
  bool writesOut(ArgResults args) =>
      args.option('out') != null || args.flag(bareOutFlag);

  /// Returns the path `--out` names, or null when it is off or bare.
  ///
  /// Throws `argument_invalid` for an empty path, so an empty shell variable
  /// never falls back to the command's own file name.
  String? outPathOf(ArgResults args) {
    final out = args.option('out');
    if (out != null && out.isEmpty) {
      throw IndexFault(
        IndexFaultCode.argumentInvalid,
        '--out takes a file path, not ""',
      );
    }
    return out;
  }

  /// Returns the code target `--target` names, or null when the flag is off.
  ///
  /// A `--target` given no value reads as `''`, which the index refuses as
  /// `argument_missing` (the runner supplies the empty value).
  String? targetOf(ArgResults args) => args.option('target');

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
    if (fault is TemplateFault &&
        (fault.code == FaultCode.packPinOlder ||
            fault.code == FaultCode.packPinNewer)) {
      specstoneRunner.recordPinRefusal();
    }
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

  /// Refuses, as a usage error, `--yes` with `--dry-run` or without `--plan`,
  /// and `--plan` without `--yes`.
  ///
  /// - [planCommand]: the command whose `--dry-run` prints the plan line.
  void checkPlanFlags({
    required bool yes,
    required String? planHash,
    required String planCommand,
    bool dryRun = false,
  }) {
    if (dryRun && yes) usageException('--yes cannot go with --dry-run.');
    if (yes && planHash == null) {
      usageException(
        '--yes needs --plan <hash>, the plan line $planCommand --dry-run '
        'prints.',
      );
    }
    if (!yes && planHash != null) {
      usageException('--plan goes only with --yes.');
    }
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

  /// Returns the object `--json` prints for [answer]: [ReadAnswer.json] with a
  /// `warnings` array of [warnings] then the answer's.
  Map<String, Object?> printedJson(ReadAnswer answer, List<String> warnings) =>
      {
        ...answer.json,
        'warnings': [...warnings, ...answer.warnings],
      };

  /// Prints [answer] and returns its exit status.
  ///
  /// Under [asJson] it prints [printedJson] on `out`. Else it warns on `err`
  /// and writes [ReadAnswer.text] on `out`.
  int printAnswer(
    ReadAnswer answer,
    List<String> warnings, {
    required bool asJson,
  }) {
    final out = specstoneRunner.out;
    if (asJson) {
      out.write('${pretty.convert(printedJson(answer, warnings))}\n');
    } else {
      warn([...warnings, ...answer.warnings]);
      out.write(answer.text);
    }
    return answer.exitStatus;
  }

  /// Writes [text], the whole `--out` file, to [outPath], or to the file named
  /// for the command when [outPath] is null, and returns the reply that names
  /// it.
  ///
  /// Outside a project ([projectRoot] null) a bare file goes under the working
  /// directory, and the write refuses it. [flags], [args], and [codeTarget]
  /// shape the bare file name.
  ///
  /// Throws the fault of `answerOutFile`.
  ReadAnswer answerOut({
    required String command,
    required String text,
    required String? outPath,
    required Directory? projectRoot,
    required Directory? docsRoot,
    required bool asJson,
    List<String> flags = const [],
    List<String> args = const [],
    String? codeTarget,
    List<String> warnings = const [],
    int exitStatus = 0,
  }) {
    final workingDirectory = specstoneRunner.workingDirectory;
    return answerOutFile(
      command: command,
      text: text,
      file: outPath == null
          ? bareOutFile(
              projectRoot ?? workingDirectory,
              outFileName(
                command: command,
                flags: flags,
                args: args,
                codeTarget: codeTarget,
                asJson: asJson,
              ),
            )
          : File(absoluteFrom(workingDirectory, outPath)),
      projectRoot: projectRoot,
      docsRoot: docsRoot,
      isBare: outPath == null,
      asJson: asJson,
      warnings: warnings,
      exitStatus: exitStatus,
    );
  }
}
