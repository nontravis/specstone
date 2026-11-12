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
            'the views.',
      );
  }

  static final _seenDraft = RegExp(r'^(.+)@([0-9a-f]{12})$');

  @override
  String get name => 'approve';

  @override
  String get description => "Show each draft and approve it at the Owner's y.";

  @override
  String get invocation =>
      'specstone approve [<name> …] [--dry-run] [--context <n> | --json] '
      '| <name>@<hash> … --yes';

  @override
  Future<int> run() async {
    final args = argResults!;
    final names = args.rest;
    final yes = args.flag('yes');
    final dryRun = args.flag('dry-run');
    final contextArg = args.option('context');
    final asJson = args.flag('json');
    if (dryRun && yes) {
      usageException('--dry-run goes without --yes.');
    }
    if (contextArg != null && yes) {
      usageException('--context goes without --yes.');
    }
    if (asJson && !dryRun) {
      usageException('--json goes only with --dry-run.');
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
    final color = console.stdoutIsTerminal && !console.noColor;
    if (dryRun) {
      return runWrite(
        (session) => approveDryRun(
          session,
          names: names,
          context: context,
          color: color,
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
      return runWrite((session) => approveNamed(session, seen), asJson: false);
    }
    return runWrite((session) {
      approveDrafts(
        session,
        names: names,
        readLine: console.readLine,
        out: specstoneRunner.out,
        context: context,
        color: color,
      );
      return const ReadAnswer(text: '', json: {});
    }, asJson: false);
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
        '--yes needs each draft as <name>@<hash>, the hash from bases.doc of '
        'specstone get --json; got $arg.',
      );
    }
    return (name: match[1]!, hash: match[2]!);
  }
}
