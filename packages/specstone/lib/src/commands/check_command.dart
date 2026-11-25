import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Checks every doc, or a target and the docs under it, and prints the
/// findings.
///
/// It does not go through `runRead`: a check report carries its own exit
/// status (1 when any finding exists), so the command prints the
/// [CheckReport] and returns `report.exitStatus`.
class CheckCommand extends SpecstoneCommand {
  new() {
    argParser
      ..addFlag('json', negatable: false, help: 'Print JSON instead of text.')
      ..addFlag(
        'repeats',
        negatable: false,
        help: 'List the text repeated across docs, and no finding.',
      );
    addOutOption();
    addTargetOption();
  }

  @override
  String get name => 'check';

  @override
  String get description =>
      'Check every doc, or a target and the docs under it.';

  @override
  String get invocation =>
      'specstone check [<target>] [--target <name>] [--repeats] [--json] '
      '[--out [<path>]]';

  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.rest.length > 1) {
      usageException('Expected at most one target, got ${args.rest.length}.');
    }
    final asJson = args.flag('json');
    final isRepeats = args.flag('repeats');
    final runner = specstoneRunner;
    var sessionWarnings = const <String>[];
    final _Output output;
    try {
      output = await ReadSession.runAsync(
        (session) async {
          sessionWarnings = session.warnings;
          final target = args.rest.firstOrNull;
          final codeTarget = targetOf(args);
          if (isRepeats) {
            final repeats = runRepeats(
              session,
              target: target,
              codeTarget: codeTarget,
            );
            return _Output(
              shown: asJson
                  ? '${SpecstoneCommand.pretty.convert(repeats.json)}\n'
                  : repeats.text,
              warnings: repeats.warnings,
              exitStatus: 0,
            );
          }
          final report = await runCheck(
            session,
            target: target,
            codeTarget: codeTarget,
          );
          return _Output(
            shown: asJson
                ? '${SpecstoneCommand.pretty.convert(report.json)}\n'
                : report.text,
            warnings: report.warnings,
            exitStatus: report.exitStatus,
          );
        },
        templates: runner.templates,
        workingDirectory: runner.workingDirectory,
        homeDirectory: runner.homeDirectory,
        busyTimeout: runner.busyTimeout,
      );
    } on SpecstoneFault catch (fault) {
      return fail(fault, asJson: asJson, warnings: sessionWarnings);
    }
    if (!asJson) warn(output.warnings);
    runner.out.write(output.shown);
    return output.exitStatus;
  }
}

/// What a check or `--repeats` run prints, and its exit status.
final class _Output {
  const new({
    required this.shown,
    required this.warnings,
    required this.exitStatus,
  });

  /// The output as printed: the JSON text with `--json`, else the report text.
  final String shown;
  final List<String> warnings;
  final int exitStatus;
}
