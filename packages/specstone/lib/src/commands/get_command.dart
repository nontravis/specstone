import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Prints the docs a name addresses, or one section of each.
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
  String get description => 'Print the docs a name addresses, or a section.';

  @override
  String get invocation =>
      'specstone get <name>[#<section key>] [--paths | --code] [--json]';

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
    if (rest.length > 1) {
      usageException('Expected one name, got ${rest.length}.');
    }
    final paths = args.flag('paths');
    final code = args.flag('code');
    final conflict = _journeyConflict(paths: paths, code: code);
    if (conflict != null) {
      return fail(
        IndexFault(IndexFaultCode.argumentConflict, conflict),
        asJson: asJson,
      );
    }
    final name = rest.first;
    return runRead(
      (session) => switch ((paths, code)) {
        (true, _) => answerJourneyPaths(session.index, name),
        (_, true) => answerJourneyCode(session.index, name),
        _ => answerGet(session.index, name),
      },
      asJson: asJson,
    );
  }

  /// Returns the message for a journey option given with another, or with a
  /// `#<section key>`; null when the flags and the name agree.
  String? _journeyConflict({required bool paths, required bool code}) {
    if (paths && code) return '--code and --paths cannot be given together';
    final option = paths ? '--paths' : (code ? '--code' : null);
    if (option != null && argResults!.rest.first.contains('#')) {
      return '$option takes no #<section key>';
    }
    return null;
  }
}
