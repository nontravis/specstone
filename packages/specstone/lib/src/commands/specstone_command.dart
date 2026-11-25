import 'dart:convert';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:specstone/src/command_runner.dart';
import 'package:specstone_core/specstone_core.dart';

/// The hidden flag a bare `--out` is read as; see `withBareOut`.
const bareOutFlag = 'bare-out';

/// The options no bare `--out` file name lists as a flag.
const Set<String> _notOutFlags = {'out', 'json', 'target', bareOutFlag};

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

  /// Whether the run [args] name prints a reply `--out` may save.
  ///
  /// A command whose parser declares `dry-run` prints a reply only under it;
  /// another command overrides this and [outRefusal] when it has such a run.
  bool isReplyRun(ArgResults args) =>
      !argParser.options.containsKey('dry-run') || args.flag('dry-run');

  /// The `argument_invalid` message for an `--out` in a run that is no reply
  /// run.
  String get outRefusal => '--out goes with --dry-run';

  /// Whether the command writes its own `--out` files, which the runner then
  /// leaves alone.
  bool get writesOwnOut => false;

  /// Returns the long names of the options and flags [args] passed but `out`,
  /// `json`, `target`, and the bare-out flag, in code point order.
  List<String> outFlagsOf(ArgResults args) => [
    for (final name in argParser.options.keys)
      if (!_notOutFlags.contains(name) && args.wasParsed(name)) name,
  ]..sort();

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

  /// Writes [fault] to `err`, marks the run faulted so no `--out` file is
  /// written, and returns its exit status.
  ///
  /// Prints the JSON envelope when [asJson], else the text form. [warnings]
  /// the run collected before it failed are not lost: the text form prints
  /// them first, and the envelope always carries them as a top-level
  /// `warnings` array beside `error`, empty when the run raised none.
  int fail(
    SpecstoneFault fault, {
    required bool asJson,
    List<String> warnings = const [],
  }) {
    specstoneRunner.recordFault();
    if (fault is TemplateFault &&
        (fault.code == FaultCode.packPinOlder ||
            fault.code == FaultCode.packPinNewer)) {
      specstoneRunner.recordPinRefusal();
    }
    if (asJson) {
      specstoneRunner.err.writeln(
        pretty.convert({...fault.toJson(), 'warnings': warnings}),
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
  /// [fail] with the warnings collected so far. [fillSearchRows] opens the
  /// session with its search rows filled. [ReadSession.run] closes each
  /// session once and rebuilds an index [answer] finds damaged.
  Future<int> runRead(
    ReadAnswer Function(ReadSession session) answer, {
    required bool asJson,
    bool fillSearchRows = false,
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
        fillSearchRows: fillSearchRows,
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
}
