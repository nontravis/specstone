import 'dart:io';

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
    final runner = specstoneRunner;
    var sessionWarnings = const <String>[];
    DocsProject? project;
    final RepeatReport? repeats;
    final CheckReport? report;
    final String? out;
    try {
      out = outPathOf(args);
      (repeats, report) = ReadSession.run(
        (session) {
          sessionWarnings = session.warnings;
          project = session.project;
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
    if (writesOut(args)) {
      return _writeReport(
        args,
        project!,
        repeats: repeats,
        report: report,
        out: out,
      );
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

  /// Writes the report, or the repeats, to the `--out` file and prints its
  /// header; the check's own exit status and warnings pass through.
  int _writeReport(
    ArgResults args,
    DocsProject project, {
    required RepeatReport? repeats,
    required CheckReport? report,
    required String? out,
  }) {
    final asJson = args.flag('json');
    final json = repeats?.json ?? report!.json;
    final text = repeats?.text ?? report!.text;
    final warnings = repeats?.warnings ?? report!.warnings;
    final workingDirectory = specstoneRunner.workingDirectory;
    final ReadAnswer answer;
    try {
      answer = answerOutFile(
        command: 'check',
        text: asJson ? '${SpecstoneCommand.pretty.convert(json)}\n' : text,
        file: out == null
            ? bareOutFile(
                project.projectRoot,
                outFileName(
                  command: 'check',
                  flags: [if (repeats != null) 'repeats'],
                  args: args.rest,
                  codeTarget: targetOf(args),
                  asJson: asJson,
                ),
              )
            : File(absoluteFrom(workingDirectory, out)),
        projectRoot: project.projectRoot,
        docsRoot: project.docsRoot,
        isBare: out == null,
        asJson: asJson,
        warnings: warnings,
        exitStatus: repeats != null ? 0 : report!.exitStatus,
      );
    } on SpecstoneFault catch (fault) {
      return fail(fault, asJson: asJson, warnings: warnings);
    }
    return printAnswer(answer, const [], asJson: asJson);
  }

  int _printRepeats(RepeatReport repeats, {required bool asJson}) {
    if (asJson) {
      specstoneRunner.out.write(
        '${SpecstoneCommand.pretty.convert(repeats.json)}\n',
      );
    } else {
      warn(repeats.warnings);
      specstoneRunner.out.write(repeats.text);
    }
    return 0;
  }
}
