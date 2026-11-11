import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:specstone_core/src/canonical_path.dart';
import 'package:specstone_core/src/document_writing/journal_bounds.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/owner_confirmation.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/setup_migration/migrate_run.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart';

const _finish = 'document_writing/delete_doc_subtree/finish_interrupted_move';

final String? _linksUnavailable = Platform.isWindows
    ? 'a link needs a privilege on Windows'
    : null;

/// What Windows answered on CI for a file deleted while it was resolved.
const _deletedAlias = r'C:\$Extend\$Deleted\002200000014DCAD7A7FE315';

/// How many refused rounds a churn failure lists.
const _refusalsShown = 5;

/// Returns every entry under [root] as text: a file by its bytes, a link by
/// its target, a folder by its name; nothing is followed.
Map<String, String> _snapshot(Directory root) {
  final prefix = '${root.path}${Platform.pathSeparator}';
  return {
    for (final entity in root.listSync(recursive: true, followLinks: false))
      entity.path.substring(prefix.length): switch (entity) {
        File() => 'file:${base64Encode(entity.readAsBytesSync())}',
        Link() => 'link:${entity.targetSync()}',
        _ => 'dir',
      },
  };
}

Matcher _leaves(String path) => throwsA(
  isA<RenderFault>()
      .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
      .having((f) => f.exitStatus, 'exit', 73)
      .having((f) => f.file, 'file', MoveJournal.journalPath)
      .having(
        (f) => f.message,
        'message',
        'its step path $path leaves the project and docs roots; '
            'check .specstone/trash/ and delete it to go on',
      ),
);

Matcher _leadsOutside(String path) => throwsA(
  isA<RenderFault>()
      .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
      .having((f) => f.exitStatus, 'exit', 73)
      .having((f) => f.file, 'file', MoveJournal.journalPath)
      .having(
        (f) => f.message,
        'message',
        '$path leads outside the project and docs roots; remove the link on '
            'its way in .specstone/ to go on',
      ),
);

void main() {
  group('$_finish E08: JournalBounds', () {
    late Directory root;
    late Directory outside;
    late JournalBounds bounds;

    setUp(() async {
      root = await writeWriteProject();
      outside = await writeTree({'victim.txt': 'mine\n'});
      if (_linksUnavailable == null) {
        Link('${root.path}/docs/out').createSync(outside.path);
      }
      bounds = JournalBounds(root, [
        root.resolveSymbolicLinksSync(),
        Directory('${root.path}/docs').resolveSymbolicLinksSync(),
      ]);
    });

    for (final path in [
      'docs/prds/new/x.md',
      'docs/$story1',
      '.specstone/trash/files/x',
      'docs/.gitignore',
      'docs/.github/x',
    ]) {
      test('holds $path', () {
        expect(bounds.holds(path), isTrue);
      });
    }

    for (final path in [
      '',
      '../outside.md',
      'docs/../../outside.md',
      'docs/..',
      'docs/.',
      'docs//x.md',
      '/etc/x',
      'C:/x',
      r'docs\x.md',
      '.git/config',
      '.GIT/config',
      'docs/.git/hooks/pre-commit',
      'git~1/config',
      '.git./config',
      '.git /config',
      '.git:stream/config',
      r'.git::$INDEX_ALLOCATION/hooks/x',
      r'docs/.Git::$INDEX_ALLOCATION/x',
    ]) {
      test('refuses "$path"', () {
        expect(bounds.holds(path), isFalse);
      });
    }

    test('refuses a path behind a link that leaves the roots', () {
      expect(bounds.holds('docs/out/victim.txt'), isFalse);
      expect(bounds.holds('docs/out/new/deeper.txt'), isFalse);
    }, skip: _linksUnavailable);

    test('holds the link itself, which a step moves as itself', () {
      expect(bounds.holds('docs/out'), isTrue);
    }, skip: _linksUnavailable);
  });

  group(
    '$_finish E08: JournalBounds on a folder that vanishes mid-resolve',
    () {
      const churnFor = Duration(seconds: 2);

      test('a folder another isolate makes and deletes is missing or there, '
          'never unresolvable', () async {
        final root = await writeTree({'keep.txt': ''});
        final real = root.resolveSymbolicLinksSync();
        final folder = '$real/side-folder';
        final churn = Isolate.run(() {
          final dir = Directory(folder);
          final watch = Stopwatch()..start();
          while (watch.elapsed < churnFor) {
            try {
              dir
                ..createSync()
                ..deleteSync();
            } on FileSystemException {
              // A virus scanner may hold the folder on Windows; only the
              // judgments below are counted.
            }
          }
        });

        var refused = 0;
        var rounds = 0;
        final firstRefusals = <String>[];
        final watch = Stopwatch()..start();
        try {
          while (watch.elapsed < churnFor) {
            rounds++;
            final answers = <String>[];
            String recordAnswer(String asked) {
              try {
                final answer = realPathOnDisk(asked);
                answers.add(answer.isEmpty ? '(empty)' : answer);
                return answer;
              } on FileSystemException catch (error) {
                answers.add('error ${error.osError?.errorCode} at $asked');
                rethrow;
              }
            }

            // A fresh instance each round, since one remembers the folders
            // asked.
            final bounds = JournalBounds(root, [real], resolve: recordAnswer);
            if (bounds.holds('side-folder/x.md')) continue;
            refused++;
            if (firstRefusals.length < _refusalsShown) {
              firstRefusals.add(answers.join(', then '));
            }
          }
        } finally {
          // The churn must stop before the test deletes its folder.
          await churn;
        }

        expect(rounds, greaterThan(0));
        expect(
          refused,
          0,
          reason:
              '$refused of $rounds judgments refused; the resolves of the '
              'first: ${firstRefusals.join('; ')}',
        );
      });
    },
  );

  group('$_finish E08: JournalBounds when the resolve answers for a folder '
      'deleted meanwhile', () {
    late Directory root;
    late String real;
    late String folder;

    setUp(() async {
      root = await writeTree({'side-folder/keep.txt': ''});
      real = root.resolveSymbolicLinksSync();
      folder = '${root.path}${Platform.pathSeparator}side-folder';
    });

    test('an empty answer for a folder gone since counts as missing', () {
      String deleteThenAnswerEmpty(String asked) {
        if (asked != folder) return realPathOnDisk(asked);
        Directory(asked).deleteSync(recursive: true);
        return '';
      }

      final bounds = JournalBounds(root, [
        real,
      ], resolve: deleteThenAnswerEmpty);

      expect(bounds.holds('side-folder/x.md'), isTrue);
    });

    test('an NTFS deleted-file answer for a folder gone since counts as '
        'missing', () {
      String deleteThenAnswerAlias(String asked) {
        if (asked != folder) return realPathOnDisk(asked);
        Directory(asked).deleteSync(recursive: true);
        return _deletedAlias;
      }

      final bounds = JournalBounds(root, [
        real,
      ], resolve: deleteThenAnswerAlias);

      expect(bounds.holds('side-folder/x.md'), isTrue);
    });

    test('a failure for a folder gone since counts as missing, whatever its '
        'code', () {
      String deleteThenFail(String asked) {
        if (asked != folder) return realPathOnDisk(asked);
        Directory(asked).deleteSync(recursive: true);
        throw FileSystemException('', asked, const OSError('denied', 5));
      }

      final bounds = JournalBounds(root, [real], resolve: deleteThenFail);

      expect(bounds.holds('side-folder/x.md'), isTrue);
    });

    test('an NTFS deleted-file answer for a folder made again since '
        'resolves the folder again', () {
      var answered = false;
      String answerAliasOnce(String asked) {
        if (asked != folder || answered) return realPathOnDisk(asked);
        answered = true;
        return _deletedAlias;
      }

      final bounds = JournalBounds(root, [real], resolve: answerAliasOnce);

      expect(bounds.holds('side-folder/x.md'), isTrue);
    });

    test('an NTFS deleted-file answer for a folder that stays refuses', () {
      String answerAlias(String asked) =>
          asked == folder ? _deletedAlias : realPathOnDisk(asked);

      final bounds = JournalBounds(root, [real], resolve: answerAlias);

      expect(bounds.holds('side-folder/x.md'), isFalse);
    });
  });

  group('$_finish E08: a refused replay changes nothing', () {
    late Directory root;

    setUp(() async {
      root = await writeWriteProject();
    });

    JournalTarget target() =>
        JournalTarget.of(openProject(root), homeDirectory: testHome());

    for (final path in [
      '../outside.md',
      'docs/../../outside.md',
      '.git/config',
      'docs/.git/hooks/pre-commit',
      '.git:stream/config',
      r'docs/.git::$INDEX_ALLOCATION/x',
    ]) {
      test('a recorded step path $path', () {
        writeJournal(root, [
          const MoveStep('docs/$story3', 'docs/$story3.moved'),
          CreateStep(path, 'payload\n'),
        ]);
        final before = _snapshot(root);

        expect(() => MoveJournal.replay(target()), _leaves(path));

        expect(_snapshot(root), before);
      });
    }

    test('a recorded step path behind a link out of the project', () async {
      final outside = await writeTree({'victim.txt': 'mine\n'});
      Link('${root.path}/docs/out').createSync(outside.path);
      writeJournal(root, [
        const MoveStep('docs/$story3', 'docs/$story3.moved'),
        const WriteStep.unguarded('docs/out/victim.txt', 'payload\n'),
      ]);
      final before = _snapshot(root);
      final outsideBefore = _snapshot(outside);

      expect(
        () => MoveJournal.replay(target()),
        _leaves('docs/out/victim.txt'),
      );

      expect(_snapshot(root), before);
      expect(_snapshot(outside), outsideBefore);
    }, skip: _linksUnavailable);
  });

  group('$_finish E08: each path is checked where it is used', () {
    test('a link an earlier step moves into place is refused at the next '
        'step, and the folder behind it keeps its text', () async {
      final root = await writeWriteProject();
      final outside = await writeTree({'victim.txt': 'mine\n'});
      Link('${root.path}/docs/lnk').createSync(outside.path);
      writeJournal(root, [
        const MoveStep('docs/lnk', 'docs/escape'),
        const WriteStep.unguarded('docs/escape/victim.txt', 'payload\n'),
      ]);
      final outsideBefore = _snapshot(outside);

      expect(
        () => MoveJournal.replay(
          JournalTarget.of(openProject(root), homeDirectory: testHome()),
        ),
        _leaves('docs/escape/victim.txt'),
      );

      expect(_snapshot(outside), outsideBefore);
      expect(File('${outside.path}/victim.txt').readAsStringSync(), 'mine\n');
    }, skip: _linksUnavailable);

    test('a link an earlier step moves into place under the code root is '
        'refused at the code file step', () async {
      final base = await writeTree({
        'proj/.specstone/config.yaml':
            '${writeProject['.specstone/config.yaml']!}code_root: src\n',
        'proj/docs/prds/PROJECT.md': 'x\n',
        'proj/src/a.dart': '// old\n',
      });
      final outside = await writeTree({'victim.dart': '// mine\n'});
      Link('${base.path}/proj/src/lnk').createSync(outside.path);
      final project = Directory('${base.path}/proj');
      writeJournal(project, [
        const MoveStep('src/lnk', 'src/escape'),
        const WriteStep.unguarded('src/escape/victim.dart', '// payload\n'),
      ]);
      final outsideBefore = _snapshot(outside);

      expect(
        () => MoveJournal.replay(
          JournalTarget.of(openProject(project), homeDirectory: testHome()),
        ),
        _leaves('src/escape/victim.dart'),
      );

      expect(_snapshot(outside), outsideBefore);
    }, skip: _linksUnavailable);

    test('a .specstone link out of the project refuses a replay before it '
        'removes the trash folder behind it', () async {
      final base = await writeTree({
        'x/trash/keep.txt': 'mine\n',
        'proj/docs/a.md': '# a\n',
      });
      Link('${base.path}/proj/.specstone').createSync('../x');
      final project = Directory('${base.path}/proj');
      final before = _snapshot(base);

      expect(
        () => MoveJournal.replay(
          JournalTarget(
            projectRoot: project,
            docsRoot: Directory('${project.path}/docs'),
            homeDirectory: testHome(),
          ),
        ),
        _leadsOutside(MoveJournal.journalPath),
      );

      expect(_snapshot(base), before);
    }, skip: _linksUnavailable);

    group('a .specstone/trash link out of the project', () {
      late Directory root;
      late Directory outside;

      setUp(() async {
        root = await writeWriteProject();
        outside = await writeTree({'keep.txt': 'mine\n', 'stage/x.md': 'x\n'});
        // Builds the index first, so the snapshots below cover it too.
        writeIn(root, (session) => session.project);
        Link('${root.path}/.specstone/trash').createSync(outside.path);
      });

      void expectRefusedUnchanged(void Function() run) {
        final rootBefore = _snapshot(root);
        final outsideBefore = _snapshot(outside);

        expect(run, _leadsOutside(MoveJournal.journalPath));

        expect(_snapshot(root), rootBefore);
        expect(_snapshot(outside), outsideBefore);
      }

      test('is refused by a replay', () {
        expectRefusedUnchanged(
          () => MoveJournal.replay(
            JournalTarget.of(openProject(root), homeDirectory: testHome()),
          ),
        );
      });

      test('is refused by a write command', () {
        expectRefusedUnchanged(
          () => writeIn(root, (session) => session.project),
        );
      });

      test('is refused by a bare migrate', () {
        expectRefusedUnchanged(
          () => runMigrate(
            MigrateRequest(
              workingDirectory: root,
              homeDirectory: testHome(),
              templates: TemplateResolver(),
              dryRun: false,
              confirmation: OwnerConfirmation.prompt,
              readLine: () => throw StateError('must not ask'),
              out: StringBuffer(),
            ),
          ),
        );
      });

      test('is refused by a run, before the journal is written', () {
        expectRefusedUnchanged(
          () => const MoveJournal(
            [MoveStep('docs/$story3', 'docs/$story3.moved')],
          ).run(JournalTarget.of(openProject(root), homeDirectory: testHome())),
        );
      });
    }, skip: _linksUnavailable);

    test('a run refuses a step path outside the project before its first '
        'change, and writes no journal', () async {
      final root = await writeWriteProject();
      final outside = await writeTree({'victim.txt': 'mine\n'});
      writeIn(root, (session) => session.project);
      final before = _snapshot(root);
      final outsideBefore = _snapshot(outside);
      final victim =
          '../${outside.uri.pathSegments.lastWhere((s) => s.isNotEmpty)}'
          '/victim.txt';

      expect(
        () => MoveJournal([
          const MoveStep('docs/$story3', 'docs/$story3.moved'),
          WriteStep.unguarded(victim, 'payload\n'),
        ]).run(JournalTarget.of(openProject(root), homeDirectory: testHome())),
        _leaves(victim),
      );

      expect(_snapshot(root), before);
      expect(_snapshot(outside), outsideBefore);
    });

    test('a run refuses an agent file outside the project even when its '
        'target lists it', () async {
      final root = await writeWriteProject();
      final outside = await writeTree({'CLAUDE.md': 'Owner\n'});
      writeIn(root, (session) => session.project);
      final before = _snapshot(root);
      final outsideBefore = _snapshot(outside);
      final folder = outside.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      final path = '../$folder/CLAUDE.md';
      final project = openProject(root);

      expect(
        () => MoveJournal([WriteStep.unguarded(path, 'Owner\nblock\n')]).run(
          JournalTarget(
            projectRoot: project.projectRoot,
            docsRoot: project.docsRoot,
            homeDirectory: testHome(),
            agentFiles: {'${outside.resolveSymbolicLinksSync()}/CLAUDE.md'},
          ),
        ),
        _leaves(path),
      );

      expect(_snapshot(root), before);
      expect(_snapshot(outside), outsideBefore);
    });

    test('a run refuses before it creates anything when .specstone is a link '
        'out of the project', () async {
      final base = await writeTree({
        'x/keep.txt': 'mine\n',
        'proj/docs/a.md': '# a\n',
      });
      Link('${base.path}/proj/.specstone').createSync('../x');
      final project = Directory('${base.path}/proj');
      final before = _snapshot(base);

      expect(
        () => const MoveJournal([MoveStep('docs/a.md', 'docs/b.md')]).run(
          JournalTarget(
            projectRoot: project,
            docsRoot: Directory('${project.path}/docs'),
            homeDirectory: testHome(),
          ),
        ),
        _leadsOutside('.specstone/.gitignore'),
      );

      expect(_snapshot(base), before);
    }, skip: _linksUnavailable);
  });
}
