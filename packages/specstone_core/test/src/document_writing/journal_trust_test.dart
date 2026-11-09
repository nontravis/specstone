import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:specstone_core/src/document_writing/journal_records.dart';
import 'package:specstone_core/src/document_writing/move_doc.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/write_fixture.dart';

const _finish = 'document_writing/delete_doc_subtree/finish_interrupted_move';

const _noRun =
    'no Specstone run on this machine wrote it; '
    'check .specstone/trash/ and delete it to go on';

/// Runs an empty write command on [root], which replays a pending journal
/// first, with the records under [home].
void _runWrite(Directory root, Directory? home) => WriteSession.run(
  (session) {},
  templates: TemplateResolver(),
  workingDirectory: root,
  homeDirectory: home,
);

/// Creates a file outside every project root, holding `original`.
File _victim() {
  final file = File(
    '${Directory.systemTemp.path}/specstone_victim_'
    '${DateTime.now().microsecondsSinceEpoch}.txt',
  )..writeAsStringSync('original');
  addTearDown(() {
    if (file.existsSync()) file.deleteSync();
  });
  return file;
}

Matcher _refusedWith(String message) => throwsA(
  isA<RenderFault>()
      .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
      .having((f) => f.file, 'file', MoveJournal.journalPath)
      .having((f) => f.message, 'message', message),
);

File _journalOf(Directory root) =>
    File('${root.path}/${MoveJournal.journalPath}');

void main() {
  test('$_finish E08: a journal no run recorded is refused before any step '
      'and the file it names outside the project stays', () async {
    final root = await writeWriteProject();
    final victim = _victim();
    writeJournal(root, [
      WriteStep('../${victim.uri.pathSegments.last}', 'overwritten'),
    ], recorded: false);

    expect(() => _runWrite(root, testHome()), _refusedWith(_noRun));

    expect(victim.readAsStringSync(), 'original');
    expect(_journalOf(root).existsSync(), isTrue);
  });

  test('$_finish E08: a migrate journal no run recorded is refused with '
      'output_not_writable, not migrate_pending', () async {
    final root = await writeWriteProject();
    writeJournal(root, [
      const CommitStep(message: 'm', paths: ['docs/x.md'], base: 'abc'),
    ], recorded: false);

    expect(() => _runWrite(root, testHome()), _refusedWith(_noRun));
  });

  test('$_finish E08: a journal whose digest differs from the recorded one '
      'is refused', () async {
    final root = await writeWriteProject();
    writeJournal(root, [const MoveStep('docs/$story3', 'docs/$story3.moved')]);
    _journalOf(root).writeAsStringSync(
      jsonEncode(
        const MoveJournal([MoveStep('docs/$story2', 'docs/$story2.moved')])
            .toJson(),
      ),
    );

    expect(() => _runWrite(root, testHome()), _refusedWith(_noRun));
    expect(hasDoc(root, story2), isTrue);
  });

  test('$_finish E08: a journal recorded for another project root is '
      'refused', () async {
    final root = await writeWriteProject();
    final other = await writeWriteProject();
    writeJournal(root, [const MoveStep('docs/$story3', 'docs/$story3.moved')]);
    final bytes = _journalOf(root).readAsBytesSync();
    _journalOf(other)
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);

    expect(() => _runWrite(other, testHome()), _refusedWith(_noRun));
  });

  test(
    '$_finish E08: a journal in a run with no home folder is refused',
    () async {
      final root = await writeWriteProject();
      writeJournal(root, [
        const MoveStep('docs/$story3', 'docs/$story3.moved'),
      ]);

      expect(() => _runWrite(root, null), _refusedWith(_noRun));
      expect(hasDoc(root, story3), isTrue);
    },
  );

  test('$_finish E08: a recorded journal whose step path leaves the project '
      'is refused and the file it names stays', () async {
    final root = await writeWriteProject();
    final victim = _victim();
    final path = '../${victim.uri.pathSegments.last}';
    writeJournal(root, [WriteStep(path, 'overwritten')]);

    expect(
      () => _runWrite(root, testHome()),
      _refusedWith(
        'its step path $path leaves the project and docs roots; '
        'check .specstone/trash/ and delete it to go on',
      ),
    );

    expect(victim.readAsStringSync(), 'original');
    expect(_journalOf(root).existsSync(), isTrue);
  });

  test('$_finish E08: a recorded journal whose step path is below .git is '
      'refused and nothing moves', () async {
    final root = await writeWriteProject();
    writeJournal(root, [
      const MoveStep('docs/$story3', 'docs/$story3.moved'),
      const CreateStep('.git/hooks/post-commit', 'echo pwned'),
    ]);

    expect(
      () => _runWrite(root, testHome()),
      _refusedWith(
        'its step path .git/hooks/post-commit leaves the project and docs '
        'roots; check .specstone/trash/ and delete it to go on',
      ),
    );

    expect(hasDoc(root, story3), isTrue);
    expect(Directory('${root.path}/.git').existsSync(), isFalse);
  });

  test('$_finish E08: a recorded journal whose step path runs through a link '
      'that leaves the roots is refused and the file stays', () async {
    final root = await writeWriteProject();
    final outside = Directory.systemTemp.createTempSync('specstone_outside_');
    addTearDown(() => outside.deleteSync(recursive: true));
    final victim = File('${outside.path}/victim.txt')
      ..writeAsStringSync('original');
    Link('${root.path}/docs/escape').createSync(outside.path);
    writeJournal(root, [const WriteStep('docs/escape/victim.txt', 'x')]);

    expect(
      () => _runWrite(root, testHome()),
      _refusedWith(
        'its step path docs/escape/victim.txt leaves the project and docs '
        'roots; check .specstone/trash/ and delete it to go on',
      ),
    );

    expect(victim.readAsStringSync(), 'original');
  }, skip: Platform.isWindows ? 'a link needs a privilege on Windows' : null);

  test('$_finish E08: a recorded journal inside the project replays and its '
      'record goes with the trash', () async {
    final root = await writeWriteProject();
    writeJournal(root, [const MoveStep('docs/$story3', 'docs/$story3.moved')]);
    final records = Directory('${testHome().path}/.specstone/journals');
    expect(records.listSync(), hasLength(1));

    _runWrite(root, testHome());

    expect(hasDoc(root, story3), isFalse);
    expect(hasDoc(root, '$story3.moved'), isTrue);
    expect(_journalOf(root).existsSync(), isFalse);
    expect(records.listSync(), isEmpty);
  });

  test(
    '$_finish E08: a recorded migrate journal still gets migrate_pending',
    () async {
      final root = await writeWriteProject();
      writeJournal(root, [
        const CommitStep(message: 'm', paths: ['docs/x.md'], base: 'abc'),
      ]);

      expect(
        () => _runWrite(root, testHome()),
        throwsA(
          isA<WriteFault>().having(
            (f) => f.code,
            'code',
            WriteFaultCode.migratePending,
          ),
        ),
      );
    },
  );

  test('$_finish E10: a run that writes a journal with no home folder is '
      'refused before its first change and writes no journal', () async {
    final root = await writeWriteProject();

    expect(
      () => WriteSession.run(
        (session) => answerRename(
          session,
          'user_story:login/reset_password',
          slug: 'recover_password',
        ),
        templates: TemplateResolver(),
        workingDirectory: root,
        homeDirectory: null,
      ),
      _refusedWith(
        'cannot write .specstone/trash/journal.json: '
        'no home folder to record it in',
      ),
    );

    expect(hasDoc(root, story3), isTrue);
    expect(Directory('${root.path}/.specstone/trash').existsSync(), isFalse);
  });

  for (final (name, home) in [
    ('relative', (Directory root) => Directory('relative_home')),
    ('inside the project', (Directory root) => Directory('${root.path}/h')),
    ('the project itself', (Directory root) => root),
  ]) {
    test('$_finish E10: a home folder that is $name counts as none, so a '
        'run that writes a journal is refused and writes nothing', () async {
      final root = await writeWriteProject();
      Directory('${root.path}/h').createSync();
      final before = hasDoc(root, story3);

      expect(
        () => WriteSession.run(
          (session) => answerRename(
            session,
            'user_story:login/reset_password',
            slug: 'recover_password',
          ),
          templates: TemplateResolver(),
          workingDirectory: root,
          homeDirectory: home(root),
        ),
        _refusedWith(
          'cannot write .specstone/trash/journal.json: '
          'no home folder to record it in',
        ),
      );

      expect(hasDoc(root, story3), before);
      expect(Directory('${root.path}/.specstone/trash').existsSync(), isFalse);
      expect(Directory('${root.path}/h/.specstone').existsSync(), isFalse);
    });
  }

  test('$_finish E08: a journal recorded under a home folder inside the '
      'project is not trusted', () async {
    final root = await writeWriteProject();
    final home = Directory('${root.path}/h')..createSync();
    final victim = _victim();
    final bytes = utf8.encode(
      jsonEncode(
        MoveJournal([
          WriteStep('../${victim.uri.pathSegments.last}', 'overwritten'),
        ]).toJson(),
      ),
    );
    _journalOf(root)
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    Directory('${home.path}/.specstone/journals').createSync(recursive: true);
    final key = sha256.convert(utf8.encode(root.resolveSymbolicLinksSync()));
    File('${home.path}/.specstone/journals/$key').writeAsStringSync(
      jsonEncode({
        'journal': sha256.convert(bytes).toString(),
        'agentFiles': <String>[],
      }),
    );

    expect(() => _runWrite(root, home), _refusedWith(_noRun));
    expect(victim.readAsStringSync(), 'original');
  });

  test('$_finish E10: a run that writes no journal is unaffected by a '
      'missing home folder', () async {
    final root = await writeWriteProject();

    _runWrite(root, null);

    expect(hasDoc(root, story3), isTrue);
  });

  test('$_finish E08: the record keeps the digest under a file named by the '
      'canonical project root', () async {
    final root = await writeWriteProject();
    final bytes = utf8.encode('{"steps":[]}');

    JournalRecords(testHome()).record(root, bytes);

    expect(JournalRecords(testHome()).holds(root, bytes), isTrue);
    expect(JournalRecords(testHome()).holds(root, utf8.encode('{}')), isFalse);
    JournalRecords(testHome()).clear(root);
    expect(JournalRecords(testHome()).holds(root, bytes), isFalse);
  });
}
