import 'package:args/args.dart';
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
    addOutOption();
  }

  @override
  String get name => 'format';

  @override
  String get description => 'Format docs to their template.';

  @override
  String get invocation =>
      'specstone format [<file|folder>] [--check [--out [<path>]]] [--json]';

  @override
  bool isReplyRun(ArgResults args) => args.flag('check');

  @override
  String get outRefusal => '--out goes with --check';

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
    final check = argResults!.flag('check');

    final FormatReport report;
    final sessionWarnings = <String>[];
    try {
      final project = DocsProject.open(
        templates: runner.templates,
        workingDirectory: runner.workingDirectory,
        homeDirectory: runner.homeDirectory,
      );
      final generators = GeneratorRun<DocIndex>(
        registry: runner.generators,
        finishJournal: () => WriteSession.openReplayed(
          templates: runner.templates,
          workingDirectory: runner.workingDirectory,
          homeDirectory: runner.homeDirectory,
          busyTimeout: runner.busyTimeout,
          warnings: sessionWarnings,
        ).close(),
        open: () {
          final session = ReadSession.open(
            templates: runner.templates,
            workingDirectory: runner.workingDirectory,
            homeDirectory: runner.homeDirectory,
            busyTimeout: runner.busyTimeout,
          );
          sessionWarnings.addAll(
            session.indexWarnings.where(
              (line) => !sessionWarnings.contains(line),
            ),
          );
          return OpenedResolver(
            resolver: session.index,
            close: session.close,
            lockWrites: (write) => session.writeIndex((_) => write()),
          );
        },
      );
      // A write finishes an unfinished journal before it resolves its target,
      // as every write command does: the journal may move the target. A check
      // writes nothing and leaves it.
      if (!check) generators.finishPendingJournal(project);
      final target = project.resolveTarget(
        rest.firstOrNull,
        workingDirectory: runner.workingDirectory,
        defaultsToDocsRoot: true,
        includeRecordsRoot: true,
      );
      report = runFormat<DocIndex>(
        project,
        target,
        check: check,
        homeDirectory: runner.homeDirectory,
        generators: generators,
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
