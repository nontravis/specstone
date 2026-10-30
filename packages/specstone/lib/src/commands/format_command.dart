import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Formats the docs under a file or folder to their templates.
///
/// Without a target it takes the docs root. With `--check` it lists what would
/// change and writes nothing.
class FormatCommand extends SpecstoneCommand {
  new() {
    argParser
      ..addFlag(
        'check',
        negatable: false,
        help: 'List the docs that would change; write nothing.',
      )
      ..addFlag('json', negatable: false, help: 'Print JSON instead of text.');
  }

  @override
  String get name => 'format';

  @override
  String get description => 'Format docs to their template.';

  @override
  String get invocation =>
      'specstone format [<file|folder>] [--check] [--json]';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length > 1) {
      usageException(
        'Expected at most one file or folder, got ${rest.length}.',
      );
    }
    final runner = specstoneRunner;
    final asJson = argResults!.flag('json');

    final FormatReport report;
    final sessionWarnings = <String>[];
    try {
      final project = DocsProject.open(
        templates: runner.templates,
        workingDirectory: runner.workingDirectory,
        homeDirectory: runner.homeDirectory,
      );
      final target = project.resolveTarget(
        rest.firstOrNull,
        workingDirectory: runner.workingDirectory,
        defaultsToDocsRoot: true,
      );
      report = runFormat<DocIndex>(
        project,
        target,
        check: argResults!.flag('check'),
        generators: GeneratorRun<DocIndex>(
          registry: runner.generators,
          open: () {
            final session = ReadSession.open(
              templates: runner.templates,
              workingDirectory: runner.workingDirectory,
              homeDirectory: runner.homeDirectory,
              busyTimeout: runner.busyTimeout,
            );
            sessionWarnings.addAll(session.warnings);
            return (resolver: session.index, close: session.close);
          },
        ),
      );
    } on SpecstoneFault catch (fault) {
      return fail(fault, asJson: asJson, warnings: sessionWarnings);
    }

    final warnings = [...sessionWarnings, ...report.warnings];
    if (asJson) {
      final json = {...report.toJson(), 'warnings': warnings};
      runner.out.write('${SpecstoneCommand.pretty.convert(json)}\n');
    } else {
      runner.out.write(report.toText());
      warn(warnings);
    }
    return report.exitStatus;
  }
}
