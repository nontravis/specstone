// Test names carry the long FR/INV tags the plan gives them.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/document_writing/owner_confirmation.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:test/test.dart';

void main() {
  test('f02/us03/s7, f02/us03/fr01/e04, dw-s03/inv12, ms-r11: neither a terminal nor --yes is owner_terminal_required, exit 77, naming both ways', () {
    final missing = OwnerConfirmation.of(yes: false, interactive: false);
    expect(missing, OwnerConfirmation.missing);
    expect(
      () => missing.refuseIfMissing('approve runs only'),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.ownerTerminalRequired)
            .having((f) => f.exitStatus, 'exitStatus', 77)
            .having(
              (f) => f.message,
              'message',
              "approve runs only at an interactive terminal, or with --yes after the Owner's ok in the chat",
            ),
      ),
    );
  });

  test('ms-r11: a terminal prompts, --yes confirms with no prompt and wins over a terminal', () {
    final terminal = OwnerConfirmation.of(yes: false, interactive: true);
    expect(terminal, OwnerConfirmation.prompt);
    expect(terminal.prompts, isTrue);
    terminal.refuseIfMissing('m'); // returns
    for (final interactive in [false, true]) {
      final yes = OwnerConfirmation.of(yes: true, interactive: interactive);
      expect(yes, OwnerConfirmation.given);
      expect(yes.prompts, isFalse);
      yes.refuseIfMissing('m'); // returns
    }
  });
}
