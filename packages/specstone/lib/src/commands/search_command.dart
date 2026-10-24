import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Prints the docs and sections whose text matches a query.
class SearchCommand extends SpecstoneCommand {
  new() {
    argParser
      ..addOption('type', help: 'Keep hits in docs of this doc type.')
      ..addOption(
        'under',
        help: 'Keep hits in the subtrees of the docs this name addresses.',
      )
      ..addOption(
        'limit',
        help: 'Print at most this many hits (default $defaultSearchLimit).',
      )
      ..addFlag('json', negatable: false, help: 'Print JSON instead of text.');
  }

  @override
  String get name => 'search';

  @override
  String get description => 'Search the text of every doc.';

  @override
  String get invocation =>
      'specstone search <query> [--type <id>] [--under <name>] [--limit N] '
      '[--json]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final asJson = args.flag('json');
    final rest = args.rest;
    if (rest.isEmpty) {
      return fail(
        missingArgument(
          'search',
          'a query',
          'specstone search "lock the account"',
        ),
        asJson: asJson,
      );
    }
    final query = rest.join(' ');
    final SearchOptions options;
    try {
      checkQuery(query);
      options = SearchOptions(
        docTypeId: args.option('type'),
        under: args.option('under'),
        limit:
            parsePositiveOption('--limit', args.option('limit')) ??
            defaultSearchLimit,
      );
    } on IndexFault catch (fault) {
      return fail(fault, asJson: asJson);
    }
    return runRead(
      (session) => answerSearch(session.index, query, options),
      asJson: asJson,
    );
  }
}
