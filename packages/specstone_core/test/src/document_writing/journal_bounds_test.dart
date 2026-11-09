import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/document_writing/journal_bounds.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/owner_confirmation.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/setup_migration/migrate_run.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart';

const _finish = 'document_writing/delete_doc_subtree/finish_interrupted_move';

final String? _linksUnavailable = Platform.isWindows
    ? 'a link needs a privilege on Windows'
    : null;

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
      .having((f) => f.file, 'file', MoveJournal.journalPath)
      .having(
        (f) => f.message,
        'message',
        'its step path $path leaves the project and docs roots; '
            'check .specstone/trash/ and delete it to go on',
      ),
);

void main() {
  group('$_finish: JournalBounds', () {
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

  group('$_finish: a refused replay changes nothing', () {
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
        const WriteStep('docs/out/victim.txt', 'payload\n'),
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

  group('$_finish: each path is checked where it is used', () {
    test('a link an earlier step moves into place is refused at the next '
        'step, and the folder behind it keeps its text', () async {
      final root = await writeWriteProject();
      final outside = await writeTree({'victim.txt': 'mine\n'});
      Link('${root.path}/docs/lnk').createSync(outside.path);
      writeJournal(root, [
        const MoveStep('docs/lnk', 'docs/escape'),
        const WriteStep('docs/escape/victim.txt', 'payload\n'),
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
        _leaves(MoveJournal.journalPath),
      );

      expect(_snapshot(base), before);
    }, skip: _linksUnavailable);

    test('a bare migrate over a committed .specstone link leaves the folder '
        'behind it alone and refuses with exit 73', () async {
      final base = await writeTree({
        'x/config.yaml': shippedPinsConfig(),
        'x/trash/keep.txt': 'mine\n',
        'proj/docs/a.md': '# a\n',
      });
      Link('${base.path}/proj/.specstone').createSync('../x');
      final before = _snapshot(base);
      final out = StringBuffer();

      Object? caught;
      try {
        runMigrate(
          MigrateRequest(
            workingDirectory: Directory('${base.path}/proj'),
            homeDirectory: testHome(),
            templates: TemplateResolver(),
            dryRun: false,
            confirmation: OwnerConfirmation.prompt,
            readLine: () => throw StateError('must not ask'),
            out: out,
          ),
        );
      } on RenderFault catch (error) {
        caught = error;
      }

      expect(caught, isA<RenderFault>());
      final fault = caught! as RenderFault;
      expect(fault.code, RenderFaultCode.outputNotWritable);
      expect(fault.file, MoveJournal.journalPath);
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

        expect(run, _leaves(MoveJournal.journalPath));

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
    }, skip: _linksUnavailable);

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
        _leaves('.specstone/.gitignore'),
      );

      expect(_snapshot(base), before);
    }, skip: _linksUnavailable);
  });
}
