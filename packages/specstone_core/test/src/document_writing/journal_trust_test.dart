import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:specstone_core/src/document_writing/move_doc.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/write_fixture.dart';

const _finish = 'document_writing/delete_doc_subtree/finish_interrupted_move';

const _noRun =
    'no Specstone run on this machine wrote it; '
    'check .specstone/trash/ and delete it to go on';

const _noHome =
    'cannot write .specstone/trash/journal.json: '
    'no home folder to record it in';

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
      .having((f) => f.exitStatus, 'exit', 73)
      .having((f) => f.file, 'file', MoveJournal.journalPath)
      .having((f) => f.message, 'message', message),
);

File _journalOf(Directory root) =>
    File('${root.path}/${MoveJournal.journalPath}');

void main() {
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
        _refusedWith(_noHome),
      );

      expect(hasDoc(root, story3), before);
      expect(Directory('${root.path}/.specstone/trash').existsSync(), isFalse);
      expect(Directory('${root.path}/h/.specstone').existsSync(), isFalse);
    });

    test('$_finish E10: the home check names a home folder that is $name '
        'before any prompt', () async {
      final root = await writeWriteProject();
      Directory('${root.path}/h').createSync();

      expect(
        () => MoveJournal.requireHomeFolder(home(root), root),
        _refusedWith(_noHome),
      );
    });
  }

  test('$_finish E10: a home folder behind a link into the project counts as '
      'none', () async {
    final root = await writeWriteProject();
    Directory('${root.path}/h').createSync();
    final outside = Directory.systemTemp.createTempSync('specstone_alias_');
    addTearDown(() => outside.deleteSync(recursive: true));
    final alias = Link('${outside.path}/home')..createSync('${root.path}/h');

    expect(
      () => MoveJournal.requireHomeFolder(Directory(alias.path), root),
      _refusedWith(_noHome),
    );
  }, skip: Platform.isWindows ? 'a link needs a privilege on Windows' : null);

  test('$_finish E10: an absolute home folder outside the project, even one '
      'not created yet, is a home', () async {
    final root = await writeWriteProject();
    final home = Directory('${testHome().path}/not/yet');

    MoveJournal.requireHomeFolder(home, root);
  });

  test('$_finish E08: a journal recorded under a home folder inside the '
      'project is not trusted', () async {
    final root = await writeWriteProject();
    final home = Directory('${root.path}/h')..createSync();
    final victim = _victim();
    final bytes = utf8.encode(
      jsonEncode(
        MoveJournal([
          WriteStep.unguarded(
            '../${victim.uri.pathSegments.last}',
            'overwritten',
          ),
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

  test('$_finish E08: a journal recorded under a relative home folder is not '
      'trusted', () async {
    final root = await writeWriteProject();
    final victim = _victim();
    writeJournal(root, [
      WriteStep.unguarded('../${victim.uri.pathSegments.last}', 'overwritten'),
    ]);

    expect(
      () => _runWrite(root, Directory('relative_home')),
      _refusedWith(_noRun),
    );
    expect(victim.readAsStringSync(), 'original');
  });
}
