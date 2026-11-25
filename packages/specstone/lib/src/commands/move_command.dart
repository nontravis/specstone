import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:specstone/src/commands/write_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Moves stories, FRs, nfs, features, items, or scenarios under a new parent.
class MoveCommand extends WriteCommand {
  new() {
    addTargetOption();
    addOutOption();
    argParser
      ..addOption(
        'under',
        help:
            'The feature that takes user_story or feature targets, the story '
            'that takes fr, nf, or scenario targets, or the doc that takes '
            'item targets: <doc type>:<name>, a bare name, or a path.',
      )
      ..addOption(
        'plan-file',
        valueHelp: 'file',
        help:
            'Apply every line of a move plan in one call; it takes no target, '
            '--under, or --top.',
      )
      ..addFlag(
        'plan-out',
        negatable: false,
        help:
            'Print a plan of each named doc as it stands: its source line, '
            'then a keep line per unit.',
      )
      ..addFlag(
        'top',
        negatable: false,
        help:
            'Move feature targets among the top features, in place of '
            '--under.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help:
            'Run every check and print what the move would do; write nothing.',
      )
      ..addFlag('json', negatable: false, help: 'Print JSON instead of text.');
  }

  @override
  String get name => 'move';

  @override
  String get description =>
      'Move stories and features under a feature, FRs and nfs under a '
      'story, features among the top features, items '
      '(<doc address>#<item ID>) into another doc, or scenarios '
      '(<story address>#S<N>) into another story, '
      'and rewrite every reference to them.';

  @override
  String get invocation =>
      'specstone move <doc address> … (--under <doc address> | --top) '
      '[--dry-run [--out [<path>]]] [--target <name>] [--json]\n'
      'specstone move --plan-file <file> [--dry-run [--out [<path>]]] '
      '[--target <name>] [--json]\n'
      'specstone move --plan-out <doc address> … [--target <name>] '
      '[--out [<path>]] [--json]';

  @override
  bool isReplyRun(ArgResults args) =>
      args.flag('plan-out') || args.flag('dry-run');

  @override
  String get outRefusal => '--out goes with --plan-out or --dry-run';

  @override
  Future<int> run() {
    final args = argResults!;
    final asJson = args.flag('json');
    final planFile = args.option('plan-file');
    if (args.flag('plan-out')) return _runPlanOut(args, asJson: asJson);
    if (planFile != null) return _runPlan(args, planFile, asJson: asJson);
    if (args.rest.isEmpty) {
      return Future.value(
        fail(
          missingArgument(
            name,
            'a target',
            'specstone move user_story:login/reset_password --under account',
          ),
          asJson: asJson,
        ),
      );
    }
    return runWrite(
      (session) => answerMove(
        session,
        args.rest,
        under: args.option('under'),
        top: args.flag('top'),
        codeTarget: targetOf(args),
        dryRun: args.flag('dry-run'),
      ),
      asJson: asJson,
    );
  }

  Future<int> _runPlan(
    ArgResults args,
    String planFile, {
    required bool asJson,
  }) {
    if (args.rest.isNotEmpty ||
        args.option('under') != null ||
        args.flag('top')) {
      return Future.value(
        fail(
          IndexFault(
            IndexFaultCode.argumentConflict,
            'move takes --plan-file or targets, not both',
          ),
          asJson: asJson,
        ),
      );
    }
    final String text;
    try {
      text = _planTextOf(planFile);
    } on IndexFault catch (fault) {
      return Future.value(fail(fault, asJson: asJson));
    }
    return runWrite(
      (session) => answerPlanMove(
        session,
        parseMovePlan(text, path: planFile),
        codeTarget: targetOf(args),
        dryRun: args.flag('dry-run'),
      ),
      asJson: asJson,
    );
  }

  /// Returns the text of the plan file [planFile] names, read as UTF-8.
  ///
  /// Throws [IndexFault] `argument_invalid` naming [planFile] as typed for a
  /// file that is missing, unreadable, or not UTF-8 text.
  String _planTextOf(String planFile) {
    final file = File(absoluteFrom(specstoneRunner.workingDirectory, planFile));
    final unreadable = IndexFault(
      IndexFaultCode.argumentInvalid,
      '$planFile: cannot read the plan file',
    );
    try {
      return utf8.decode(file.readAsBytesSync());
    } on FileSystemException {
      throw unreadable;
    } on FormatException {
      throw unreadable;
    }
  }

  Future<int> _runPlanOut(ArgResults args, {required bool asJson}) {
    if (args.option('plan-file') != null ||
        args.option('under') != null ||
        args.flag('top') ||
        args.flag('dry-run')) {
      return Future.value(
        fail(
          IndexFault(
            IndexFaultCode.argumentConflict,
            'move --plan-out takes no --plan-file, --under, --top, or '
            '--dry-run',
          ),
          asJson: asJson,
        ),
      );
    }
    if (args.rest.isEmpty) {
      return Future.value(
        fail(
          missingArgument(
            name,
            'a doc address',
            'specstone move --plan-out domain:shop',
          ),
          asJson: asJson,
        ),
      );
    }
    return runWrite(
      (session) => _skeletonAnswer(session, args),
      asJson: asJson,
    );
  }

  ReadAnswer _skeletonAnswer(WriteSession session, ArgResults args) {
    final plan = planSkeletonOf(session, args.rest, codeTarget: targetOf(args));
    return ReadAnswer(text: plan, json: {'plan': plan});
  }
}
