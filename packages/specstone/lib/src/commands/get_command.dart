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
  }

  @override
  String get name => 'get';

  @override
  String get description =>
      'Print the docs each name addresses, or a section, in one call.';

  @override
  String get invocation =>
      'specstone get <name | path>[#<section key>] … [--paths | --code] '
      '[--json]';

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
      return switch ((paths, code)) {
        (true, _) => answerJourneyPaths(session.index, rest.first),
        (_, true) => answerJourneyCode(session.index, rest.first),
        _ => answerGet(session.index, rest),
      };
    }, asJson: asJson);
  }
}
