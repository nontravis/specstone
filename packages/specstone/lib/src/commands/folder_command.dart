import 'dart:io';

import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Prints the absolute path of the project's `.specstone` folder.
class FolderCommand extends SpecstoneCommand {
  new() {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print JSON instead of text.',
    );
  }

  @override
  String get name => 'folder';

  @override
  String get description => "Print the project's .specstone folder.";

  @override
  String get invocation => 'specstone folder [--json]';

  @override
  Future<int> run() async {
    final asJson = argResults!.flag('json');
    try {
      final rest = argResults!.rest;
      if (rest.isNotEmpty) {
        throw IndexFault(
          IndexFaultCode.argumentInvalid,
          'folder takes no argument, got ${rest.length}',
        );
      }
      final folder = _specstoneFolder(specstoneRunner.workingDirectory);
      final out = specstoneRunner.out;
      if (asJson) {
        out.write('${SpecstoneCommand.pretty.convert({'folder': folder})}\n');
      } else {
        out.writeln(folder);
      }
      return 0;
    } on SpecstoneFault catch (fault) {
      return fail(fault, asJson: asJson);
    }
  }
}

/// Returns the canonical `.specstone` path of the project above [start],
/// after making its `reports/` folder.
String _specstoneFolder(Directory start) {
  final root = matchProjectRoot(start)?.root;
  if (root == null) {
    throw RenderFault(
      RenderFaultCode.projectNotFound,
      'no Specstone project: no folder from the working directory upward '
      'holds .specstone/config.yaml',
    );
  }
  requireSpecstoneFolder(root);
  final folder = canonicalPath(
    '${root.path}${Platform.pathSeparator}.specstone',
  );
  final reports = Directory('$folder${Platform.pathSeparator}reports');
  try {
    reports.createSync(recursive: true);
  } on FileSystemException catch (error) {
    throw RenderFault(
      RenderFaultCode.outputNotWritable,
      'cannot make ${reports.path}: ${error.osError?.message ?? error.message}',
    );
  }
  return folder;
}
