import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:test/test.dart';

import '../../specstone_core/test/helpers/write_fixture.dart';
import 'helpers/write_runner.dart';

void main() {
  test('document_writing/delete_doc_subtree/finish_interrupted_move E08: a '
      'write command refuses a journal from a clone with exit 73 and leaves '
      'the file it names', () async {
    final root = await writeWriteProject();
    final victim = File(
      '${Directory.systemTemp.path}/specstone_victim_cli_'
      '${DateTime.now().microsecondsSinceEpoch}.txt',
    )..writeAsStringSync('original');
    addTearDown(() {
      if (victim.existsSync()) victim.deleteSync();
    });
    writeJournal(root, [
      WriteStep('../${victim.uri.pathSegments.last}', 'overwritten'),
    ], recorded: false);
    final (:runner, :out, :err) = writeRunner(root);

    final status = await runner.run([
      'rename',
      'user_story:login/reset_password',
      '--to',
      'recover_account',
      '--json',
    ]);

    expect(status, 73);
    expect(out.toString(), isEmpty);
    final error = (jsonDecode(err.toString()) as Map)['error'] as Map;
    expect(error['code'], 'output_not_writable');
    expect(error['file'], MoveJournal.journalPath);
    expect(
      error['message'],
      'no Specstone run on this machine wrote it; '
      'check .specstone/trash/ and delete it to go on',
    );
    expect(victim.readAsStringSync(), 'original');
    expect(hasDoc(root, story3), isTrue);
  });

  test(
    'document_writing/delete_doc_subtree/finish_interrupted_move: a '
    'journal this machine recorded is finished by the next write command',
    () async {
      final root = await writeWriteProject();
      writeJournal(root, [
        const MoveStep('docs/$story3', 'docs/$story3.moved'),
      ]);
      final (:runner, :out, :err) = writeRunner(root);

      final status = await runner.run([
        'rename',
        'user_story:login/sign_out',
        '--to',
        'log_out',
      ]);

      expect(status, 0, reason: err.toString());
      expect(hasDoc(root, '$story3.moved'), isTrue);
    },
  );
}
