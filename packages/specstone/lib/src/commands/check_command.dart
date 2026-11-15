import 'package:args/args.dart';
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
    final String? outPath;
    try {
      outPath = outPathOf(args);
      output = ReadSession.run(
        (session) {
          sessionWarnings = session.warnings;
          final target = args.rest.firstOrNull;
          final codeTarget = targetOf(args);
          final project = session.project;
          if (isRepeats) {
            final repeats = runRepeats(
              session,
              target: target,
              codeTarget: codeTarget,
            );
            return (
              project: project,
              json: repeats.json,
              text: repeats.text,
              warnings: repeats.warnings,
              exitStatus: 0,
            );
          }
          final report = runCheck(
            session,
            target: target,
            codeTarget: codeTarget,
          );
          return (
            project: project,
            json: report.json,
            text: report.text,
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
    final shown = asJson
        ? '${SpecstoneCommand.pretty.convert(output.json)}\n'
        : output.text;
    if (writesOut(args)) {
      return _writeOut(
        args,
        output,
        shown,
        outPath: outPath,
        asJson: asJson,
        isRepeats: isRepeats,
      );
    }
    if (!asJson) warn(output.warnings);
    runner.out.write(shown);
    return output.exitStatus;
  }

  /// Writes [shown], the output stdout would hold, to the `--out` file and
  /// prints its header; the check's own exit status and warnings pass through.
  int _writeOut(
    ArgResults args,
    _Output output,
    String shown, {
    required String? outPath,
    required bool asJson,
    required bool isRepeats,
  }) {
    try {
      final answer = answerOut(
        command: 'check',
        text: shown,
        outPath: outPath,
        projectRoot: output.project.projectRoot,
        docsRoot: output.project.docsRoot,
        asJson: asJson,
        flags: [if (isRepeats) 'repeats'],
        args: args.rest,
        codeTarget: targetOf(args),
        warnings: output.warnings,
        exitStatus: output.exitStatus,
      );
      return printAnswer(answer, const [], asJson: asJson);
    } on SpecstoneFault catch (fault) {
      return fail(fault, asJson: asJson, warnings: output.warnings);
    }
  }
}

typedef _Output = ({
  DocsProject project,
  Map<String, Object> json,
  String text,
  List<String> warnings,
  int exitStatus,
});
