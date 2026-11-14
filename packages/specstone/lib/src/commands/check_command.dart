import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Checks every doc, or a target and the docs under it, and prints the
/// findings.
///
/// It does not go through `runRead`: a check report carries its own exit
/// status (1 when any finding exists), so the command prints the
/// [CheckReport] and returns `report.exitStatus` (PD2).
class CheckCommand extends SpecstoneCommand {
  new() {
    argParser
      ..addFlag('json', negatable: false, help: 'Print JSON instead of text.')
      ..addFlag(
        'repeats',
        negatable: false,
        help: 'List the text repeated across docs, and no finding.',
      );
    addTargetOption();
  }

  @override
  String get name => 'check';

  @override
  String get description =>
      'Check every doc, or a target and the docs under it.';

  @override
  String get invocation =>
      'specstone check [<target>] [--target <name>] [--repeats] [--json]';

  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.rest.length > 1) {
      usageException('Expected at most one target, got ${args.rest.length}.');
    }
    final asJson = args.flag('json');
    final runner = specstoneRunner;
    var sessionWarnings = const <String>[];
    final RepeatReport? repeats;
    final CheckReport? report;
    try {
      (repeats, report) = ReadSession.run(
        (session) {
          sessionWarnings = session.warnings;
          final target = args.rest.firstOrNull;
          final codeTarget = targetOf(args);
          return args.flag('repeats')
              ? (
                  runRepeats(session, target: target, codeTarget: codeTarget),
                  null,
                )
              : (
                  null,
                  runCheck(session, target: target, codeTarget: codeTarget),
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
    if (repeats != null) return _printRepeats(repeats, asJson: asJson);
    if (asJson) {
      runner.out.write('${SpecstoneCommand.pretty.convert(report!.json)}\n');
    } else {
      warn(report!.warnings);
      runner.out.write(report.text);
    }
    return report.exitStatus;
  }

  int _printRepeats(RepeatReport repeats, {required bool asJson}) {
    final text = asJson
        ? '${SpecstoneCommand.pretty.convert(repeats.json)}\n'
        : repeats.text;
    specstoneRunner.out.write(text);
    return 0;
  }
}
