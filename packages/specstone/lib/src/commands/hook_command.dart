import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Groups the commands that agent hooks run.
class HookCommand extends SpecstoneCommand {
  new() {
    addSubcommand(PostEditCommand());
  }

  @override
  String get name => 'hook';

  @override
  String get description => 'Commands that agent hooks run.';

  @override
  String get invocation => 'specstone hook <command>';
}

/// Checks the doc a `PostToolUse` hook reports as edited.
///
/// Reads the hook JSON on stdin and prints the doc's findings as hook output.
/// It never exits 2, so it blocks no edit (PD5 to PD7).
class PostEditCommand extends SpecstoneCommand {
  static const _expected =
      'hook post-edit expects one JSON object holding tool_input.file_path '
      'on stdin';
  static const _docsFolder = 'docs/';

  @override
  String get name => 'post-edit';

  @override
  String get description =>
      'Check the doc a PostToolUse hook edited and print its findings.';

  @override
  String get invocation => 'specstone hook post-edit < post-tool-use.json';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      usageException('Expected no argument, got ${argResults!.rest.length}.');
    }
    final runner = specstoneRunner;
    try {
      final filePath = _filePathOf(await runner.console.readAll());
      final project = DocsProject.open(
        templates: runner.templates,
        workingDirectory: runner.workingDirectory,
        homeDirectory: runner.homeDirectory,
      );
      final docPath = _checkedDocPath(project, filePath);
      if (docPath == null) return 0;
      final report = ReadSession.run(
        (session) => runCheck(session, docPath: docPath),
        templates: runner.templates,
        workingDirectory: runner.workingDirectory,
        homeDirectory: runner.homeDirectory,
        busyTimeout: runner.busyTimeout,
      );
      if (report.findings.isEmpty) return 0;
      final text = report.text;
      final context = text.substring(0, text.length - 1);
      final output = {
        'hookSpecificOutput': {
          'hookEventName': 'PostToolUse',
          'additionalContext': context,
        },
      };
      runner.out.write('${SpecstoneCommand.pretty.convert(output)}\n');
      return 0;
    } on RenderFault catch (fault) {
      if (fault.code == RenderFaultCode.projectNotFound) return 0;
      return fail(fault, asJson: false);
    } on SpecstoneFault catch (fault) {
      return fail(fault, asJson: false);
    }
  }

  /// Returns `tool_input.file_path` from [input], or throws
  /// `argument_invalid`.
  String _filePathOf(String input) {
    final Object? decoded;
    try {
      decoded = jsonDecode(input);
    } on FormatException {
      throw IndexFault(IndexFaultCode.argumentInvalid, _expected);
    }
    if (decoded case {'tool_input': {'file_path': final String path}}
        when path.isNotEmpty) {
      return path;
    }
    throw IndexFault(IndexFaultCode.argumentInvalid, _expected);
  }

  /// Returns the DocPath of [filePath] when it names a markdown file in a
  /// checked folder of the docs root, else null.
  String? _checkedDocPath(DocsProject project, String filePath) {
    final file = File(filePath);
    final resolved = file.isAbsolute
        ? file
        : File(
            '${specstoneRunner.workingDirectory.absolute.path}'
            '${Platform.pathSeparator}$filePath',
          );
    if (!project.isInsideDocsRoot(resolved)) return null;
    final shown = project.displayPath(resolved);
    if (!shown.startsWith(_docsFolder)) return null;
    final docPath = shown.substring(_docsFolder.length);
    if (!docPath.endsWith('.md')) return null;
    final folder = docPath.split('/').first;
    return checkedFoldersOf(project.set).contains(folder) ? docPath : null;
  }
}
