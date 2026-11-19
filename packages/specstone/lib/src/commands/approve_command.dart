import 'package:specstone/src/commands/write_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Walks the drafts and approves each one at the Owner's `y`, or approves the
/// drafts named `<name>@<hash>` under `--yes`.
class ApproveCommand extends WriteCommand {
  new() {
    argParser
      ..addFlag(
        'yes',
        negatable: false,
        help:
            'Approve the named drafts without the terminal prompt; the agent '
            "runs it after the Owner's ok.",
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help:
            'Print each draft as the walk shows it, without a terminal and '
            'without approving.',
      )
      ..addOption(
        'context',
        valueHelp: 'n',
        help:
            'Show n lines around each change, in place of the whole changed '
            'unit.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help:
            'With --dry-run, print the drafts as one JSON object in place of '
            'the views. With --auto, print the result as one JSON object.',
      )
      ..addFlag(
        'auto',
        negatable: false,
        help:
            'Judge the named drafts and approve the clean ones under the '
            "Owner's auto approve mode; no terminal needed.",
      )
      ..addMultiOption(
        'audit',
        valueHelp: 'path',
        splitCommas: false,
        help: 'With --auto, an audit report of the run, oldest first.',
      )
      ..addMultiOption(
        'author',
        valueHelp: 'path',
        splitCommas: false,
        help: 'With --auto, an author report of the run.',
      )
      ..addFlag(
        'no-audit',
        negatable: false,
        help: 'With --auto, the flow has no audit report.',
      );
    addTargetOption();
  }

  static final _seenDraft = RegExp(r'^(.+)@([0-9a-f]{12})$');

  @override
  String get name => 'approve';

  @override
  String get description => "Show each draft and approve it at the Owner's y.";

  @override
  String get invocation =>
      'specstone approve [<name> …] [--target <name>] [--dry-run] '
      '[--context <n> | --json] | <name>@<hash> … --yes [--target <name>] | '
      '<name> … --auto [--audit <path> … | --no-audit] [--author <path>] … '
      '[--json] [--target <name>]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final names = args.rest;
    final yes = args.flag('yes');
    final dryRun = args.flag('dry-run');
    final contextArg = args.option('context');
    final asJson = args.flag('json');
    final auto = args.flag('auto');
    _requireAutoCall(
      auto: auto,
      mixesForm: yes || dryRun || contextArg != null,
    );
    if (dryRun && yes) {
      usageException('--dry-run goes without --yes.');
    }
    if (contextArg != null && yes) {
      usageException('--context goes without --yes.');
    }
    if (asJson && !dryRun && !auto) {
      usageException('--json goes only with --dry-run or --auto.');
    }
    if (asJson && contextArg != null) {
      usageException('--json goes without --context.');
    }
    final context = contextArg == null ? null : _contextOf(contextArg);
    if (yes && names.isEmpty) {
      usageException('--yes needs the names of the drafts it approves.');
    }
    if (!yes) {
      // Only a `.md` file is a doc, so a name ending `@<12 hex>` is no path.
      for (final name in names.where(_seenDraft.hasMatch)) {
        usageException('$name: a @<hash> goes only with --yes.');
      }
    }
    if (auto) return _runAuto(names, codeTarget: targetOf(args));
    final color = console.stdoutIsTerminal && !console.noColor;
    if (dryRun) {
      return runWrite(
        (session) => approveDryRun(
          session,
          names: names,
          context: context,
          color: color,
          codeTarget: targetOf(args),
          approveModeVariable: asJson ? console.approveModeVariable : null,
        ),
        asJson: asJson,
      );
    }
    final seen = yes ? names.map(_seenDraftOf).toList() : const <SeenDraft>[];
    final confirmation = OwnerConfirmation.of(
      yes: yes,
      interactive: interactive,
    );
    try {
      confirmation.refuseIfMissing('approve runs only');
    } on SpecstoneFault catch (fault) {
      return failWrite(fault, asJson: false);
    }
    if (!confirmation.prompts) {
      return runWrite(
        (session) => approveNamed(session, seen, codeTarget: targetOf(args)),
        asJson: false,
      );
    }
    return runWrite((session) {
      approveDrafts(
        session,
        names: names,
        readLine: console.readLine,
        out: specstoneRunner.out,
        context: context,
        color: color,
        codeTarget: targetOf(args),
      );
      return const ReadAnswer(text: '', json: {});
    }, asJson: false);
  }

  /// Throws a usage error for a call `--auto` refuses: report flags without
  /// [auto], and [auto] with no name, beside another form ([mixesForm]), or
  /// with both `--audit` and `--no-audit`.
  void _requireAutoCall({required bool auto, required bool mixesForm}) {
    final args = argResults!;
    final hasAudit = args.multiOption('audit').isNotEmpty;
    final noAudit = args.flag('no-audit');
    if (!auto) {
      if (hasAudit || noAudit || args.multiOption('author').isNotEmpty) {
        usageException('--audit, --author, and --no-audit need --auto.');
      }
      return;
    }
    if (args.rest.isEmpty) {
      usageException('--auto needs the names of the drafts it approves.');
    }
    if (mixesForm) {
      usageException('--auto takes no --yes, --dry-run, or --context.');
    }
    if (hasAudit && noAudit) {
      usageException('--auto takes --audit <path> or --no-audit, not both.');
    }
  }

  Future<int> _runAuto(List<String> names, {required String? codeTarget}) {
    final args = argResults!;
    final call = AutoApproveCall(
      names: names,
      auditPaths: args.multiOption('audit'),
      authorPaths: args.multiOption('author'),
      noAudit: args.flag('no-audit'),
      workingDirectory: specstoneRunner.workingDirectory,
      codeTarget: codeTarget,
      approveModeVariable: console.approveModeVariable,
    );
    return runWriteAsync(
      (session) => approveAuto(session, call),
      asJson: args.flag('json'),
    );
  }

  /// Returns the whole number from 0 in [text].
  ///
  /// Throws a usage error for any other [text].
  int _contextOf(String text) {
    final value = int.tryParse(text);
    if (value == null || value < 0) {
      usageException('--context takes a whole number from 0.');
    }
    return value;
  }

  /// Returns the draft and hash of an `--yes` [arg], `<name>@<hash>`.
  ///
  /// Throws a usage error for an [arg] with no 12-hex `@<hash>`.
  SeenDraft _seenDraftOf(String arg) {
    final match = _seenDraft.firstMatch(arg);
    if (match == null) {
      usageException(
        '--yes needs each draft as <name>@<hash>, the hash from '
        'docs[0].bases.doc of specstone get <name> --json; got $arg.',
      );
    }
    return SeenDraft(name: match[1]!, hash: match[2]!);
  }
}
