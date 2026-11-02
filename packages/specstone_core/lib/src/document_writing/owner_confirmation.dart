import 'package:specstone_core/src/document_writing/write_fault.dart';

/// Names the two ways the Owner confirms a write only the Owner may make.
///
/// The chat way is the agent running `--yes` after the Owner's `ok`.
const ownerConfirmationWays =
    "at an interactive terminal, or with --yes after the Owner's ok in the "
    'chat';

/// How the Owner confirms a write that only the Owner may make.
enum OwnerConfirmation {
  /// Stdin and stdout are an interactive terminal: the command asks first.
  prompt,

  /// `--yes`: the Owner's ok came before the call, in Claude Code.
  given,

  /// Neither way: the write refuses.
  missing;

  /// Returns the confirmation of a call; [yes] (`--yes`) wins over a terminal.
  ///
  /// - [interactive]: whether stdin and stdout are both terminals.
  factory of({required bool yes, required bool interactive}) => yes
      ? .given
      : interactive
      ? .prompt
      : .missing;

  /// Whether the command asks the Owner at the terminal before it writes.
  bool get prompts => this == .prompt;

  /// Refuses when the Owner can confirm neither way.
  ///
  /// Throws [WriteFault] `owner_terminal_required` for [missing]; its message
  /// is [lead] followed by the two ways the Owner confirms.
  void refuseIfMissing(String lead) {
    if (this != .missing) return;
    throw WriteFault(
      WriteFaultCode.ownerTerminalRequired,
      '$lead $ownerConfirmationWays',
    );
  }
}
