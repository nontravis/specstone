import 'dart:io';

import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:test/test.dart';

import '../../specstone_core/test/helpers/check_fixture.dart';
import '../../specstone_core/test/helpers/write_fixture.dart' show writeJournal;
import 'helpers/built_cli.dart';

void main() {
  late String binary;

  setUpAll(() async {
    binary = await buildSpecstone();
  });

  test(
    'document_writing/delete_doc_subtree/finish_interrupted_move: a replay '
    'names a file edited since the stopped run on stderr and leaves it',
    () async {
      const edited = 'old text\nthe user added a line\n';
      final root = await writeCheckProject(extra: {'docs/notes.md': edited});
      writeJournal(root, [
        WriteStep(
          'docs/notes.md',
          'new text\n',
          before: textHashOf('old text\n'),
        ),
      ]);

      final result = await Process.run(binary, [
        'rename',
        'feature:login',
        '--to',
        'signin',
      ], workingDirectory: root.path);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        result.stderr,
        contains(
          'docs/notes.md changed since the stopped run; left as it is\n',
        ),
      );
      expect(File('${root.path}/docs/notes.md').readAsStringSync(), edited);
      expect(MoveJournal.pending(root), isFalse);
    },
  );
}
