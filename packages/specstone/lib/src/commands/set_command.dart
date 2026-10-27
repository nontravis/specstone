import 'package:specstone/src/commands/write_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Replaces one section, field, or title of a doc with the text on stdin.
class SetCommand extends WriteCommand {
  new() {
    argParser
      ..addOption(
        'base',
        help: 'The base hash of the target, as `get` prints it.',
      )
      ..addOption('field', help: 'The id of the field to write.')
      ..addFlag(
        'title',
        negatable: false,
        help: 'Write the doc title, one line.',
      )
      ..addFlag('json', negatable: false, help: 'Print JSON instead of text.');
  }

  @override
  String get name => 'set';

  @override
  String get description =>
      'Replace a section, a field, or the title of a doc with stdin.';

  @override
  String get invocation =>
      'specstone set <type>:<name>[#<section key>] '
      '[--field <id> | --title] --base <hash> [--json]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final asJson = args.flag('json');
    final rest = args.rest;
    if (rest.length > 1) {
      usageException('Expected one target, got ${rest.length}.');
    }
    final SetRequest request;
    try {
      request = SetRequest.parse(
        rest.firstOrNull,
        field: args.option('field'),
        title: args.flag('title'),
        base: args.option('base'),
      );
    } on SpecstoneFault catch (fault) {
      return fail(fault, asJson: asJson);
    }
    final text = await console.readAll();
    return runWrite(
      (session) => answerSet(session, request, text),
      asJson: asJson,
    );
  }
}
