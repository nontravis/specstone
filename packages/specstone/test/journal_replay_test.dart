import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/doc_model/doc_splice.dart' show baseHashOf;
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:test/test.dart';

import '../../specstone_core/test/helpers/check_fixture.dart';
import '../../specstone_core/test/helpers/write_fixture.dart'
    show
        docFile,
        fr31,
        readDoc,
        story1,
        story3,
        testHome,
        writeJournal,
        writeWriteProject;
import 'helpers/built_cli.dart';

void main() {
  late String binary;

  setUpAll(() async {
    binary = await buildSpecstone();
  });

  test(
    'a replay '
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

      final result = await Process.run(
        binary,
        ['rename', 'feature:login', '--to', 'signin'],
        workingDirectory: root.path,
        environment: {'HOME': testHome().path, 'USERPROFILE': testHome().path},
      );

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

  test('E14: the next '
      'write command finishes a stopped batch and keeps a doc edited after the '
      'stop', () async {
    final twin = await writeWriteProject();
    final root = await writeWriteProject();
    final environment = {
      'HOME': testHome().path,
      'USERPROFILE': testHome().path,
    };
    // The CLI writes UTF-8; Process.run decodes with the system code page by
    // default, which turns the `·` of a naming line into two characters on
    // Windows, so the batch file would hold naming lines with no base.
    final read = await Process.run(
      binary,
      ['get', story1, story3, fr31],
      workingDirectory: twin.path,
      environment: environment,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    final folder = await Directory.systemTemp.createTemp('specstone_batch_');
    addTearDown(() => folder.delete(recursive: true));
    final batch = File('${folder.path}/batch.md')
      ..writeAsStringSync(
        (read.stdout as String)
            .replaceFirst('Sign in with an email.', 'Sign in with a passkey.')
            .replaceFirst('Reset a password.', 'Reset the password.')
            .replaceFirst('send a link', 'send a reset link'),
      );
    final written = await Process.run(
      binary,
      ['set', '--batch', batch.path],
      workingDirectory: twin.path,
      environment: environment,
      stderrEncoding: utf8,
    );
    expect(written.exitCode, 0, reason: '${written.stderr}');
    const docs = [story1, story3, fr31];
    writeJournal(root, [
      for (final docPath in docs)
        WriteStep(
          'docs/$docPath',
          readDoc(twin, docPath),
          before: textHashOf(readDoc(root, docPath)),
        ),
    ]);
    docFile(root, story1).writeAsStringSync(readDoc(twin, story1));
    final edited = readDoc(
      root,
      fr31,
    ).replaceFirst('send a link', 'send a link by mail');
    docFile(root, fr31).writeAsStringSync(edited);

    final next = await Process.start(
      binary,
      [
        'set',
        'user_story:login/sign_out#use_case',
        '--base',
        baseHashOf('\nSign out.\n'),
      ],
      workingDirectory: root.path,
      environment: environment,
    );
    next.stdin.write('Sign out everywhere.\n');
    await next.stdin.close();
    final stderr = await next.stderr.transform(utf8.decoder).join();
    await next.stdout.drain<void>();

    expect(await next.exitCode, 0, reason: stderr);
    expect(readDoc(root, story1), readDoc(twin, story1));
    expect(readDoc(root, story3), readDoc(twin, story3));
    expect(readDoc(root, fr31), edited);
    expect(MoveJournal.pending(root), isFalse);
  });
}
