// The expected texts are doc literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/document_writing/batch_fault.dart';
import 'package:specstone_core/src/document_writing/batch_file.dart'
    show parseBatchFile;
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/root_trust.dart';
import 'package:specstone_core/src/document_writing/set_batch.dart';
import 'package:specstone_core/src/index_query/get_docs.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' show checkOf, spots;
import '../../helpers/index_fixture.dart' show openSession;
import '../../helpers/posix_modes.dart';
import '../../helpers/relative_link.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart';

const _story = 'document_writing/edit_one_section_or_field';
const _wb = '$_story/write_a_batch';
const _staleBase =
    'document_writing/edit_one_section_or_field/refuse_stale_base';
const _finish = 'document_writing/delete_doc_subtree/finish_interrupted_move';
const _serialize =
    'document_writing/edit_one_section_or_field/serialize_writes';

const _useCase = 'user_story:login/email_login#use_case';
const _criteria = 'user_story:login/email_login#acceptance_criteria';
const _signOutUseCase = 'user_story:login/sign_out#use_case';
const _signOutCriteria = 'user_story:login/sign_out#acceptance_criteria';

const _story1Line = 'login/email_login (user_story)';
const _story2Line = 'login/sign_out (user_story)';

/// Returns the text `get` prints for [names], as an Agent reads it.
String getText(Directory root, List<String> names) {
  final session = openSession(root);
  try {
    return answerGet(session.index, names).text;
  } finally {
    session.close();
  }
}

ReadAnswer runBatch(Directory root, String text) =>
    writeIn(root, (s) => answerSetBatch(s, parseBatchFile('batch.md', text)));

/// Returns [text] with its first [from] replaced by [to]; fails when [from] is
/// not there, so an edit never silently misses.
String edit(String text, String from, String to) {
  expect(text, contains(from), reason: 'the edit target is in the text');
  return text.replaceFirst(from, to);
}

String docBase(Directory root, String docPath) =>
    (getDoc(root, docPath)['bases']! as Map)['doc']! as String;

String partBase(Directory root, String address) =>
    getDoc(root, address)['base']! as String;

/// The docs of [root] as bytes, for the check that a refusal wrote nothing.
Map<String, List<int>> docBytes(Directory root) =>
    treeBytes(Directory('${root.path}/docs'));

/// Runs the batch and returns its refusal, failing when it writes or throws
/// anything else; the docs keep their bytes.
BatchFault refuse(Directory root, String text) {
  final before = docBytes(root);
  try {
    runBatch(root, text);
  } on BatchFault catch (fault) {
    expect(docBytes(root), before, reason: 'a refused batch writes no doc');
    return fault;
  }
  fail('the batch was not refused');
}

BatchEntry onlyEntry(BatchFault fault) {
  expect(fault.entries, hasLength(1));
  return fault.entries.single;
}

String wholeLine(String name, String docPath, String base) =>
    '==> $name · $docPath · base $base <==';

String journalPathOf(Directory root) =>
    '${root.path}/${MoveJournal.journalPath}';

Matcher refusedWith(String code, {int status = 64}) => isA<BatchFault>()
    .having((f) => f.exitStatus, 'exit', status)
    .having((f) => f.entries.first.code, 'code', code);

void main() {
  test(
    '$_wb E01: three whole-doc blocks, each fresh and changed, write each doc once, mark it draft, and print each new base in file order',
    () async {
      final root = await writeWriteProject();
      var text = getText(root, [story2, fr11, loginArch]);
      text = edit(text, 'Sign out.', 'Sign out everywhere.');
      text = edit(
        text,
        'check the email and the password',
        'check the email, the password, and the device',
      );
      text = edit(
        text,
        'Collects the email and the password',
        'Collects the email',
      );

      final answer = runBatch(root, text);

      for (final docPath in [story2, fr11, loginArch]) {
        expect(
          readDoc(root, docPath),
          contains('draft: true\n'),
          reason: docPath,
        );
      }
      expect(readDoc(root, story2), contains('Sign out everywhere.'));
      expect(readDoc(root, fr11), contains('and the device'));
      expect(
        readDoc(root, loginArch),
        contains('| Login form | Collects the email |'),
      );
      expect(
        answer.text,
        '${wholeLine(_story2Line, story2, docBase(root, story2))}\n'
        '${wholeLine('login/email_login/validate_credentials (fr)', fr11, docBase(root, fr11))}\n'
        '${wholeLine('login (architecture)', loginArch, docBase(root, loginArch))}\n',
      );
      expect(answer.json, {
        'blocks': [
          for (final (name, type, docPath) in [
            ('login/sign_out', 'user_story', story2),
            ('login/email_login/validate_credentials', 'fr', fr11),
            ('login', 'architecture', loginArch),
          ])
            {
              'name': name,
              'docType': type,
              'path': docPath,
              'key': 'doc',
              'base': docBase(root, docPath),
              'draft': true,
              'written': true,
            },
        ],
      });
      expect(File(journalPathOf(root)).existsSync(), isFalse);
    },
  );

  test(
    '$_story S14: three docs read in one call, one unchanged, write each changed doc and leave the unchanged doc as it is',
    () async {
      final root = await writeWriteProject();
      final unchangedBytes = docFile(root, loginArch).readAsBytesSync();
      var text = getText(root, [story2, fr11, loginArch]);
      text = edit(text, 'Sign out.', 'Sign out everywhere.');
      text = edit(text, 'check the email', 'check the email twice, then');

      final answer = runBatch(root, text);

      expect(readDoc(root, story2), contains('Sign out everywhere.'));
      expect(readDoc(root, story2), contains('draft: true\n'));
      expect(readDoc(root, fr11), contains('check the email twice, then'));
      expect(docFile(root, loginArch).readAsBytesSync(), unchangedBytes);
      final lines = answer.text.trimRight().split('\n');
      expect(lines, hasLength(3));
      expect(lines[0], endsWith('base ${docBase(root, story2)} <=='));
      expect(lines[1], endsWith('base ${docBase(root, fr11)} <=='));
      expect(
        lines[2],
        wholeLine(
          'login (architecture)',
          loginArch,
          docBase(root, loginArch),
        ).replaceFirst(' <==', ' · unchanged <=='),
      );
    },
  );

  test(
    '$_story S15: one stale doc refuses the whole batch and hands back its current text with its current base',
    () async {
      final root = await writeWriteProject();
      var text = getText(root, [story2, fr11]);
      text = edit(text, 'Sign out.', 'Sign out everywhere.');
      text = edit(text, 'check the email', 'check the email twice, then');
      final changed = readDoc(
        root,
        fr11,
      ).replaceFirst('shall check', 'shall carefully check');
      docFile(root, fr11).writeAsStringSync(changed);

      final fault = refuse(root, text);

      final entry = onlyEntry(fault);
      expect(entry.file, fr11);
      expect(entry.current!.text, changed);
      expect(entry.current!.base, docBase(root, fr11));
      expect(fault.exitStatus, 75);
    },
  );

  test(
    '$_wb E02: a block whose base differs from its target on disk writes no doc and refuses with 75, its fault line naming the doc and its current text under its naming line',
    () async {
      final root = await writeWriteProject();
      var text = getText(root, [story1, story2]);
      final staleBase = docBase(root, story2);
      text = edit(text, 'Sign out.', 'Sign out everywhere.');
      text = edit(text, 'Sign in with an email.', 'Sign in with a passkey.');
      docFile(root, story2).writeAsStringSync(
        readDoc(root, story2).replaceFirst('Sign out.', 'Log out.'),
      );

      final fault = refuse(root, text);

      expect(fault, refusedWith('base_mismatch', status: 75));
      final entry = onlyEntry(fault);
      expect(
        entry.toText(),
        '$story2: doc: the doc changed since base $staleBase',
      );
      expect(entry.key, 'doc');
      expect(entry.current!.text, readDoc(root, story2));
      expect(entry.current!.base, docBase(root, story2));
      expect(
        entry.current!.heading,
        wholeLine(_story2Line, story2, docBase(root, story2)),
      );
    },
  );

  test(
    '$_staleBase E07: a stale section block and a stale whole-doc block each hand back their current text under their naming line',
    () async {
      final root = await writeWriteProject();
      final section = getText(root, [_signOutUseCase]);
      final whole = getText(root, [story1]);
      final text = '${edit(section, 'Sign out.', 'Sign out now.')}\n$whole';
      docFile(root, story2).writeAsStringSync(
        readDoc(root, story2).replaceFirst('Sign out.', 'Log out.'),
      );
      docFile(root, story1).writeAsStringSync(
        readDoc(
          root,
          story1,
        ).replaceFirst('Sign in with', 'Please sign in with'),
      );

      final fault = refuse(root, text);

      expect(fault, refusedWith('base_mismatch', status: 75));
      expect(fault.entries, hasLength(2));
      final [stale, staleWhole] = fault.entries;
      expect(stale.key, 'use_case');
      expect(
        stale.current!.heading,
        '==> $_story2Line · $story2#use_case · base ${partBase(root, _signOutUseCase)} <==',
      );
      expect(stale.current!.text, '## Use Case\n\nLog out.\n');
      expect(
        staleWhole.toText(),
        startsWith('$story1: doc: the doc changed since base '),
      );
      expect(
        staleWhole.current!.heading,
        wholeLine(_story1Line, story1, docBase(root, story1)),
      );
      expect(staleWhole.current!.text, readDoc(root, story1));
    },
  );

  test(
    '$_wb E03: a block whose path names no doc, or a doc deleted since the read, refuses with doc_not_found naming the block by its path, and the name part resolves nothing',
    () async {
      final root = await writeWriteProject();
      final text = getText(root, [story1, story3]);
      docFile(root, story3).deleteSync();
      const gone = 'prds/features/f09_gone/USER_STORY.md';

      final fault = refuse(
        root,
        '$text\n==> login/email_login (user_story) · $gone · base $emptyBaseHash <==\n# Gone\n',
      );

      expect(fault, refusedWith('doc_not_found'));
      expect(fault.entries.map((e) => (e.code, e.file, e.key)), [
        ('doc_not_found', story3, 'doc'),
        ('doc_not_found', gone, 'doc'),
      ]);
    },
  );

  test('$_wb E03: a block naming an untyped doc refuses with untyped_target', () async {
    final root = await writeWriteProject();

    final fault = refuse(
      root,
      '==> context · prds/d01_context.md · base $emptyBaseHash <==\n# Context\n',
    );

    expect(fault, refusedWith('untyped_target'));
    expect(onlyEntry(fault).file, 'prds/d01_context.md');
  });

  test(
    '$_wb E04: a stale block and a block whose doc is gone are both named, the envelope is the first entry in file order, and the status is 64',
    () async {
      final root = await writeWriteProject();
      final text = getText(root, [story1]);
      docFile(root, story1).writeAsStringSync(
        readDoc(
          root,
          story1,
        ).replaceFirst('Sign in with', 'Please sign in with'),
      );
      const gone = 'prds/features/f09_gone/USER_STORY.md';

      final fault = refuse(
        root,
        '$text\n==> x (user_story) · $gone · base $emptyBaseHash <==\n# Gone\n',
      );

      expect(fault, refusedWith('base_mismatch'));
      expect(fault.entries.map((e) => e.code), [
        'base_mismatch',
        'doc_not_found',
      ]);
      final error = fault.toJson()['error']! as Map<String, Object?>;
      expect(error['code'], 'base_mismatch');
      expect(error['file'], story1);
      expect(error['key'], 'doc');
      expect(error['blocks'], hasLength(2));
    },
  );

  test(
    '$_wb E04: a refused line before both blocks gives the envelope its code, message, file, and line, with no key',
    () async {
      final root = await writeWriteProject();
      final text = getText(root, [story1]);
      docFile(root, story1).writeAsStringSync(
        readDoc(
          root,
          story1,
        ).replaceFirst('Sign in with', 'Please sign in with'),
      );

      final fault = refuse(root, 'stray text\n$text');

      expect(fault.entries.map((e) => (e.line, e.code)), [
        (1, 'argument_invalid'),
        (null, 'base_mismatch'),
      ]);
      final error = fault.toJson()['error']! as Map<String, Object?>;
      expect(error['code'], 'argument_invalid');
      expect(error['file'], 'batch.md');
      expect(error['line'], 1);
      expect(error, isNot(contains('key')));
      expect(fault.exitStatus, 64);
    },
  );

  test(
    '$_wb E04: a refused line alone, with no block left, still refuses and never succeeds empty',
    () async {
      final root = await writeWriteProject();

      final fault = refuse(
        root,
        '==> login/email_login (user_story) · $story1 <==\n# x\n',
      );

      expect(onlyEntry(fault).line, 1);
      expect(fault.exitStatus, 64);
    },
  );

  test(
    '$_wb E05: two blocks of one part refuse with argument_invalid, each block an entry naming the other by its line',
    () async {
      final root = await writeWriteProject();
      final block = getText(root, [_useCase]);
      final text =
          '$block\n${edit(block, 'Sign in with an email.', 'Sign in with a passkey.')}';

      final fault = refuse(root, text);

      expect(fault, refusedWith('argument_invalid'));
      expect(fault.entries.map((e) => (e.file, e.key)), [
        (story1, 'use_case'),
        (story1, 'use_case'),
      ]);
      expect(fault.entries[0].message, contains('line 6'));
      expect(fault.entries[1].message, contains('line 1'));
    },
  );

  test(
    '$_wb E05: a whole-doc block beside any other block of its doc refuses with argument_invalid, each block an entry naming the other by its line',
    () async {
      final root = await writeWriteProject();
      final text = '${getText(root, [story1])}\n${getText(root, [_useCase])}';
      final secondLine = getText(root, [story1]).split('\n').length + 1;

      final fault = refuse(root, text);

      expect(fault, refusedWith('argument_invalid'));
      expect(fault.entries.map((e) => (e.file, e.key)), [
        (story1, 'doc'),
        (story1, 'use_case'),
      ]);
      expect(fault.entries[0].message, contains('line $secondLine'));
      expect(fault.entries[1].message, contains('line 1'));
    },
  );

  test(
    '$_wb E05: a block refused for its text still takes part, so its twin is named too',
    () async {
      final root = await writeWriteProject();
      final open = edit(
        getText(root, [_useCase]),
        'Sign in with an email.',
        'Sign in with an email.\n\n```dart\ncode()\n',
      );
      final whole = getText(root, [story1]);
      final openLine = whole.split('\n').length + 1;

      final fault = refuse(root, '$whole\n$open');

      expect(fault.entries.map((e) => (e.key, e.code)), [
        ('doc', 'argument_invalid'),
        ('use_case', 'argument_invalid'),
      ]);
      expect(fault.entries[0].message, contains('line $openLine'));
      expect(fault.entries[1].message, contains('```'));
    },
  );

  test(
    '$_wb E05: two distinct sections of one doc are written in one write of that doc, with one draft',
    () async {
      final root = await writeWriteProject();
      var text = getText(root, [_signOutUseCase, _signOutCriteria]);
      text = edit(text, 'Sign out.', 'Sign out everywhere.');
      text = edit(text, 'a signed-in user', 'a signed-in user on two devices');

      final answer = runBatch(root, text);

      final doc = readDoc(root, story2);
      expect(doc, contains('## Use Case\n\nSign out everywhere.\n'));
      expect(doc, contains('a signed-in user on two devices'));
      expect('draft: true'.allMatches(doc), hasLength(1));
      expect(answer.text.trimRight().split('\n'), [
        '==> $_story2Line · $story2#use_case · base ${partBase(root, _signOutUseCase)} <==',
        '==> $_story2Line · $story2#acceptance_criteria · base ${partBase(root, _signOutCriteria)} <==',
      ]);
    },
  );

  test(
    '$_wb E06: a block under a field or a title naming line refuses with argument_invalid naming the block',
    () async {
      final root = await writeWriteProject();
      const fieldBlock =
          '==> $_story1Line · $story1 · field vision · base $emptyBaseHash <==\n- PV-02\n';
      const titleBlock =
          '==> $_story1Line · $story1 · title · base $emptyBaseHash <==\n# New\n';

      final fault = refuse(root, '$fieldBlock\n$titleBlock');

      expect(fault, refusedWith('argument_invalid'));
      expect(fault.entries.map((e) => (e.file, e.key)), [
        (story1, 'vision'),
        (story1, 'title'),
      ]);
    },
  );

  test(
    '$_wb E06: a whole-doc block writes the frontmatter and the title',
    () async {
      final root = await writeWriteProject();
      var text = getText(root, [story1]);
      text = edit(text, '  - PV-01\n', '  - PV-01\n  - PV-02\n');
      text = edit(
        text,
        '# Sign in with email',
        '# Sign in with email or a passkey',
      );

      runBatch(root, text);

      final doc = readDoc(root, story1);
      expect(doc, contains('vision:\n  - PV-01\n  - PV-02\n'));
      expect(doc, contains('# Sign in with email or a passkey\n'));
    },
  );

  group(
    '$_wb E07: a whole-doc block refuses what a single set of that part refuses',
    () {
      Future<(Directory, String)> story(String docPath) async {
        final root = await writeWriteProject();
        return (root, getText(root, [docPath]));
      }

      test('a changed draft, a changed approved, and a computed field are field_not_writable naming the field', () async {
        var (root, text) = await story(story1);
        var fault = refuse(root, edit(text, 'draft: true\n', ''));
        expect(
          (onlyEntry(fault).code, onlyEntry(fault).key),
          ('field_not_writable', 'draft'),
        );

        (root, text) = await story(story2);
        fault = refuse(root, edit(text, 'approved: "', 'approved: "0'));
        expect(
          (onlyEntry(fault).code, onlyEntry(fault).key),
          ('field_not_writable', 'approved'),
        );

        (root, text) = await story(loginFeature);
        fault = refuse(root, edit(text, 'vision:', 'status: planned\nvision:'));
        expect(
          (onlyEntry(fault).code, onlyEntry(fault).key),
          ('field_not_writable', 'status'),
        );
      });

      test('a field the doc type does not declare is field_unknown', () async {
        final (root, text) = await story(story1);
        final fault = refuse(
          root,
          edit(text, 'status: planned\n', 'status: planned\nbogus: 1\n'),
        );
        expect(
          (onlyEntry(fault).code, onlyEntry(fault).key),
          ('field_unknown', 'bogus'),
        );
      });

      test('a value its field type refuses is field_value_invalid', () async {
        final (root, text) = await story(story1);
        final fault = refuse(
          root,
          edit(text, 'status: planned', 'status: nonsense'),
        );
        expect(
          (onlyEntry(fault).code, onlyEntry(fault).key),
          ('field_value_invalid', 'status'),
        );
      });

      test('a removed required section is required_target naming it', () async {
        final (root, text) = await story(story1);
        final fault = refuse(
          root,
          edit(text, '## Use Case\n\nSign in with an email.\n\n', ''),
        );
        final entry = onlyEntry(fault);
        expect((entry.code, entry.key), ('required_target', 'use_case'));
        expect(entry.message, 'user_story requires the section use_case');
      });

      test('a removed required field is required_target naming it', () async {
        final (root, text) = await story(fr11);
        final fault = refuse(root, edit(text, 'verify_method: test\n', ''));
        expect(
          (onlyEntry(fault).code, onlyEntry(fault).key),
          ('required_target', 'verify_method'),
        );
      });
    },
  );

  test(
    '$_wb E06: a whole-doc block with its title removed refuses with argument_invalid as set --title does, and writes nothing',
    () async {
      final root = await writeWriteProject();
      final text = getText(root, [story1]);

      final fault = refuse(root, edit(text, '# Sign in with email\n\n', ''));

      expect(fault, refusedWith('argument_invalid'));
      final entry = onlyEntry(fault);
      expect((entry.file, entry.key), (story1, 'doc'));
      expect(entry.message, 'a title is one line; stdin held 0 lines');
    },
  );

  test(
    '$_wb E06: a whole-doc block holding a second title line refuses with argument_invalid as a lead holding a # line does, and writes nothing',
    () async {
      final root = await writeWriteProject();
      final text = getText(root, [story1]);

      final fault = refuse(
        root,
        edit(
          text,
          '# Sign in with email\n',
          '# Sign in with email\n\n# Another\n',
        ),
      );

      expect(fault, refusedWith('argument_invalid'));
      final entry = onlyEntry(fault);
      expect((entry.file, entry.key), (story1, 'doc'));
      expect(entry.message, contains('the lead holds the line "# Another"'));
    },
  );

  group(
    '$_wb INV-4: an output_ref-only whole-doc change keeps an approved doc approved whatever its file ends with',
    () {
      for (final (shape, ending) in [
        ('a trailing blank line', (String text) => '$text\n'),
        ('no final newline', (String text) => text.trimRight()),
      ]) {
        test(shape, () async {
          final original = ending(writeProject['docs/$fr11']!);
          final root = await writeWriteProject(extra: {'docs/$fr11': original});
          final text = edit(
            getText(root, [fr11]),
            'CredentialValidator',
            'CredentialChecker',
          );

          final answer = runBatch(root, text);

          final written = readDoc(root, fr11);
          expect(written, contains('CredentialChecker'));
          expect(written, isNot(contains('draft:')));
          expect(
            RegExp('approved: "[0-9a-f]{12}"').firstMatch(written)!.group(0),
            RegExp('approved: "[0-9a-f]{12}"').firstMatch(original)!.group(0),
          );
          expect(answer.json['blocks'], [containsPair('draft', false)]);
        });
      }
    },
  );

  test(
    '$_wb INV-4: a whole-doc block that changes the text before the title as well as an output_ref field marks an approved doc draft',
    () async {
      final root = await writeWriteProject();
      var text = getText(root, [fr11]);
      text = edit(text, 'CredentialValidator', 'CredentialChecker');
      text = edit(
        text,
        '# Validate credentials\n',
        'Preface text.\n\n# Validate credentials\n',
      );

      final answer = runBatch(root, text);

      expect(readDoc(root, fr11), contains('Preface text.'));
      expect(readDoc(root, fr11), contains('draft: true\n'));
      expect(answer.json['blocks'], [containsPair('draft', true)]);
    },
  );

  test(
    '$_wb E05: two section blocks and a whole-doc block of one doc are all refused, the whole-doc entry naming each of the two',
    () async {
      final root = await writeWriteProject();
      final sections = getText(root, [_useCase, _criteria]);
      final whole = getText(root, [story1]);
      final wholeLine = sections.split('\n').length + 1;

      final fault = refuse(root, '$sections\n$whole');

      expect(fault.entries.map((e) => (e.key, e.code)), [
        ('use_case', 'argument_invalid'),
        ('acceptance_criteria', 'argument_invalid'),
        ('doc', 'argument_invalid'),
      ]);
      expect(fault.entries[0].message, contains('line $wholeLine'));
      expect(fault.entries[1].message, contains('line $wholeLine'));
      expect(
        fault.entries[2].message,
        allOf(contains('lines 1,'), contains('line')),
      );
    },
  );

  test(
    '$_wb E05: a field block beside a whole-doc block of its doc is refused for its kind and the whole-doc block is refused for the overlap',
    () async {
      final root = await writeWriteProject();
      const fieldBlock =
          '==> $_story1Line · $story1 · field vision · base $emptyBaseHash <==\n- PV-02\n';
      final whole = getText(root, [story1]);

      final fault = refuse(root, '$fieldBlock\n$whole');

      expect(fault.entries.map((e) => (e.key, e.code)), [
        ('vision', 'argument_invalid'),
        ('doc', 'argument_invalid'),
      ]);
      expect(fault.entries[1].message, contains('line 1'));
    },
  );

  test(
    '$_wb E07: a whole-doc block that removes two sections of one key is written, not refused as stale',
    () async {
      final original =
          '${writeProject['docs/$story1']!}\n## Notes\n\nA.\n\n## Notes\n\nB.\n';
      final root = await writeWriteProject(extra: {'docs/$story1': original});
      final text = edit(
        getText(root, [story1]),
        '\n## Notes\n\nA.\n\n## Notes\n\nB.\n',
        '',
      );

      runBatch(root, text);

      expect(readDoc(root, story1), writeProject['docs/$story1']);
    },
  );

  test(
    '$_wb E08: a section block holding the ## line of another section outside fenced code refuses with argument_invalid',
    () async {
      final root = await writeWriteProject();
      final text = edit(
        getText(root, [_useCase]),
        'Sign in with an email.\n',
        'Sign in with an email.\n\n## Acceptance Criteria\n\nx\n',
      );

      final fault = refuse(root, text);

      expect(fault, refusedWith('argument_invalid'));
      expect(onlyEntry(fault).key, 'use_case');
    },
  );

  test(
    '$_wb E08: a section key its doc neither holds nor defines refuses with section_not_found',
    () async {
      final root = await writeWriteProject();

      final fault = refuse(
        root,
        '==> $_story1Line · $story1#nosuch_section · base $emptyBaseHash <==\nx\n',
      );

      expect(fault, refusedWith('section_not_found'));
      expect(onlyEntry(fault).key, 'nosuch_section');
    },
  );

  test(
    '$_wb E09: a whole-doc block that adds a ## section its template does not define is written, and check reports section_undeclared',
    () async {
      final root = await writeWriteProject();
      final text =
          '${getText(root, [story1])}\n## Extra\n\nA note the template lacks.\n';

      runBatch(root, text);

      expect(
        readDoc(root, story1),
        contains('## Extra\n\nA note the template lacks.\n'),
      );
      expect(spots(checkOf(root), FindingKind.sectionUndeclared), isNotEmpty);
    },
  );

  test(
    '$_wb E10: a fence that opens in a block and stays open to the end of the file refuses naming that block, beside every other refused line and block',
    () async {
      final root = await writeWriteProject();
      final stale = getText(root, [story1]);
      docFile(root, story1).writeAsStringSync(
        readDoc(
          root,
          story1,
        ).replaceFirst('Sign in with', 'Please sign in with'),
      );
      final open = edit(
        getText(root, [_signOutUseCase]),
        'Sign out.',
        'Sign out.\n\n```dart\ncode()\n',
      );

      final fault = refuse(root, 'stray\n$stale\n$open');

      expect(fault.exitStatus, 64);
      expect(fault.entries.map((e) => (e.code, e.line, e.key)), [
        ('argument_invalid', 1, null),
        ('base_mismatch', null, 'doc'),
        ('argument_invalid', null, 'use_case'),
      ]);
      expect(fault.entries.last.file, story2);
      expect(fault.entries.last.message, contains('```'));
    },
  );

  test(
    '$_wb E10: a fence in a list item that the next naming line closes is open in its block alone and refuses',
    () async {
      final root = await writeWriteProject();
      final first = edit(
        getText(root, [_useCase]),
        'Sign in with an email.\n',
        'Sign in with an email.\n\n- item\n  ```dart\n  code()\n',
      );
      final second = getText(root, [_signOutUseCase]);

      final fault = refuse(root, '$first\n$second');

      expect(onlyEntry(fault).key, 'use_case');
      expect(onlyEntry(fault).code, 'argument_invalid');
    },
  );

  test(
    '$_wb E11: an unchanged block prints its naming line with its base and · unchanged, the doc keeps its bytes, and a batch of only unchanged blocks writes no journal',
    () async {
      final root = await writeWriteProject();
      final before = docBytes(root);
      final text = getText(root, [
        story1,
        _signOutCriteria,
        fr11,
        'user_story:login/reset_password#_lead',
      ]);

      final answer = writeInNoHome(
        root,
        (s) => answerSetBatch(s, parseBatchFile('batch.md', text)),
      );

      expect(docBytes(root), before);
      final lines = answer.text.trimRight().split('\n');
      expect(lines, hasLength(4));
      for (final line in lines) {
        expect(
          line,
          matches(RegExp(r'^==> .* · base [0-9a-f]{12} · unchanged <==$')),
        );
      }
      expect(
        answer.json['blocks'],
        everyElement(containsPair('written', false)),
      );
      expect(File(journalPathOf(root)).existsSync(), isFalse);
    },
  );

  test(
    '$_wb E11: an unchanged section block beside a changed block of its doc still prints its unchanged line, and the doc is written',
    () async {
      final root = await writeWriteProject();
      var text = getText(root, [_signOutUseCase, _signOutCriteria]);
      text = edit(text, 'a signed-in user', 'a signed-in user on two devices');

      final answer = runBatch(root, text);

      final lines = answer.text.trimRight().split('\n');
      expect(lines[0], endsWith(' · unchanged <=='));
      expect(lines[1], isNot(contains('unchanged')));
      expect(answer.json['blocks'], [
        containsPair('written', false),
        containsPair('written', true),
      ]);
      expect(readDoc(root, story2), contains('draft: true\n'));
    },
  );

  test(
    '$_wb E11: a doc not in format layout keeps its bytes and its approval when its blocks come back unedited',
    () async {
      final root = await writeWriteProject();
      final approved = readDoc(
        root,
        story2,
      ).replaceFirst('## Use Case\n\n', '## Use Case\n');
      docFile(root, story2).writeAsStringSync(approved);

      for (final names in [
        [story2],
        [_signOutUseCase],
      ]) {
        final text = getText(root, names);
        final answer = writeInNoHome(
          root,
          (s) => answerSetBatch(s, parseBatchFile('batch.md', text)),
        );
        expect(answer.json['blocks'], [containsPair('written', false)]);
        expect(
          answer.json['blocks'],
          everyElement(containsPair('draft', false)),
        );
      }
      expect(readDoc(root, story2), approved);
      expect(readDoc(root, story2), isNot(contains('draft:')));
    },
  );

  test(
    '$_wb E12: a whole-doc block is checked against bases.doc, so a change to any part since the read makes it stale',
    () async {
      final root = await writeWriteProject();
      final text = edit(
        getText(root, [story1]),
        'Sign in with an email.',
        'Sign in with a passkey.',
      );
      expect(text, contains('base ${docBase(root, story1)} <=='));
      docFile(
        root,
        story1,
      ).writeAsStringSync(readDoc(root, story1).replaceFirst('PV-01', 'PV-09'));

      final fault = refuse(root, text);

      expect(fault, refusedWith('base_mismatch', status: 75));
    },
  );

  test(
    '$_wb E12: bases.doc hashes the doc with LF line ends, so a CRLF doc with a BOM round-trips unchanged and an edit keeps both',
    () async {
      final lf = writeProject['docs/$story2']!;
      final root = await writeWriteProject(
        extra: {'docs/$story2': '\uFEFF${lf.replaceAll('\n', '\r\n')}'},
      );
      final bytes = docFile(root, story2).readAsBytesSync();
      final text = getText(root, [story2]);
      expect(text, contains('base ${baseHashOf(lf)} <=='));

      final unchanged = writeInNoHome(
        root,
        (s) => answerSetBatch(s, parseBatchFile('batch.md', text)),
      );
      expect(docFile(root, story2).readAsBytesSync(), bytes);
      expect(unchanged.json['blocks'], [containsPair('written', false)]);

      runBatch(root, edit(text, 'Sign out.', 'Sign out everywhere.'));

      final written = docFile(root, story2).readAsBytesSync();
      expect(written.take(3), [0xEF, 0xBB, 0xBF]);
      final decoded = utf8.decode(written.skip(3).toList());
      expect(decoded, contains('Sign out everywhere.'));
      expect(decoded, isNot(matches(RegExp(r'(?<!\r)\n'))));
      expect(LineEnding.of(decoded), LineEnding.crlf);
    },
  );

  test(
    '$_wb E12: a CRLF doc written by a section block keeps its line ends',
    () async {
      final lf = writeProject['docs/$story2']!;
      final root = await writeWriteProject(
        extra: {'docs/$story2': lf.replaceAll('\n', '\r\n')},
      );
      final text = edit(
        getText(root, [_signOutUseCase]),
        'Sign out.',
        'Sign out now.',
      );

      runBatch(root, text);

      final written = readDoc(root, story2);
      expect(written, contains('Sign out now.'));
      expect(written, isNot(matches(RegExp(r'(?<!\r)\n'))));
    },
  );

  test(
    '$_wb E14: a run stopped after it wrote its journal and before its last doc is finished by the next write command, which leaves a doc edited after the stop as it is',
    () async {
      final root = await writeWriteProject();
      final records = Directory('${testHome().path}/.specstone/journals');
      var text = getText(root, [story1, story3, fr31]);
      text = edit(text, 'Sign in with an email.', 'Sign in with a passkey.');
      text = edit(text, 'Reset a password.', 'Reset the password.');
      text = edit(text, 'send a link', 'send a reset link');
      final stuck = docFile(root, story3).parent;
      Process.runSync('chmod', ['555', stuck.path]);
      addTearDown(() => Process.runSync('chmod', ['755', stuck.path]));

      expect(() => runBatch(root, text), throwsA(isA<RenderFault>()));

      expect(readDoc(root, story1), contains('a passkey'));
      final journal =
          jsonDecode(File(journalPathOf(root)).readAsStringSync()) as Map;
      final steps = (journal['steps']! as List).cast<Map<String, Object?>>();
      expect(steps.map((s) => (s['write']! as Map)['path']), [
        'docs/$story1',
        'docs/$story3',
        'docs/$fr31',
      ]);
      expect(
        steps.map((s) => (s['write']! as Map)['before']),
        everyElement(isA<String>()),
      );
      expect(records.listSync(), hasLength(1));

      Process.runSync('chmod', ['755', stuck.path]);
      final edited = readDoc(
        root,
        fr31,
      ).replaceFirst('send a link', 'send a link by mail');
      docFile(root, fr31).writeAsStringSync(edited);
      writeIn(root, (_) {});

      expect(readDoc(root, story3), contains('Reset the password.'));
      expect(readDoc(root, fr31), edited);
      expect(File(journalPathOf(root)).existsSync(), isFalse);
      expect(records.listSync(), isEmpty);
    },
    skip: unreadablePathSkipReason() ?? false,
  );

  test(
    '$_wb E14: a stopped journal of guarded write steps is finished by the next write command, which leaves a doc edited after the stop as it is',
    () async {
      final root = await writeWriteProject();
      final twin = await writeWriteProject();
      var text = getText(twin, [story1, story3, fr31]);
      text = edit(text, 'Sign in with an email.', 'Sign in with a passkey.');
      text = edit(text, 'Reset a password.', 'Reset the password.');
      text = edit(text, 'send a link', 'send a reset link');
      runBatch(twin, text);
      final docs = [story1, story3, fr31];
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

      writeIn(root, (_) {});

      expect(readDoc(root, story1), readDoc(twin, story1));
      expect(readDoc(root, story3), readDoc(twin, story3));
      expect(readDoc(root, fr31), edited);
      expect(File(journalPathOf(root)).existsSync(), isFalse);
    },
  );

  test(
    '$_wb E15: no home folder to record the journal in refuses with output_not_writable before the first change',
    () async {
      final root = await writeWriteProject();
      final before = docBytes(root);
      final text = edit(
        getText(root, [story1]),
        'Sign in with an email.',
        'Sign in with a passkey.',
      );

      expect(
        () => writeInNoHome(
          root,
          (s) => answerSetBatch(s, parseBatchFile('batch.md', text)),
        ),
        throwsA(
          isA<RenderFault>()
              .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
              .having((f) => f.exitStatus, 'exit', 73)
              .having(
                (f) => f.message,
                'message',
                'cannot write .specstone/trash/journal.json: no home folder to record it in',
              ),
        ),
      );

      expect(docBytes(root), before);
      expect(Directory('${root.path}/.specstone/trash').existsSync(), isFalse);
    },
  );

  test(
    '$_finish E12: a batch in a project whose roots wait for the trust record of the Owner refuses with the trust text before any change',
    () async {
      final base = await writeTree({
        for (final MapEntry(:key, :value) in writeProject.entries)
          if (key.startsWith('docs/'))
            'ext/${key.substring(5)}': value
          else
            'src/clone/$key': value,
      });
      createRelativeLink('${base.path}/src/clone/docs', '../../ext');
      final clone = Directory('${base.path}/src/clone');
      final before = treeBytes(Directory('${base.path}/ext'));
      final text = edit(
        getText(clone, [story1]),
        'Sign in with an email.',
        'Sign in with a passkey.',
      );

      expect(
        () => runBatch(clone, text),
        throwsA(
          isA<RenderFault>()
              .having((f) => f.exitStatus, 'exit', 73)
              .having((f) => f.file, 'file', MoveJournal.journalPath)
              .having(
                (f) => f.message,
                'message',
                endsWith('run specstone trust at a terminal to allow it'),
              ),
        ),
      );

      expect(treeBytes(Directory('${base.path}/ext')), before);
      RootTrust.locate(clone, homeDirectory: testHome()).record();
      runBatch(clone, text);
      expect(
        File('${base.path}/ext/$story1').readAsStringSync(),
        contains('a passkey'),
      );
    },
    skip: Platform.isWindows ? 'a link needs a privilege on Windows' : false,
  );

  test(
    '$_wb E16: a doc the formatter refuses once its blocks are spliced in is written as spliced, every other byte kept',
    () async {
      final original =
          '${writeProject['docs/$story1']!}\n## Extra\n\nraw   text\n';
      final root = await writeWriteProject(extra: {'docs/$story1': original});
      final text = edit(
        getText(root, [_useCase]),
        'Sign in with an email.',
        'Sign in with a passkey.',
      );

      runBatch(root, text);

      expect(
        readDoc(root, story1),
        original.replaceFirst(
          'Sign in with an email.',
          'Sign in with a passkey.',
        ),
      );
    },
  );

  test(
    '$_wb E16: a doc the formatter refuses, with trailing blank lines, compares the spliced text with the text on disk, so its blocks come back unchanged',
    () async {
      final original =
          '${writeProject['docs/$story1']!}\n## Extra\n\nraw   text\n\n\n';
      final root = await writeWriteProject(extra: {'docs/$story1': original});

      for (final names in [
        [story1],
        [_useCase],
      ]) {
        final text = getText(root, names);
        final answer = writeInNoHome(
          root,
          (s) => answerSetBatch(s, parseBatchFile('batch.md', text)),
        );
        expect(answer.json['blocks'], [containsPair('written', false)]);
      }
      expect(readDoc(root, story1), original);
    },
  );

  test(
    '$_wb E03: a doc deleted after the names resolved and before the lock refuses with doc_not_found naming the block',
    () async {
      final root = await writeWriteProject();
      final text = getText(root, [story1, story3]);

      final fault = writeIn(root, (s) {
        docFile(root, story3).deleteSync();
        try {
          answerSetBatch(s, parseBatchFile('batch.md', text));
        } on BatchFault catch (fault) {
          return fault;
        }
        fail('the batch was not refused');
      });

      expect(fault.entries.map((e) => (e.code, e.file, e.key)), [
        ('doc_not_found', story3, 'doc'),
      ]);
    },
  );

  test(
    '$_wb: a section block with empty text removes an optional section and prints the base of an absent section',
    () async {
      final withRules = writeProject['docs/$story1']!.replaceFirst(
        '## Acceptance Criteria',
        '## Rules\n\n- BR-01 One account per email.\n\n## Acceptance Criteria',
      );
      final root = await writeWriteProject(extra: {'docs/$story1': withRules});
      const rules = 'user_story:login/email_login#rules';
      final line = getText(root, [rules]).split('\n').first;

      final answer = runBatch(root, '$line\n');

      expect(readDoc(root, story1), isNot(contains('## Rules')));
      expect(answer.json['blocks'], [containsPair('base', emptyBaseHash)]);
    },
  );

  test('$_wb: a lead block writes the lead and prints its new base', () async {
    final root = await writeWriteProject();
    const lead = 'user_story:login/reset_password#_lead';
    final line = getText(root, [lead]).split('\n').first;

    final answer = runBatch(root, '$line\nAn intro to the story.\n');

    expect(
      readDoc(root, story3),
      contains('# Reset password\n\nAn intro to the story.\n\n## Use Case'),
    );
    expect(answer.json['blocks'], [containsPair('base', partBase(root, lead))]);
    expect(answer.json['blocks'], [containsPair('written', true)]);
  });

  test(
    '$_wb: two section blocks of one doc, the first adding a template section the doc lacks and the second rewriting a section after it, land in one write of that doc, each checked against the doc on disk',
    () async {
      final root = await writeWriteProject();
      const rules = 'user_story:login/email_login#rules';
      final text =
          '==> $_story1Line · $story1#rules · base $emptyBaseHash <==\n'
          '## Rules\n- BR-01 One account per email.\n\n'
          '${edit(getText(root, [_criteria]), 'a registered email', 'a registered email and a password')}';

      final answer = runBatch(root, text);

      final doc = readDoc(root, story1);
      expect(
        doc,
        contains(
          '## Use Case\n\nSign in with an email.\n\n## Rules\n\n- BR-01 One account per email.\n\n## Acceptance Criteria\n',
        ),
      );
      expect(doc, contains('a registered email and a password'));
      expect(answer.text.trimRight().split('\n'), [
        '==> $_story1Line · $story1#rules · base ${partBase(root, rules)} <==',
        '==> $_story1Line · $story1#acceptance_criteria · base ${partBase(root, _criteria)} <==',
      ]);
    },
  );

  test(
    '$_wb INV-4: a whole-doc block that changes only an output_ref field leaves an approved doc approved with its approval hash intact',
    () async {
      final root = await writeWriteProject();
      final text = edit(
        getText(root, [fr11]),
        'credential_validator.dart:CredentialValidator',
        'credential_validator.dart:CredentialChecker',
      );

      final answer = runBatch(root, text);

      expect(readDoc(root, fr11), isNot(contains('draft:')));
      expect(readDoc(root, fr11), contains('CredentialChecker'));
      expect(answer.json['blocks'], [containsPair('draft', false)]);
      expect(spots(checkOf(root), FindingKind.approvalStale), isEmpty);
    },
  );

  test(
    '$_wb INV-4: a whole-doc block that changes an output_ref field and the body marks the doc draft',
    () async {
      final root = await writeWriteProject();
      var text = edit(
        getText(root, [fr11]),
        'CredentialValidator',
        'CredentialChecker',
      );
      text = edit(text, 'check the email', 'check the email twice, then');

      runBatch(root, text);

      expect(readDoc(root, fr11), contains('draft: true\n'));
    },
  );

  test(
    '$_serialize E05: a lock the batch cannot take propagates as index_busy, unwrapped',
    () async {
      final root = await writeWriteProject();
      final anHourAgo = DateTime.now().subtract(const Duration(hours: 1));
      for (final file in root.listSync(recursive: true).whereType<File>()) {
        file.setLastModifiedSync(anHourAgo);
      }
      writeIn(root, (_) {}); // creates the index
      final text = edit(
        getText(root, [story1]),
        'Sign in with an email.',
        'Sign in with a passkey.',
      );
      final other = IndexStore.open(root, busyTimeout: Duration.zero);
      addTearDown(other.close);

      other.write(() {
        expect(
          () => writeIn(
            root,
            (s) => answerSetBatch(s, parseBatchFile('batch.md', text)),
            busyTimeout: Duration.zero,
          ),
          throwsA(
            isA<IndexFault>().having(
              (f) => f.code,
              'code',
              IndexFaultCode.indexBusy,
            ),
          ),
        );
      });
    },
  );

  test(
    '$_wb: a batch file with no block refuses at the file level and writes nothing',
    () async {
      final root = await writeWriteProject();

      expect(
        () => runBatch(root, 'text with no naming line\n'),
        throwsA(
          isA<BatchFault>().having((f) => f.isFileLevel, 'isFileLevel', isTrue),
        ),
      );
    },
  );

  test(
    '$_wb: a block text holding a naming-line shape at column 0 outside a fence refuses with nothing written; a fenced or indented one is text',
    () async {
      final root = await writeWriteProject();
      const shaped = '==> other (feature) · prds/f.md#problem · base zz <==';
      final text = getText(root, [_useCase]);
      final refused = refuse(root, '${text.trimRight()}\n\n$shaped\n');
      expect(onlyEntry(refused).code, 'argument_invalid');
      expect(onlyEntry(refused).message, contains('naming line'));

      final answer = runBatch(
        root,
        '${text.trimRight()}\n\n```text\n$shaped\n```\n\n    $shaped\n',
      );
      expect(answer.json['blocks'], [containsPair('written', true)]);
      expect(readDoc(root, story1), contains('\n    $shaped\n'));
    },
  );

  test(
    '$_wb E11: an unedited block for a template section the doc lacks, optional or required, is unchanged, and an approved doc stays approved',
    () async {
      final root = await writeWriteProject();
      final noUseCase = readDoc(
        root,
        story1,
      ).replaceFirst('## Use Case\n\nSign in with an email.\n\n', '');
      docFile(root, story1).writeAsStringSync(noUseCase);
      final names = <String>[];
      for (final docPath in [story1, story2, fr11, loginFeature, loginArch]) {
        final sections =
            (getDoc(root, docPath)['bases']! as Map)['sections']! as Map;
        names.addAll([
          for (final MapEntry(:key, :value) in sections.entries)
            if (value == emptyBaseHash) '$docPath#$key',
        ]);
      }
      expect(names.length, greaterThan(4));
      expect(names, contains('$story1#use_case'));
      final before = docBytes(root);
      final text = getText(root, names);
      expect(text, isNot(contains('\n## ')));

      final answer = writeInNoHome(
        root,
        (s) => answerSetBatch(s, parseBatchFile('batch.md', text)),
      );

      expect(docBytes(root), before);
      final lines = answer.text.trimRight().split('\n');
      expect(lines, hasLength(names.length));
      for (final line in lines) {
        expect(line, endsWith(' · unchanged <=='));
      }
      expect(File(journalPathOf(root)).existsSync(), isFalse);
    },
  );
}
