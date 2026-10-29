import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Builds a self-contained copy of the docs under a file or folder.
///
/// Needs a target. Writes under `.specstone/build/` unless `--output` names a
/// file.
class BuildCommand extends SpecstoneCommand {
  new() {
    argParser
      ..addOption(
        'format',
        valueHelp: 'html',
        defaultsTo: OutputFormat.html.name,
        help: 'The kind of copy to build: html.',
      )
      ..addOption(
        'paper',
        valueHelp: 'a4|a5|letter|legal',
        defaultsTo: Paper.a4.wire,
        help: 'The paper the html prints on.',
      )
      ..addFlag(
        'landscape',
        negatable: false,
        help: 'Print the pages in landscape.',
      )
      ..addOption(
        'margin',
        valueHelp: 'length',
        defaultsTo: PageSetup.defaults.margin,
        help: 'The margin on every side of a printed page, in mm, cm, or in.',
      )
      ..addOption(
        'output',
        valueHelp: 'file',
        help: 'Write the copy here instead of under .specstone/build/.',
      )
      ..addFlag('json', negatable: false, help: 'Print JSON instead of text.');
  }

  @override
  String get name => 'build';

  @override
  String get description => 'Build an html copy of docs.';

  @override
  String get invocation =>
      'specstone build <target> [--format html] [--paper a4|a5|letter|legal] '
      '[--landscape] [--margin <length>] [--output <file>] [--json]';

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
    final outputOption = argResults!.option('output');

    final BuildResult result;
    final warnings = <String>[];
    try {
      final format = OutputFormat.parse(argResults!.option('format'));
      final page = PageSetup.parse(
        paper: argResults!.option('paper'),
        landscape: argResults!.flag('landscape'),
        margin: argResults!.option('margin'),
      );
      final project = DocsProject.open(
        templates: runner.templates,
        workingDirectory: runner.workingDirectory,
        homeDirectory: runner.homeDirectory,
      );
      final target = project.resolveTarget(
        rest.firstOrNull,
        workingDirectory: runner.workingDirectory,
        defaultsToDocsRoot: false,
      );
      final output = outputOption == null
          ? defaultOutputFile(project, target, format)
          : _outputFile(outputOption, runner.workingDirectory);
      final displayPath = outputOption != null && File(outputOption).isAbsolute
          ? outputOption
          : project.displayPath(output);
      if (project.isInsideDocsRoot(output)) {
        throw RenderFault(
          RenderFaultCode.outputNotWritable,
          'the output path is inside the docs root',
          file: displayPath,
        );
      }
      final build = buildHtml(project, target, page: page);
      warnings.addAll(build.warnings);
      writeBuildOutput(
        output,
        utf8.encode(build.html),
        displayPath: displayPath,
      );
      result = BuildResult(output: displayPath, warnings: warnings);
    } on SpecstoneFault catch (fault) {
      return fail(fault, asJson: asJson, warnings: warnings);
    }

    if (asJson) {
      runner.out.write('${SpecstoneCommand.pretty.convert(result.toJson())}\n');
    } else {
      runner.out.write('${result.output}\n');
      warn(result.warnings);
    }
    return 0;
  }
}

File _outputFile(String option, Directory workingDirectory) {
  final file = File(option);
  if (file.isAbsolute) return file;
  return File(
    '${workingDirectory.absolute.path}${Platform.pathSeparator}$option',
  );
}
