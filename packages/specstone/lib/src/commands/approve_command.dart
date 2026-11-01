import 'package:specstone/src/commands/write_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Walks the drafts and approves each one at the Owner's `y`, or approves the
/// drafts named `<type>:<name>@<hash>` under `--yes`.
class ApproveCommand extends WriteCommand {
  new() {
    argParser.addFlag(
      'yes',
      negatable: false,
      help:
          'Approve the named drafts without the terminal prompt; the agent '
          "runs it after the Owner's ok.",
    );
  }

  static final _seenDraft = RegExp(r'^(.+)@([0-9a-f]{12})$');

  @override
  String get name => 'approve';

  @override
  String get description => "Show each draft and approve it at the Owner's y.";

  @override
  String get invocation =>
      'specstone approve [<name> …] | <type>:<name>@<hash> … --yes';

  @override
  Future<int> run() async {
    final args = argResults!;
    final names = args.rest;
    final yes = args.flag('yes');
    if (yes && names.isEmpty) {
      usageException('--yes needs the names of the drafts it approves.');
    }
    if (!yes) {
      for (final name in names.where((name) => name.contains('@'))) {
        usageException('$name: a @<hash> goes only with --yes.');
      }
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
      );
      return const ReadAnswer(text: '', json: {});
    }, asJson: false);
  }

  /// Returns the draft and hash of an `--yes` [arg], `<type>:<name>@<hash>`.
  ///
  /// Throws a usage error for an [arg] with no 12-hex `@<hash>`.
  SeenDraft _seenDraftOf(String arg) {
    final match = _seenDraft.firstMatch(arg);
    if (match == null) {
      usageException(
        '--yes needs each draft as <type>:<name>@<hash>, the hash from '
        'bases.doc of specstone get --json; got $arg.',
      );
    }
    return (name: match[1]!, hash: match[2]!);
  }
}
