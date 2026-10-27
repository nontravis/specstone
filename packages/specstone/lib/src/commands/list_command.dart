import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Lists the docs of one doc type, narrowed by filters.
class ListCommand extends SpecstoneCommand {
  new() {
    argParser
      ..addOption(
        'status',
        help: 'Keep docs with this status; a feature takes its computed one.',
      )
      ..addFlag('draft', negatable: false, help: 'Keep docs marked draft.')
      ..addOption(
        'under',
        help: 'Keep the subtrees of the docs this name addresses.',
      )
      ..addOption(
        'cites',
        help: 'Keep docs whose frontmatter holds this value.',
      )
      ..addOption('slug', help: 'Keep docs whose aliases hold this slug.')
      ..addFlag(
        'no-implements',
        negatable: false,
        help: 'Keep docs with no implements entry.',
      )
      ..addFlag(
        'suspect',
        negatable: false,
        help: 'Keep docs with a suspect link.',
      )
      ..addFlag('json', negatable: false, help: 'Print JSON instead of text.');
  }

  @override
  String get name => 'list';

  @override
  String get description => 'List the docs of one doc type.';

  @override
  String get invocation =>
      'specstone list <type> [--status <value>] [--draft] [--under <name>] '
      '[--cites <id>] [--slug <alias>] [--no-implements] [--suspect] [--json]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final asJson = args.flag('json');
    final rest = args.rest;
    if (rest.isEmpty) {
      return fail(
        missingArgument('list', 'a doc type', 'specstone list feature'),
        asJson: asJson,
      );
    }
    if (rest.length > 1) {
      usageException('Expected one doc type, got ${rest.length}.');
    }
    final filters = ListFilters(
      status: args.option('status'),
      draft: args.flag('draft'),
      under: args.option('under'),
      cites: args.option('cites'),
      slug: args.option('slug'),
      noImplements: args.flag('no-implements'),
    );
    return runRead(
      (session) => args.flag('suspect')
          ? answerListSuspect(session, rest.first, filters)
          : answerList(session.index, rest.first, filters),
      asJson: asJson,
    );
  }
}
