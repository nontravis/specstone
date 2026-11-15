import 'dart:io';

import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Prints the docs each name addresses, or one section of each.
class GetCommand extends SpecstoneCommand {
  new() {
    argParser
      ..addFlag('json', negatable: false, help: 'Print JSON instead of text.')
      ..addFlag(
        'paths',
        negatable: false,
        help: 'Print each start-to-end path of a journey.',
      )
      ..addFlag(
        'code',
        negatable: false,
        help: 'Print the code each step of a journey reaches.',
      );
    addOutOption();
    addTargetOption();
  }

  @override
  String get name => 'get';

  @override
  String get description =>
      'Print the docs each name addresses, or a section, in one call.';

  @override
  String get invocation =>
      'specstone get <name | path>[#<section key>] … [--paths | --code] '
      '[--json] [--out [<path>]]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final asJson = args.flag('json');
    final rest = args.rest;
    if (rest.isEmpty) {
      return fail(
        missingArgument('get', 'a name', 'specstone get login'),
        asJson: asJson,
      );
    }
    final paths = args.flag('paths');
    final code = args.flag('code');
    if (paths && code) {
      return fail(
        IndexFault(
          IndexFaultCode.argumentConflict,
          '--code and --paths cannot be given together',
        ),
        asJson: asJson,
      );
    }
    final String? out;
    try {
      out = outPathOf(args);
    } on IndexFault catch (fault) {
      return fail(fault, asJson: asJson);
    }
    final option = paths ? '--paths' : (code ? '--code' : null);
    if (option != null && rest.length > 1) {
      return fail(
        IndexFault(
          IndexFaultCode.argumentInvalid,
          '$option takes one name, got ${rest.length}',
        ),
        asJson: asJson,
      );
    }
    return runRead((session) {
      if (option != null &&
          session.index.splitAddress(rest.first).sectionKey != null) {
        throw IndexFault(
          IndexFaultCode.argumentConflict,
          '$option takes no #<section key>',
        );
      }
      final answer = switch ((paths, code)) {
        (true, _) => answerJourneyPaths(
          session.index,
          rest.first,
          codeTarget: targetOf(args),
        ),
        (_, true) => answerJourneyCode(
          session.index,
          rest.first,
          codeTarget: targetOf(args),
        ),
        _ => answerGet(session.index, rest, codeTarget: targetOf(args)),
      };
      return writesOut(args) ? _written(session, answer, out) : answer;
    }, asJson: asJson);
  }

  /// Writes [answer] to the `--out` file, bare when [out] is null, and returns
  /// the reply that names it.
  ReadAnswer _written(ReadSession session, ReadAnswer answer, String? out) {
    final args = argResults!;
    final asJson = args.flag('json');
    final project = session.project;
    final text = asJson
        ? '${SpecstoneCommand.pretty.convert({
            ...answer.json,
            'warnings': [...session.warnings, ...answer.warnings],
          })}\n'
        : answer.text;
    return answerOutFile(
      command: 'get',
      text: text,
      file: out == null
          ? bareOutFile(
              project.projectRoot,
              outFileName(
                command: 'get',
                flags: [
                  if (args.flag('paths')) 'paths',
                  if (args.flag('code')) 'code',
                ],
                args: args.rest,
                codeTarget: targetOf(args),
                asJson: asJson,
              ),
            )
          : File(absoluteFrom(specstoneRunner.workingDirectory, out)),
      projectRoot: project.projectRoot,
      docsRoot: project.docsRoot,
      isBare: out == null,
      asJson: asJson,
      warnings: answer.warnings,
      exitStatus: answer.exitStatus,
    );
  }
}
