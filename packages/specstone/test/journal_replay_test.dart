import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/doc_model/doc_splice.dart'
    show baseHashOf, withKeyBlock;
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:test/test.dart';

import '../../specstone_core/test/helpers/check_fixture.dart';
import '../../specstone_core/test/helpers/posix_modes.dart'
    show unreadablePathSkipReason;
import '../../specstone_core/test/helpers/write_fixture.dart'
    show
        docFile,
        fr31,
        loginArch,
        readDoc,
        signupArch,
        story1,
        story3,
        testHome,
        writeJournal,
        writeProject,
        writeWriteProject;
import 'helpers/built_cli.dart';

void main() {
  late String binary;

  setUpAll(() async {
    binary = await buildSpecstone();
  });

  test('a replay names a file edited since the stopped run on stderr '
      'and leaves it', () async {
    const edited = 'old text\nthe user added a line\n';
    final root = await writeCheckProject(extra: {'docs/notes.md': edited});
    writeJournal(root, [
      WriteStep(
        'docs/notes.md',
        'new text\n',
        before: textHashOf('old text\n'),
      ),
    ]);

    final result = await runSpecstone(
      binary,
      ['rename', 'feature:login', '--to', 'signin'],
      workingDirectory: root.path,
      environment: {'HOME': testHome().path, 'USERPROFILE': testHome().path},
    );

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(
      result.stderr,
      contains('docs/notes.md changed since the stopped run; left as it is\n'),
    );
    expect(File('${root.path}/docs/notes.md').readAsStringSync(), edited);
    expect(MoveJournal.pending(root), isFalse);
  });

  group('a replay warning on a file edited since the stopped run', () {
    const line = 'docs/notes.md changed since the stopped run; left as it is';

    Future<ProcessResult> renameAfterStoppedRun(List<String> flags) async {
      final root = await writeCheckProject(
        extra: {'docs/notes.md': 'old text\nthe user added a line\n'},
      );
      writeJournal(root, [
        WriteStep(
          'docs/notes.md',
          'new text\n',
          before: textHashOf('old text\n'),
        ),
      ]);
      return runSpecstone(
        binary,
        ['rename', 'feature:login', '--to', 'signin', ...flags],
        workingDirectory: root.path,
        environment: {'HOME': testHome().path, 'USERPROFILE': testHome().path},
      );
    }

    test('joins the reply warnings under --json and leaves stderr '
        'empty', () async {
      final result = await renameAfterStoppedRun(['--json']);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final reply = jsonDecode(result.stdout as String) as Map<String, Object?>;
      expect(reply['warnings'], contains(line));
      expect(result.stderr, isEmpty);
    });

    test('prints as a prefixed warning line in text mode', () async {
      final result = await renameAfterStoppedRun([]);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stderr, contains('⚠️ WARNING: $line\n'));
    });

    test('stays in the fault reply when a later step of the same replay '
        'fails', () async {
      final root = await writeCheckProject(
        extra: {
          'docs/notes.md': 'old text\nthe user added a line\n',
          'docs/locked/a.md': 'kept\n',
        },
      );
      writeJournal(root, [
        WriteStep(
          'docs/notes.md',
          'new text\n',
          before: textHashOf('old text\n'),
        ),
        const MoveStep('docs/locked', '.specstone/trash/files/docs/locked'),
      ]);
      final locked = Directory('${root.path}/docs/locked');
      Process.runSync('chmod', ['555', locked.path]);
      addTearDown(() => Process.runSync('chmod', ['755', locked.path]));

      final result = await runSpecstone(
        binary,
        ['rename', 'feature:login', '--to', 'signin', '--json'],
        workingDirectory: root.path,
        environment: {'HOME': testHome().path, 'USERPROFILE': testHome().path},
      );

      expect(result.exitCode, isNot(0), reason: '${result.stderr}');
      final fault = jsonDecode(result.stderr as String) as Map<String, Object?>;
      expect(fault['warnings'], contains(line));
    }, skip: unreadablePathSkipReason() ?? false);
  });

  test('the next '
      'write command finishes a stopped batch and keeps a doc edited after the '
      'stop', () async {
    final twin = await writeWriteProject();
    final root = await writeWriteProject();
    final environment = {
      'HOME': testHome().path,
      'USERPROFILE': testHome().path,
    };
    final read = await runSpecstone(
      binary,
      ['get', story1, story3, fr31],
      workingDirectory: twin.path,
      environment: environment,
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
    final written = await runSpecstone(
      binary,
      ['set', '--batch', batch.path],
      workingDirectory: twin.path,
      environment: environment,
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

  test('a --remove-task run stopped after its journal and '
      'before its last doc is finished by the next write command', () async {
    const docs = [loginArch, signupArch];
    final files = {
      for (final docPath in docs)
        'docs/$docPath': withKeyBlock(
          writeProject['docs/$docPath']!,
          'tasks',
          'tasks:\n  - ENG-42\n  - ENG-50\n',
        ),
    };
    final twin = await writeWriteProject(extra: files);
    final root = await writeWriteProject(extra: files);
    final environment = {
      'HOME': testHome().path,
      'USERPROFILE': testHome().path,
    };
    final removed = await runSpecstone(
      binary,
      ['set', '--remove-task', 'ENG-42'],
      workingDirectory: twin.path,
      environment: environment,
    );
    expect(removed.exitCode, 0, reason: '${removed.stderr}');
    writeJournal(root, [
      for (final docPath in docs)
        WriteStep(
          'docs/$docPath',
          readDoc(twin, docPath),
          before: textHashOf(readDoc(root, docPath)),
        ),
    ]);
    docFile(root, loginArch).writeAsStringSync(readDoc(twin, loginArch));

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
    for (final docPath in docs) {
      expect(readDoc(root, docPath), readDoc(twin, docPath), reason: docPath);
      expect(readDoc(root, docPath), isNot(contains('ENG-42')));
    }
    expect(MoveJournal.pending(root), isFalse);
  });
}
