import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/document_writing/approve_drafts.dart';
import 'package:specstone_core/src/document_writing/delete_doc.dart';
import 'package:specstone_core/src/document_writing/home_record.dart';
import 'package:specstone_core/src/document_writing/move_doc.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/new_doc.dart';
import 'package:specstone_core/src/document_writing/owner_confirmation.dart';
import 'package:specstone_core/src/document_writing/root_trust.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:test/test.dart';

import '../../helpers/git_repo.dart';
import '../../helpers/relative_link.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart';

final String? _linksUnavailable = Platform.isWindows
    ? 'a link needs a privilege on Windows'
    : null;

const _cloneTemplate = 'path: "rules/{slug}.md"\n';

/// Writes a clone whose committed `docs` link leads to the sibling folder
/// `ext/`, which holds the docs; the clone's own template sets the path of a
/// persona to `rules/{slug}.md`.
Future<({Directory base, Directory clone, Directory ext})>
_fallThroughClone() async {
  final base = await writeTree({
    for (final MapEntry(:key, :value) in writeProject.entries)
      if (key.startsWith('docs/'))
        'ext/${key.substring(5)}': value
      else
        'src/clone/$key': value,
    'src/clone/.specstone/templates/persona.yaml': _cloneTemplate,
  });
  createRelativeLink('${base.path}/src/clone/docs', '../../ext');
  return (
    base: base,
    clone: Directory('${base.path}/src/clone'),
    ext: Directory('${base.path}/ext'),
  );
}

/// Writes another project of the user, `victim/`, and a clone whose `docs`
/// link names the docs of that project.
Future<({Directory base, Directory clone, Directory victim})>
_linkedClone() async {
  final base = await writeTree({
    for (final MapEntry(:key, :value) in writeProject.entries)
      'victim/$key': value,
    'clone/keep.txt': '',
  });
  createRelativeLink('${base.path}/clone/docs', '../victim/docs');
  return (
    base: base,
    clone: Directory('${base.path}/clone'),
    victim: Directory('${base.path}/victim'),
  );
}

/// Records the trust of the project [folder] holds, as the Owner's `trust`
/// does, under [testHome].
void _trust(Directory folder) =>
    RootTrust.locate(folder, homeDirectory: testHome()).record();

/// Deletes the draft `lock_after_failures`, which no doc links to and the
/// Owner need not confirm.
ReadAnswer _deleteDraft(WriteSession session) => answerDelete(
  session,
  const ['fr:login/email_login/lock_after_failures'],
  confirmation: OwnerConfirmation.missing,
  readLine: () => null,
  prompts: StringBuffer(),
);

Matcher _refusesOutside(String path) => throwsA(
  isA<RenderFault>()
      .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
      .having((f) => f.exitStatus, 'exit', 73)
      .having((f) => f.file, 'file', path)
      .having(
        (f) => f.message,
        'message',
        allOf(
          startsWith('cannot write $path: '),
          endsWith('run specstone trust at a terminal to allow it'),
        ),
      ),
);

/// Makes [project] a git repository holding its files, then adds one draft
/// that no commit holds, so `approve` asks git to pair it with a moved doc.
void _gitWithUntrackedDraft(Directory project) {
  expect(git(project, ['init', '-q']).exitCode, 0);
  commitAll(project, 'docs');
  File('${project.path}/docs/prds/personas/y/PERSONA.md')
    ..createSync(recursive: true)
    ..writeAsStringSync('---\ndraft: true\n---\n\n# Y\n');
}

final RegExp _looseObjectPath = RegExp(r'/objects/[0-9a-f]{2}/[0-9a-f]+$');

/// The loose object files under the git folder of [project], by path.
///
/// Compared as a set, so a run that swaps one object for another shows too.
Set<String> _looseObjects(Directory project) =>
    Directory('${project.path}/.git/objects')
        .listSync(recursive: true)
        .whereType<File>()
        .map((file) => file.path.replaceAll(r'\', '/'))
        .where(_looseObjectPath.hasMatch)
        .toSet();

/// A history whose git runs count in [calls].
ApprovalHistory _countingHistory(List<List<String>> calls) => ApprovalHistory(
  runGit: (arguments, {required workingDirectory, environment}) {
    calls.add(arguments);
    return runRealGit(
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  },
);

final Matcher _refusesBeforeGit = throwsA(
  isA<RenderFault>()
      .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
      .having((f) => f.exitStatus, 'exit', 73)
      .having((f) => f.message, 'message', startsWith('cannot write docs/')),
);

void main() {
  group('a docs folder outside the project', () {
    test('the clone cannot make new write into the folder its docs link '
        'names, however its template sets the path', () async {
      final (:clone, :ext, base: _) = await _fallThroughClone();
      final before = treeBytes(ext);

      expect(
        () => writeIn(
          clone,
          (s) => answerNew(s, docTypeId: 'persona', slug: 'team'),
        ),
        _refusesOutside('docs/rules/team.md'),
      );

      expect(treeBytes(ext), before);
    }, skip: _linksUnavailable);

    test('set refuses the same way and leaves the doc as it was', () async {
      final (:clone, :ext, base: _) = await _fallThroughClone();
      final before = treeBytes(ext);

      expect(
        () => writeIn(
          clone,
          (s) => s.writeDoc(story2, '# Changed\n', LineEnding.lf),
        ),
        _refusesOutside('docs/$story2'),
      );

      expect(treeBytes(ext), before);
    }, skip: _linksUnavailable);
  });

  group('a project root reached through a docs link', () {
    test('set and new refuse, and the other project keeps its docs', () async {
      final (:clone, :victim, base: _) = await _linkedClone();
      final before = treeBytes(Directory('${victim.path}/docs'));

      expect(
        () => writeIn(
          clone,
          (s) => s.writeDoc(story2, '# Changed\n', LineEnding.lf),
        ),
        _refusesOutside('docs/$story2'),
      );
      expect(
        () => writeIn(
          clone,
          (s) => answerNew(s, docTypeId: 'persona', slug: 'team'),
        ),
        _refusesOutside('docs/prds/personas/team/PERSONA.md'),
      );

      expect(treeBytes(Directory('${victim.path}/docs')), before);
    }, skip: _linksUnavailable);

    test('the refusal names the docs link, not the code folder', () async {
      final (:clone, :victim, base: _) = await _linkedClone();

      expect(
        () => writeIn(
          clone,
          (s) => s.writeDoc(story2, '# Changed\n', LineEnding.lf),
        ),
        throwsA(
          isA<RenderFault>().having(
            (f) => f.message,
            'message',
            'cannot write docs/$story2: the project folder '
                '${victim.resolveSymbolicLinksSync()} was reached through the '
                'docs link in ${clone.resolveSymbolicLinksSync()}; run '
                'specstone trust at a terminal to allow it',
          ),
        ),
      );
    }, skip: _linksUnavailable);
  });

  group('after the Owner records the roots', () {
    test('new and set write into the folder the docs link names', () async {
      final (:clone, :ext, base: _) = await _fallThroughClone();
      _trust(clone);

      writeIn(clone, (s) => answerNew(s, docTypeId: 'persona', slug: 'team'));
      writeIn(clone, (s) => s.writeDoc(story2, '# Changed\n', LineEnding.lf));

      expect(File('${ext.path}/rules/team.md').existsSync(), isTrue);
      expect(
        File('${ext.path}/$story2').readAsStringSync(),
        contains('Changed'),
      );
    }, skip: _linksUnavailable);

    test(
      'set and new write into the other project the docs link names',
      () async {
        final (:clone, :victim, base: _) = await _linkedClone();
        _trust(clone);

        writeIn(clone, (s) => s.writeDoc(story2, '# Changed\n', LineEnding.lf));
        writeIn(clone, (s) => answerNew(s, docTypeId: 'persona', slug: 'team'));

        expect(
          File('${victim.path}/docs/$story2').readAsStringSync(),
          contains('Changed'),
        );
        expect(
          File('${victim.path}/docs/prds/personas/team/PERSONA.md')
              .existsSync(),
          isTrue,
        );
      },
      skip: _linksUnavailable,
    );

    test('a rename, which moves through the journal, writes too', () async {
      final (:clone, :ext, base: _) = await _fallThroughClone();
      _trust(clone);

      writeIn(
        clone,
        (s) => answerRename(s, 'user_story:login/reset_password', slug: 'x'),
      );

      expect(
        Directory('${ext.path}/prds/features/f01_login/us03_x').existsSync(),
        isTrue,
      );
    }, skip: _linksUnavailable);

    test('a delete, which the journal alone writes, writes too', () async {
      final (:clone, :ext, base: _) = await _fallThroughClone();
      _trust(clone);

      writeIn(clone, _deleteDraft);

      expect(File('${ext.path}/$fr12').existsSync(), isFalse);
    }, skip: _linksUnavailable);
  });

  group('the journal bounds without the record', () {
    test('a delete refuses naming the journal, and the folder keeps its '
        'file', () async {
      final (:clone, :ext, base: _) = await _fallThroughClone();
      final before = treeBytes(ext);

      expect(
        () => writeIn(clone, _deleteDraft),
        _refusesOutside('.specstone/trash/journal.json'),
      );

      expect(treeBytes(ext), before);
    }, skip: _linksUnavailable);

    test(
      'a delete in the other project the docs link names refuses too',
      () async {
        final (:clone, :victim, base: _) = await _linkedClone();
        final before = treeBytes(Directory('${victim.path}/docs'));

        expect(
          () => writeIn(clone, _deleteDraft),
          _refusesOutside('.specstone/trash/journal.json'),
        );

        expect(treeBytes(Directory('${victim.path}/docs')), before);
      },
      skip: _linksUnavailable,
    );
  });

  group('every journal command refuses first, before it plans a rewrite', () {
    final commands = <String, ReadAnswer Function(WriteSession)>{
      'reorder': (s) =>
          answerReorder(s, 'user_story:login/reset_password', place: '1'),
      'rename': (s) =>
          answerRename(s, 'user_story:login/reset_password', slug: 'x'),
      'move': (s) =>
          answerMove(s, ['user_story:login/reset_password'], under: 'signup'),
    };

    for (final MapEntry(:key, :value) in commands.entries) {
      test('$key names the journal and the folder keeps its bytes', () async {
        final (:clone, :ext, base: _) = await _fallThroughClone();
        final before = treeBytes(ext);

        expect(
          () => writeIn(clone, value),
          _refusesOutside('.specstone/trash/journal.json'),
        );

        expect(treeBytes(ext), before);
        expect(
          File('${clone.path}/.specstone/trash/journal.json').existsSync(),
          isFalse,
        );
      }, skip: _linksUnavailable);

      test('$key in the other project the docs link names refuses the same '
          'way', () async {
        final (:clone, :victim, base: _) = await _linkedClone();
        final before = treeBytes(Directory('${victim.path}/docs'));

        expect(
          () => writeIn(clone, value),
          _refusesOutside('.specstone/trash/journal.json'),
        );

        expect(treeBytes(Directory('${victim.path}/docs')), before);
      }, skip: _linksUnavailable);
    }
  });

  group('a pending journal under roots the Owner has not recorded', () {
    test('a replay refuses with the trust text, not the step path, and keeps '
        'the journal', () async {
      final (:clone, :ext, base: _) = await _fallThroughClone();
      writeJournal(clone, [
        const WriteStep.unguarded('docs/prds/x.md', 'text'),
      ]);
      final journal = File('${clone.path}/.specstone/trash/journal.json');
      final before = journal.readAsBytesSync();
      final extBefore = treeBytes(ext);

      expect(
        () => writeIn(clone, (session) {}),
        throwsA(
          isA<RenderFault>()
              .having((f) => f.file, 'file', '.specstone/trash/journal.json')
              .having(
                (f) => f.message,
                'message',
                'cannot write .specstone/trash/journal.json: the docs folder '
                    '${ext.resolveSymbolicLinksSync()} lies outside the '
                    'project; run specstone trust at a terminal to allow it',
              ),
        ),
      );

      expect(journal.readAsBytesSync(), before);
      expect(treeBytes(ext), extBefore);
    }, skip: _linksUnavailable);

    test('a journal step that leaves roots the Owner trusts still names the '
        'step path', () async {
      final (:clone, base: _, ext: _) = await _fallThroughClone();
      _trust(clone);
      writeJournal(clone, [
        const WriteStep.unguarded('../outside.txt', 'text'),
      ]);

      expect(
        () => writeIn(clone, (session) {}),
        throwsA(
          isA<RenderFault>().having(
            (f) => f.message,
            'message',
            startsWith(
              'its step path ../outside.txt leaves the project and '
              'docs roots; check .specstone/trash/',
            ),
          ),
        ),
      );
    }, skip: _linksUnavailable);
  });

  group('a record that no longer fits', () {
    test('is ignored once the docs link leads to another folder', () async {
      final (:base, :clone, ext: _) = await _fallThroughClone();
      _trust(clone);
      final other = Directory('${base.path}/ext2');
      for (final MapEntry(:key, :value) in writeProject.entries) {
        if (!key.startsWith('docs/')) continue;
        File('${other.path}/${key.substring(5)}')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(value);
      }
      Link('${clone.path}/docs').deleteSync();
      createRelativeLink('${clone.path}/docs', '../../ext2');
      final before = treeBytes(other);

      expect(
        () => writeIn(
          clone,
          (s) => answerNew(s, docTypeId: 'persona', slug: 'team'),
        ),
        _refusesOutside('docs/rules/team.md'),
      );

      expect(treeBytes(other), before);
    }, skip: _linksUnavailable);

    test('is ignored when it holds only one of the roots', () async {
      final (:clone, base: _, ext: _) = await _fallThroughClone();
      final trust = RootTrust.locate(clone, homeDirectory: testHome());
      File(
          '${testHome().path}/.specstone/trusted/'
          '${digestOf(utf8.encode(trust.folder.path))}',
        )
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({'projectRoot': trust.projectRoot.path}),
        );

      expect(
        RootTrust.locate(clone, homeDirectory: testHome()).isTrusted,
        isFalse,
      );
    }, skip: _linksUnavailable);
  });

  group('a record the clone cannot plant', () {
    test('lives under the home folder, so a record carried inside the '
        'project is no record', () async {
      final (:clone, base: _, ext: _) = await _fallThroughClone();
      final trust = RootTrust.locate(clone, homeDirectory: testHome());
      File(
          '${clone.path}/.specstone/trusted/'
          '${digestOf(utf8.encode(trust.folder.path))}',
        )
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'projectRoot': trust.projectRoot.path,
            'docsRoot': trust.docsRoot.path,
          }),
        );

      final inProject = RootTrust.locate(clone, homeDirectory: clone);

      expect(inProject.isTrusted, isFalse);
      expect(inProject.record, throwsA(isA<RenderFault>()));
    }, skip: _linksUnavailable);

    test('is never read from a home folder that is not absolute', () async {
      final (:clone, base: _, ext: _) = await _fallThroughClone();
      final trust = RootTrust.locate(
        clone,
        homeDirectory: Directory('relative-home'),
      );

      expect(trust.isTrusted, isFalse);
      expect(
        trust.record,
        throwsA(
          isA<RenderFault>().having(
            (f) => f.code,
            'code',
            RenderFaultCode.outputNotWritable,
          ),
        ),
      );
      expect(Directory('relative-home').existsSync(), isFalse);
    }, skip: _linksUnavailable);

    test('is never read from a home folder inside the docs folder', () async {
      final (:clone, :ext, base: _) = await _fallThroughClone();

      final trust = RootTrust.locate(clone, homeDirectory: ext);

      expect(trust.record, throwsA(isA<RenderFault>()));
    }, skip: _linksUnavailable);

    test('is not made when the environment names no home folder', () async {
      final (:clone, base: _, ext: _) = await _fallThroughClone();

      final trust = RootTrust.locate(clone, homeDirectory: null);

      expect(trust.isTrusted, isFalse);
      expect(trust.requireHome, throwsA(isA<RenderFault>()));
    }, skip: _linksUnavailable);
  });

  group('the layouts that need no record', () {
    Future<({Directory ws, Directory code})> workspace() async {
      final base = await writeTree({
        for (final MapEntry(:key, :value) in writeProject.entries)
          'ws/$key': value,
        'ws/specstone/lib/a.dart': '// a\n',
      });
      createRelativeLink('${base.path}/ws/specstone/docs', '../docs');
      return (
        ws: Directory('${base.path}/ws'),
        code: Directory('${base.path}/ws/specstone'),
      );
    }

    test('a project whose docs folder lies inside it writes', () async {
      final root = await writeWriteProject();

      writeIn(root, (s) => s.writeDoc(story2, '# Changed\n', LineEnding.lf));

      expect(RootTrust.locate(root, homeDirectory: null).needsRecord, isFalse);
      expect(readDoc(root, story2), contains('Changed'));
    });

    test('the workspace run from its root writes with no record', () async {
      final (:ws, code: _) = await workspace();

      writeIn(ws, (s) => s.writeDoc(story2, '# Changed\n', LineEnding.lf));

      expect(readDoc(ws, story2), contains('Changed'));
    }, skip: _linksUnavailable);

    test('the workspace run from the folder whose docs link leads to its docs '
        'refuses until one trust, then writes', () async {
      final (:ws, :code) = await workspace();

      expect(
        () => writeIn(
          code,
          (s) => s.writeDoc(story2, '# Changed\n', LineEnding.lf),
        ),
        _refusesOutside('docs/$story2'),
      );
      expect(readDoc(ws, story2), isNot(contains('Changed')));

      _trust(code);
      writeIn(code, (s) => s.writeDoc(story2, '# Changed\n', LineEnding.lf));

      expect(readDoc(ws, story2), contains('Changed'));
    }, skip: _linksUnavailable);

    test('a docs link to a project below the folder holding it needs no record '
        'for new, set, or a rename', () async {
      final base = await writeTree({
        for (final MapEntry(:key, :value) in writeProject.entries)
          'outer/below/$key': value,
        'outer/keep.txt': '',
      });
      createRelativeLink('${base.path}/outer/docs', 'below/docs');
      final outer = Directory('${base.path}/outer');
      final below = Directory('${base.path}/outer/below');

      expect(RootTrust.locate(outer, homeDirectory: null).needsRecord, isFalse);
      writeIn(outer, (s) => s.writeDoc(story2, '# Changed\n', LineEnding.lf));
      writeIn(outer, (s) => answerNew(s, docTypeId: 'persona', slug: 'team'));
      writeIn(
        outer,
        (s) => answerRename(s, 'user_story:login/reset_password', slug: 'x'),
      );

      expect(readDoc(below, story2), contains('Changed'));
      expect(hasDoc(below, 'prds/personas/team/PERSONA.md'), isTrue);
      expect(
        Directory('${below.path}/docs/prds/features/f01_login/us03_x')
            .existsSync(),
        isTrue,
      );
    }, skip: _linksUnavailable);

    test('a docs link to a project that is not below the folder, even one '
        'sharing its name prefix, still needs one', () async {
      final base = await writeTree({
        for (final MapEntry(:key, :value) in writeProject.entries)
          'clone-extra/$key': value,
        'clone/keep.txt': '',
      });
      createRelativeLink('${base.path}/clone/docs', '../clone-extra/docs');

      expect(
        RootTrust.locate(
          Directory('${base.path}/clone'),
          homeDirectory: null,
        ).needsRecord,
        isTrue,
      );
    }, skip: _linksUnavailable);

    test('a trust of the linked folder does not carry to a run from the '
        'workspace root, which never needed it', () async {
      final (:ws, :code) = await workspace();
      _trust(code);

      expect(
        RootTrust.locate(ws, homeDirectory: testHome()).needsRecord,
        isFalse,
      );
    }, skip: _linksUnavailable);
  });

  group('approve in a layout the Owner has not recorded', () {
    test('refuses before any git call and any view, and the other project '
        'keeps its objects', () async {
      final (:clone, :victim, base: _) = await _linkedClone();
      _gitWithUntrackedDraft(victim);
      final objects = _looseObjects(victim);

      for (final dryRun in [true, false]) {
        final calls = <List<String>>[];
        final out = StringBuffer();
        expect(
          () => writeIn(
            clone,
            (s) => dryRun
                ? approveDryRun(s, history: _countingHistory(calls))
                : approveDrafts(
                    s,
                    readLine: () => fail('the Owner was asked'),
                    out: out,
                    history: _countingHistory(calls),
                  ),
          ),
          _refusesBeforeGit,
        );
        expect(calls, isEmpty);
        expect(out.toString(), isEmpty);
      }
      expect(_looseObjects(victim), objects);
    }, skip: _linksUnavailable ?? (hasGit ? null : 'needs git'));
  });

  group('approve writes no object into the repository', () {
    test('after the Owner records a linked project', () async {
      final (:clone, :victim, base: _) = await _linkedClone();
      _gitWithUntrackedDraft(victim);
      _trust(clone);
      final objects = _looseObjects(victim);

      final text = writeIn(clone, (s) => approveDryRun(s).text);

      expect(text, contains('docs/prds/personas/y/PERSONA.md'));
      expect(_looseObjects(victim), objects);
    }, skip: _linksUnavailable ?? (hasGit ? null : 'needs git'));

    test('in a project that needs no record', () async {
      final root = await writeWriteProject();
      _gitWithUntrackedDraft(root);
      final objects = _looseObjects(root);

      final text = writeIn(root, (s) => approveDryRun(s).text);

      expect(text, contains('docs/prds/personas/y/PERSONA.md'));
      expect(_looseObjects(root), objects);
    }, skip: hasGit ? null : 'needs git');
  });
}
