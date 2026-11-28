// The test names are plan text kept as written.
// ignore_for_file: lines_longer_than_80_chars

@Tags(['integration'])
library;

import 'dart:io';

import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/document_writing/approve_drafts.dart';
import 'package:specstone_core/src/document_writing/approved_copy_store.dart';
import 'package:specstone_core/src/document_writing/models/seen_draft.dart';
import 'package:specstone_core/src/document_writing/move_doc.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../../helpers/git_repo.dart';
import '../../helpers/no_generators.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart';

const _storeFolder = '.specstone/approved';
const _orphan = 'ba9876543210';

final _approvedMark = RegExp('approved: "([0-9a-f]{12})"');

File _copyFile(Directory root, String hash) =>
    File('${root.path}/$_storeFolder/$hash.md');

String _markIn(String text) => _approvedMark.firstMatch(text)!.group(1)!;

String _markOf(Directory root, String docPath) =>
    _markIn(readDoc(root, docPath));

void _saveCopy(Directory root, String hash, String text) =>
    _copyFile(root, hash)
      ..createSync(recursive: true)
      ..writeAsStringSync(text);

void _walkApproving(Directory root, String name) => writeIn(
  root,
  (s) => approveDrafts(
    s,
    names: [name],
    readLine: () => 'y',
    out: StringBuffer(),
    generators: noGenerators,
  ),
);

/// Writes the doc at [from] to [docPath] as a draft with a sentence more, its
/// `approved:` mark kept.
void _editAsDraft(Directory root, String from, String docPath) {
  final text = readDoc(root, from)
      .replaceFirst('\n---\n\n# Buyer', '\ndraft: true\n---\n\n# Buyer')
      .replaceFirst('Buys things.', 'Buys things. Browses stores.');
  docFile(root, from).deleteSync();
  docFile(root, docPath)
    ..createSync(recursive: true)
    ..writeAsStringSync(text);
}

SeenDraft _seenDraft(Directory root, String address) =>
    SeenDraft(name: address, hash: getDoc(root, address)['base']! as String);

String _dryRunView(Directory root, String name) => writeIn(
  root,
  (s) => approveDryRun(s, names: [name], generators: noGenerators),
).text;

void main() {
  final skipGit = hasGit ? null : 'git is not available';

  group('ApprovedCopyStore', () {
    String approvedText(String body) => withApprovalHash(body, null);

    test('a saved copy is found by the mark it carries', () async {
      final store = ApprovedCopyStore(
        await writeTree({'.specstone/config.yaml': ''}),
      );
      final text = approvedText('# T\n\nBody.\n');

      store.save(text);

      expect(store.find(_markIn(text), null)?.text, text);
    });

    test('a copy edited after it was saved, or saved under another mark, is not found', () async {
      final root = await writeTree({'.specstone/config.yaml': ''});
      final store = ApprovedCopyStore(root);
      final text = approvedText('# T\n\nBody.\n');
      final mark = _markIn(text);

      store.save(text);
      _saveCopy(root, mark, text.replaceFirst('Body.', 'Body. Edited.'));
      expect(store.find(mark, null), isNull);

      _saveCopy(root, mark, approvedText('# T\n\nOther.\n'));
      expect(store.find(mark, null), isNull);
    });

    test('a value that is no hash finds nothing and reads no path', () async {
      final root = await writeTree({'.specstone/config.yaml': ''});
      File('${root.path}/outside.md')
          .writeAsStringSync(approvedText('# T\n\nBody.\n'));

      final store = ApprovedCopyStore(root);

      expect(store.find('../../outside', null), isNull);
      expect(store.find(true, null), isNull);
      expect(store.find(null, null), isNull);
    });

    test(
      'a store folder that cannot be made skips the save and throws nothing',
      () async {
        final root = await writeTree({_storeFolder: 'a file, not a folder'});

        ApprovedCopyStore(root).save(approvedText('# T\n\nBody.\n'));

        expect(
          File('${root.path}/$_storeFolder').readAsStringSync(),
          'a file, not a folder',
        );
      },
    );

    test(
      'prune deletes the copies no hash carries and leaves every other file',
      () async {
        final root = await writeTree({
          '$_storeFolder/0123456789ab.md': 'kept',
          '$_storeFolder/$_orphan.md': 'gone',
          '$_storeFolder/notes.md': 'not a copy',
          '$_storeFolder/0123456789ab.txt': 'not a copy either',
        });

        ApprovedCopyStore(root).prune({'0123456789ab'});

        expect(_copyFile(root, '0123456789ab').existsSync(), isTrue);
        expect(_copyFile(root, _orphan).existsSync(), isFalse);
        expect(
          File('${root.path}/$_storeFolder/notes.md').existsSync(),
          isTrue,
        );
        expect(
          File('${root.path}/$_storeFolder/0123456789ab.txt').existsSync(),
          isTrue,
        );
      },
    );

    test('the first save adds approved/ to an existing .specstone/.gitignore and keeps its lines', () async {
      final root = await writeTree({
        '.specstone/.gitignore': 'index.sqlite*\nbuild/\nmine/\n',
      });

      ApprovedCopyStore(root).save(approvedText('# T\n\nBody.\n'));

      expect(
        File('${root.path}/.specstone/.gitignore').readAsStringSync(),
        'index.sqlite*\nbuild/\nmine/\ntrash/\nbundles/\nreports/\napproved/\n',
      );
      expect(Directory('${root.path}/$_storeFolder').listSync(), hasLength(1));
    });

    test('a later save re-adds a missing approved/ line when the store folder is already present', () async {
      final root = await writeTree({
        '.specstone/.gitignore':
            'index.sqlite*\nbuild/\ntrash/\nbundles/\nreports/\n',
        '$_storeFolder/$_orphan.md': 'an earlier copy',
      });

      ApprovedCopyStore(root).save(approvedText('# T\n\nBody.\n'));

      expect(
        File('${root.path}/.specstone/.gitignore').readAsStringSync(),
        'index.sqlite*\nbuild/\ntrash/\nbundles/\nreports/\napproved/\n',
      );
      expect(Directory('${root.path}/$_storeFolder').listSync(), hasLength(2));
    });

    test(
      'a .gitignore that cannot take the approved/ line skips the save',
      skip: unreadablePathSkipReason(),
      () async {
        final root = await writeTree({
          '.specstone/.gitignore': 'index.sqlite*\n',
        });
        final ignore = File('${root.path}/.specstone/.gitignore');
        Process.runSync('chmod', ['444', ignore.path]);
        addTearDown(() => Process.runSync('chmod', ['644', ignore.path]));

        ApprovedCopyStore(root).save(approvedText('# T\n\nBody.\n'));

        expect(Directory('${root.path}/$_storeFolder').existsSync(), isFalse);
      },
    );

    test('prune of a project with no store folder makes none', () async {
      final root = await writeTree({'.specstone/config.yaml': ''});

      ApprovedCopyStore(root).prune(const {});

      expect(Directory('${root.path}/$_storeFolder').existsSync(), isFalse);
    });
  });

  group('the writers', () {
    test(
      'y saves the approved text under the hash it wrote as approved:',
      () async {
        final root = await writeWriteProject();

        _walkApproving(root, 'persona:buyer');

        expect(
          _copyFile(root, _markOf(root, persona)).readAsStringSync(),
          readDoc(root, persona),
        );
      },
    );

    test('a CRLF doc is saved as LF text', () async {
      final root = await writeWriteProject();
      final file = docFile(root, persona);
      file.writeAsStringSync(file.readAsStringSync().replaceAll('\n', '\r\n'));

      _walkApproving(root, 'persona:buyer');

      final saved = _copyFile(root, _markOf(root, persona)).readAsStringSync();
      expect(saved, isNot(contains('\r')));
      expect(saved, readDoc(root, persona).replaceAll('\r\n', '\n'));
    });

    test('approving named drafts saves each copy', () async {
      final root = await writeWriteProject();
      SeenDraft seen(String address) => SeenDraft(
        name: address,
        hash: getDoc(root, address)['base']! as String,
      );

      writeIn(
        root,
        (s) => approveNamed(s, [
          seen('feature:signup'),
          seen('persona:buyer'),
        ], generators: noGenerators),
      );

      for (final docPath in [signupFeature, persona]) {
        expect(
          _copyFile(root, _markOf(root, docPath)).readAsStringSync(),
          readDoc(root, docPath),
        );
      }
    });

    test('an approval whose copy cannot be saved is still written', () async {
      final root = await writeWriteProject(
        extra: {_storeFolder: 'a file, not a folder'},
      );

      _walkApproving(root, 'persona:buyer');

      expect(readDoc(root, persona), contains('approved: "'));
      expect(readDoc(root, persona), isNot(contains('draft: true')));
      expect(
        File('${root.path}/$_storeFolder').readAsStringSync(),
        'a file, not a folder',
      );
    });
  });

  group('a WriteStep that keeps an approved copy', () {
    final stamped = withApprovalHash('# Buyer\n\nBuys.\n', null);
    late Directory root;
    late JournalTarget target;
    late String before;

    setUp(() async {
      root = await writeWriteProject();
      target = JournalTarget.of(openProject(root), homeDirectory: testHome());
      before = textHashOf(readDoc(root, persona));
    });

    WriteStep step({bool keeps = true}) => WriteStep(
      'docs/$persona',
      stamped,
      before: before,
      keepsApprovedCopy: keeps,
    );

    test('saves the copy it writes, as LF text without a BOM', () {
      final crlf = stamped.replaceAll('\n', '\r\n');

      WriteStep(
        'docs/$persona',
        '﻿$crlf',
        before: before,
        keepsApprovedCopy: true,
      ).apply(target);

      expect(readDoc(root, persona), crlf);
      expect(_copyFile(root, _markIn(stamped)).readAsStringSync(), stamped);
    });

    test('saves no copy unless it keeps one', () {
      step(keeps: false).apply(target);

      expect(readDoc(root, persona), stamped);
      expect(Directory('${root.path}/$_storeFolder').existsSync(), isFalse);
    });

    test('saves no copy when the file changed since it was planned', () {
      docFile(root, persona).writeAsStringSync('changed\n');

      step().apply(target);

      expect(readDoc(root, persona), 'changed\n');
      expect(Directory('${root.path}/$_storeFolder').existsSync(), isFalse);
    });

    test(
      'saves the copy on a replay when the stopped run had written the file',
      () {
        docFile(root, persona).writeAsStringSync(stamped);
        writeJournal(root, [step()]);

        MoveJournal.replay(target);

        expect(_copyFile(root, _markIn(stamped)).readAsStringSync(), stamped);
      },
    );

    test('saves no copy for a file that is gone', () {
      WriteStep(
        'docs/prds/missing.md',
        stamped,
        before: before,
        keepsApprovedCopy: true,
      ).apply(target);

      expect(Directory('${root.path}/$_storeFolder').existsSync(), isFalse);
    });

    test('saves the copy on a replay of its journal', () {
      writeJournal(root, [step()]);

      MoveJournal.replay(target);

      expect(readDoc(root, persona), stamped);
      expect(_copyFile(root, _markIn(stamped)).readAsStringSync(), stamped);
    });

    test('writes its flag to the journal only when set, and an older journal reads it as unset', () {
      expect((step().toJson()['write']! as Map)['keepsApprovedCopy'], isTrue);
      expect(
        (step(keeps: false).toJson()['write']! as Map).containsKey(
          'keepsApprovedCopy',
        ),
        isFalse,
      );

      final replayed = JournalStep.fromJson(step().toJson());
      final older = JournalStep.fromJson({
        'write': {'path': 'docs/$persona', 'text': stamped, 'before': before},
      });

      expect((replayed as WriteStep).keepsApprovedCopy, isTrue);
      expect((older as WriteStep).keepsApprovedCopy, isFalse);
    });

    test('is not saved when a journal without the flag replays', () {
      writeJournal(root, [
        JournalStep.fromJson({
          'write': {'path': 'docs/$persona', 'text': stamped, 'before': before},
        }),
      ]);

      MoveJournal.replay(target);

      expect(readDoc(root, persona), stamped);
      expect(Directory('${root.path}/$_storeFolder').existsSync(), isFalse);
    });
  });

  group('a move that re-stamps an approved doc', () {
    for (final (tag, move) in <(String, void Function(WriteSession))>[
      (
        'a reorder',
        (s) => answerReorder(
          s,
          'feature:signup',
          place: '1',
          generators: noGenerators,
        ),
      ),
      (
        'a rename',
        (s) => answerRename(
          s,
          'feature:signup',
          slug: 'join',
          generators: noGenerators,
        ),
      ),
    ]) {
      test('$tag saves its approved copy, which the next view compares against', () async {
        final root = await writeWriteProject();

        writeIn(root, move);

        final file = docFile(root, featuresIndex);
        expect(
          _copyFile(root, _markOf(root, featuresIndex)).readAsStringSync(),
          readDoc(root, featuresIndex),
        );
        file.writeAsStringSync(
          '${readDoc(root, featuresIndex).replaceFirst('---\n', '---\ndraft: true\n')}\nAdded line.\n',
        );
        final drafts =
            writeIn(
                  root,
                  (s) => approveDryRun(s, generators: noGenerators),
                ).json['drafts']!
                as List;
        final view = drafts.cast<Map<String, Object?>>().singleWhere(
          (draft) => draft['path'] == featuresIndex,
        );
        expect(view['lookup'], 'found');
        expect(view['dropped'], isEmpty);
        expect(view['new'], anyElement(contains('Added line')));
      });
    }

    for (final (tag, move) in <(String, void Function(WriteSession))>[
      (
        'a dry-run reorder',
        (s) => answerReorder(
          s,
          'feature:signup',
          place: '1',
          dryRun: true,
          generators: noGenerators,
        ),
      ),
      (
        'a dry-run rename',
        (s) => answerRename(
          s,
          'feature:signup',
          slug: 'join',
          dryRun: true,
          generators: noGenerators,
        ),
      ),
    ]) {
      test('$tag saves no copy', () async {
        final root = await writeWriteProject();

        writeIn(root, move);

        expect(Directory('${root.path}/$_storeFolder').existsSync(), isFalse);
      });
    }
  });

  group('the lookup', () {
    test('an approval left uncommitted is the base of the next view', () async {
      final root = await writeWriteProject();
      _walkApproving(root, 'persona:buyer');
      _editAsDraft(root, persona, persona);

      final view = _dryRunView(root, 'persona:buyer');

      expect(view, contains('| old     | approved copy not yet committed |\n'));
      expect(view, contains('| dropped | 0 sentences dropped |\n'));
      expect(view, contains('| new     | 1 sentence new |\n'));
    });

    test('the copy is found after the doc is renamed', () async {
      final root = await writeWriteProject();
      _walkApproving(root, 'persona:buyer');
      _editAsDraft(root, persona, 'prds/personas/shopper/PERSONA.md');

      final view = _dryRunView(root, 'persona:shopper');

      expect(view, contains('| old     | approved copy not yet committed |\n'));
      expect(view, contains('| new     | 1 sentence new |\n'));
    });

    test('a committed approval is read from git, with its rename line, though its copy is saved', () async {
      const renamed = 'prds/personas/shopper/PERSONA.md';
      final root = await writeWriteProject();
      expect(git(root, ['init', '-q']).exitCode, 0);
      expect(git(root, ['config', 'core.autocrlf', 'false']).exitCode, 0);
      _walkApproving(root, 'persona:buyer');
      commitAll(root, 'approved');
      _editAsDraft(root, persona, renamed);
      commitAll(root, 'renamed and drafted');
      expect(_copyFile(root, _markOf(root, renamed)).existsSync(), isTrue);

      final view = _dryRunView(root, 'persona:shopper');

      expect(view, contains('| old     | approved copy in commit `'));
      expect(view, contains('renamed from `docs/$persona`'));
      expect(view, isNot(contains('not yet committed')));
    }, skip: skipGit);

    test(
      'a committed approval whose copy was never saved is read from git',
      () async {
        final root = await writeWriteProject(
          extra: {_storeFolder: 'a file, not a folder'},
        );
        expect(git(root, ['init', '-q']).exitCode, 0);
        expect(git(root, ['config', 'core.autocrlf', 'false']).exitCode, 0);
        _walkApproving(root, 'persona:buyer');
        commitAll(root, 'approved');
        _editAsDraft(root, persona, persona);

        final view = _dryRunView(root, 'persona:buyer');

        expect(view, contains('| old     | approved copy in commit `'));
        expect(view, contains('| new     | 1 sentence new |\n'));
        expect(view, isNot(contains('not yet committed')));
      },
      skip: skipGit,
    );

    test('a copy whose hash does not match the doc is ignored, and git history is read', () async {
      String story(String mark, String useCase) =>
          '---\nstatus: planned\n$mark---\n\n# Sign out\n\n## Use Case\n\n'
          '$useCase\n\n## Acceptance Criteria\n\n- **Given** a signed-in user\n';
      final root = await writeWriteProject(
        extra: {
          'docs/$story2': story(
            'approved: true\n',
            'Sign out. Ends the session.',
          ),
        },
      );
      expect(git(root, ['init', '-q']).exitCode, 0);
      expect(git(root, ['config', 'core.autocrlf', 'false']).exitCode, 0);
      commitAll(root, 'approved');
      const stale = '0123456789ab';
      docFile(root, story2).writeAsStringSync(
        story(
          'draft: true\napproved: "$stale"\n',
          'Sign out. Ends the session. Keeps the cart.',
        ),
      );
      _saveCopy(
        root,
        stale,
        story('approved: "$stale"\n', 'Sign out. Keeps the cart.'),
      );

      final view = _dryRunView(root, 'user_story:login/sign_out');

      expect(view, contains('| old     | approved copy in commit `'));
      expect(view, isNot(contains('not yet committed')));
    }, skip: skipGit);

    test('a doc marked approved: true with no saved copy reads its approved copy from git', () async {
      String story(String marks, String useCase) =>
          '---\nstatus: planned\n$marks---\n\n# Sign out\n\n## Use Case\n\n'
          '$useCase\n\n## Acceptance Criteria\n\n- **Given** a signed-in user\n';
      final root = await writeWriteProject(
        extra: {
          'docs/$story2': story(
            'approved: true\n',
            'Sign out. Ends the session.',
          ),
        },
      );
      expect(git(root, ['init', '-q']).exitCode, 0);
      expect(git(root, ['config', 'core.autocrlf', 'false']).exitCode, 0);
      commitAll(root, 'approved');
      docFile(root, story2).writeAsStringSync(
        story(
          'draft: true\napproved: true\n',
          'Sign out. Ends the session. Keeps the cart.',
        ),
      );

      final view = _dryRunView(root, 'user_story:login/sign_out');

      expect(Directory('${root.path}/$_storeFolder').existsSync(), isFalse);
      expect(view, contains('| old     | approved copy in commit `'));
      expect(view, isNot(contains('not yet committed')));
    }, skip: skipGit);
  });

  group('the prune', () {
    test('an approve run deletes the copy no doc carries and keeps the one a doc carries', () async {
      final root = await writeWriteProject();
      _saveCopy(root, _orphan, 'an approval no doc carries');

      _walkApproving(root, 'persona:buyer');

      expect(_copyFile(root, _orphan).existsSync(), isFalse);
      expect(_copyFile(root, _markOf(root, persona)).existsSync(), isTrue);
    });

    test(
      'a doc approved again leaves its old copy to the next prune',
      () async {
        final root = await writeWriteProject();
        _walkApproving(root, 'persona:buyer');
        final firstMark = _markOf(root, persona);
        _editAsDraft(root, persona, persona);

        _walkApproving(root, 'persona:buyer');

        expect(_copyFile(root, firstMark).existsSync(), isFalse);
        expect(_copyFile(root, _markOf(root, persona)).existsSync(), isTrue);
      },
    );

    test('a doc another session made and approved while the walk waited keeps its copy', () async {
      final root = await writeWriteProject();
      const other = 'prds/personas/shopper/PERSONA.md';
      var asked = false;
      String? answer() {
        if (!asked) {
          asked = true;
          docFile(root, other)
            ..createSync(recursive: true)
            ..writeAsStringSync(
              '---\ndraft: true\n---\n\n# Shopper\n\n## Profile\nShops.\n',
            );
          _walkApproving(root, 'persona:shopper');
        }
        return 'y';
      }

      writeIn(
        root,
        (s) => approveDrafts(
          s,
          names: ['persona:buyer'],
          readLine: answer,
          out: StringBuffer(),
          generators: noGenerators,
        ),
      );

      expect(_copyFile(root, _markOf(root, other)).existsSync(), isTrue);
      expect(_copyFile(root, _markOf(root, persona)).existsSync(), isTrue);
    });

    test(
      'a doc whose frontmatter is not valid YAML leaves every copy in place',
      () async {
        final root = await writeWriteProject();
        _walkApproving(root, 'persona:buyer');
        final mark = _markOf(root, persona);
        final file = docFile(root, persona);
        file.writeAsStringSync(
          file.readAsStringSync().replaceFirst(
            'approved: "$mark"\n',
            'approved: "$mark"\nbroken: [unclosed\n',
          ),
        );

        _walkApproving(root, 'feature:signup');

        expect(_copyFile(root, mark).existsSync(), isTrue);
        expect(
          _copyFile(root, _markOf(root, signupFeature)).existsSync(),
          isTrue,
        );
      },
    );

    test('a dry run deletes no copy', () async {
      final root = await writeWriteProject();
      _saveCopy(root, _orphan, 'an approval no doc carries');

      _dryRunView(root, 'persona:buyer');

      expect(_copyFile(root, _orphan).existsSync(), isTrue);
    });

    group('at the end of a walk or a --yes call', () {
      late Directory root;

      setUp(() async {
        root = await writeWriteProject();
        _saveCopy(root, _orphan, 'an approval no doc carries');
      });

      test('a walk ended by q prunes', () {
        writeIn(
          root,
          (s) => approveDrafts(
            s,
            readLine: () => 'q',
            out: StringBuffer(),
            generators: noGenerators,
          ),
        );

        expect(_copyFile(root, _orphan).existsSync(), isFalse);
      });

      test('a walk answered n to every draft prunes', () {
        writeIn(
          root,
          (s) => approveDrafts(
            s,
            readLine: () => 'n',
            out: StringBuffer(),
            generators: noGenerators,
          ),
        );

        expect(_copyFile(root, _orphan).existsSync(), isFalse);
        expect(readDoc(root, persona), contains('draft: true'));
      });

      test('--yes prunes after its writes, keeping the copy it saved', () {
        writeIn(
          root,
          (s) => approveNamed(s, [
            _seenDraft(root, 'persona:buyer'),
          ], generators: noGenerators),
        );

        expect(_copyFile(root, _orphan).existsSync(), isFalse);
        expect(_copyFile(root, _markOf(root, persona)).existsSync(), isTrue);
      });

      test('a walk a refusal ends prunes none', () {
        expect(
          () => writeIn(
            root,
            (s) => approveDrafts(
              s,
              names: ['feature:nosuch'],
              readLine: () => 'y',
              out: StringBuffer(),
              generators: noGenerators,
            ),
          ),
          throwsA(isA<IndexFault>()),
        );
        expect(_copyFile(root, _orphan).existsSync(), isTrue);
      });

      test('a --yes call a refusal ends prunes none', () {
        const stale = SeenDraft(name: 'persona:buyer', hash: '000000000000');

        expect(
          () => writeIn(
            root,
            (s) => approveNamed(s, [stale], generators: noGenerators),
          ),
          throwsA(isA<WriteFault>()),
        );
        expect(_copyFile(root, _orphan).existsSync(), isTrue);
      });

      test('a walk with no draft in scope prunes none', () {
        final out = StringBuffer();

        writeIn(
          root,
          (s) => approveDrafts(
            s,
            names: ['user_story:login/sign_out'],
            readLine: () => 'y',
            out: out,
            generators: noGenerators,
          ),
        );

        expect(out.toString(), 'no draft waits for approval\n');
        expect(_copyFile(root, _orphan).existsSync(), isTrue);
      });

      test('a busy index write lock skips the prune and keeps the copies', () {
        writeIn(root, (_) {});
        final other = sqlite3.open('${root.path}/.specstone/index.sqlite');
        addTearDown(other.close);
        String? answer() {
          other.execute('BEGIN IMMEDIATE');
          return 'q';
        }

        writeIn(
          root,
          (s) => approveDrafts(
            s,
            readLine: answer,
            out: StringBuffer(),
            generators: noGenerators,
          ),
          busyTimeout: const Duration(milliseconds: 200),
        );

        expect(_copyFile(root, _orphan).existsSync(), isTrue);
      });

      test(
        'a doc that cannot be read skips the prune and keeps the copies',
        skip: unreadablePathSkipReason(),
        () {
          final unreadable = docFile(root, 'prds/d01_context.md');
          String? answer() {
            Process.runSync('chmod', ['000', unreadable.path]);
            addTearDown(
              () => Process.runSync('chmod', ['644', unreadable.path]),
            );
            return 'q';
          }

          writeIn(
            root,
            (s) => approveDrafts(
              s,
              readLine: answer,
              out: StringBuffer(),
              generators: noGenerators,
            ),
          );

          expect(_copyFile(root, _orphan).existsSync(), isTrue);
        },
      );

      test(
        'a docs folder that cannot be read skips the prune and keeps the copies',
        skip: unreadablePathSkipReason(),
        () {
          final unreadable = Directory('${root.path}/docs/prds/personas');
          String? answer() {
            Process.runSync('chmod', ['000', unreadable.path]);
            addTearDown(
              () => Process.runSync('chmod', ['755', unreadable.path]),
            );
            return 'q';
          }

          writeIn(
            root,
            (s) => approveDrafts(
              s,
              readLine: answer,
              out: StringBuffer(),
              generators: noGenerators,
            ),
          );

          expect(_copyFile(root, _orphan).existsSync(), isTrue);
        },
      );
    });
  });
}
