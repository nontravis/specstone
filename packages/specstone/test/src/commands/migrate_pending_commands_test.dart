import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/write_fixture.dart';
import '../../helpers/write_runner.dart';

const _message =
    'a migration is unfinished; run specstone migrate at an interactive '
    "terminal, or with --yes after the Owner's ok in the chat, to finish it, "
    'then run the command again';

void main() {
  const commands = {
    'approve': ['approve', 'feature:signup'],
    'delete': ['delete', 'fr:login/reset_password/expire_reset_link'],
    'reorder': ['reorder', 'login/reset_password', '--to', '1'],
    'rename': ['rename', 'login/reset_password', '--to', 'recover_account'],
    'move': ['move', 'user_story:login/reset_password', '--under', 'signup'],
  };

  for (final MapEntry(key: name, value: args) in commands.entries) {
    test('$name refuses a pending migrate journal with exit 75 and writes '
        'nothing', () async {
      final root = await writeWriteProject();
      writeJournal(root, [
        const MoveStep(
          'docs/prds/personas/buyer',
          'docs/prds/personas/shopper',
        ),
        const CommitStep(
          message: 'move',
          paths: ['docs/prds/personas'],
          base: '0000000',
        ),
      ]);
      final before = treeBytes(root)
        ..removeWhere((path, _) => !path.startsWith('docs/'));
      final (:runner, :out, :err) = writeRunner(
        root,
        console: FakeConsole(
          stdinIsTerminal: true,
          stdoutIsTerminal: true,
          answers: ['y', 'y'],
        ),
      );

      expect(await runner.run(args), 75);

      expect(err.toString(), contains(_message));
      final after = treeBytes(root)
        ..removeWhere((path, _) => !path.startsWith('docs/'));
      expect(after.keys, before.keys);
      for (final MapEntry(:key, :value) in before.entries) {
        expect(after[key], value, reason: key);
      }
    });
  }
}
