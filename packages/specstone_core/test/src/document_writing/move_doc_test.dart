import 'dart:io';

import 'package:specstone_core/src/document_writing/move_doc.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:test/test.dart';

import '../../helpers/write_fixture.dart';

void main() {
  ReadAnswer reorder(Directory root, String address, String place) =>
      writeIn(root, (s) => answerReorder(s, address, place: place));

  const f = 'prds/features/f01_login';

  test('f02/us05/s1, f02/us05/fr01, f02/us05/fr01/e01, f02/us05/fr02, f02/us05/fr02/e01, dw-s03/inv8, dw-s03/inv10: the third story moves to the top and every link follows', () async {
    final root = await writeWriteProject();
    final answer = reorder(root, 'user_story:login/reset_password', '1');
    expect(
      answer.text,
      'moved $f/us03_reset_password/ to $f/us01_reset_password/\n'
      'moved $f/us01_email_login/ to $f/us02_email_login/\n'
      'moved $f/us02_sign_out/ to $f/us03_sign_out/\n'
      'rewrote $f/us01_reset_password/USER_STORY.md\n'
      'rewrote $f/us02_email_login/fr02_lock_after_failures.md\n',
    );
    expect(
      readDoc(root, '$f/us02_email_login/fr02_lock_after_failures.md'),
      contains('](../us01_reset_password/USER_STORY.md#use-case)'),
    );
    expect(
      readDoc(root, '$f/us01_reset_password/USER_STORY.md'),
      contains('](../us03_sign_out/USER_STORY.md)'),
    );
    expect(
      writeIn(root, (s) => s.target('user_story:login/reset_password').docPath),
      '$f/us01_reset_password/USER_STORY.md',
    );
  });

  test('f02/us05/s4, f02/us05/fr01/e05, f02/us05/fr02/e03: a feature moves with its spec folder, and untyped referrers follow', () async {
    final root = await writeWriteProject();
    expect(reorder(root, 'feature:signup', '1').json, {
      'moved': [
        {
          'from': 'prds/features/f02_signup/',
          'to': 'prds/features/f01_signup/',
        },
        {'from': 'specs/f02_signup/', 'to': 'specs/f01_signup/'},
        {'from': 'prds/features/f01_login/', 'to': 'prds/features/f02_login/'},
        {'from': 'specs/f01_login/', 'to': 'specs/f02_login/'},
      ],
      'rewritten': ['prds/FEATURES.md', 'prds/d01_context.md'],
    });
    expect(
      readDoc(root, 'prds/d01_context.md'),
      contains('](features/f01_signup/FEATURE.md)'),
    );
  });

  test('f02/us05/s5, f02/us05/fr01/e06: a place outside the list is position_out_of_range, and nothing moves', () async {
    final root = await writeWriteProject();
    for (final place in ['0', '4']) {
      expect(
        () => reorder(root, 'user_story:login/reset_password', place),
        throwsA(
          isA<WriteFault>()
              .having((f) => f.code, 'code', WriteFaultCode.positionOutOfRange)
              .having(
                (f) => f.message,
                'message',
                'user_story:login/reset_password cannot move to place $place: the places run from 1 to 3',
              ),
        ),
      );
    }
    expect(hasDoc(root, story3), isTrue);
  });

  test('f02/us05/s6, f02/us05/fr01/e08: a doc type with no number is doc_type_not_movable', () async {
    final root = await writeWriteProject();
    expect(
      () => reorder(root, 'persona:buyer', '1'),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.docTypeNotMovable)
            .having(
              (f) => f.message,
              'message',
              'persona docs carry no number, so reorder cannot move them',
            ),
      ),
    );
  });

  test(
    'f02/us05/s2, f02/us05/fr01/e02: the gaps a delete left close',
    () async {
      final root = await writeWriteProject(
        without: {'docs/$story2'},
        extra: {'docs/$f/us04_audit/USER_STORY.md': '# Audit\n'},
      );
      reorder(root, 'user_story:login/audit', '3');
      expect(hasDoc(root, '$f/us01_email_login/USER_STORY.md'), isTrue);
      expect(hasDoc(root, '$f/us02_reset_password/USER_STORY.md'), isTrue);
      expect(hasDoc(root, '$f/us03_audit/USER_STORY.md'), isTrue);
      expect(hasDoc(root, story3), isFalse);
    },
  );

  test(
    'f02/us05/fr01/e03: the place it holds, with no gap, moves nothing',
    () async {
      final root = await writeWriteProject();
      final answer = reorder(root, 'user_story:login/email_login', '1');
      expect(answer.text, '');
      expect(answer.json, {'moved': <Object>[], 'rewritten': <Object>[]});
      expect(hasDoc(root, story1), isTrue);
    },
  );

  test(
    'f02/us05/fr01/e04: the FRs and the nfs under one story number apart',
    () async {
      final root = await writeWriteProject(
        extra: {
          'docs/$f/us03_reset_password/nf01_fast_link.md': '# Fast link\n',
        },
      );
      reorder(root, 'fr:login/reset_password/expire_reset_link', '1');
      expect(
        hasDoc(root, '$f/us03_reset_password/fr01_expire_reset_link.md'),
        isTrue,
      );
      expect(
        hasDoc(root, '$f/us03_reset_password/fr02_send_reset_link.md'),
        isTrue,
      );
      expect(hasDoc(root, '$f/us03_reset_password/nf01_fast_link.md'), isTrue);
      expect(
        readDoc(root, '$f/us03_reset_password/fr01_expire_reset_link.md'),
        contains('](fr02_send_reset_link.md)'),
      );
    },
  );

  test(
    'f02/us05/fr01/e07: parsePlace refuses a missing or non-integer place',
    () {
      expect(parsePlace('0'), 0);
      expect(parsePlace('12'), 12);
      expect(
        () => parsePlace(null),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.argumentMissing)
              .having(
                (f) => f.message,
                'message',
                'reorder needs a place, such as specstone reorder user_story:login/reset_password --to 1',
              ),
        ),
      );
      for (final value in [
        '',
        'one',
        '-1',
        '1.5',
        ' 1',
        '٣',
        '99999999999999999999',
      ]) {
        expect(
          () => parsePlace(value),
          throwsA(
            isA<IndexFault>()
                .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
                .having(
                  (f) => f.message,
                  'message',
                  '--to takes a whole number, got $value',
                ),
          ),
        );
      }
    },
  );

  test('f02/us05/s3, f02/us05/fr01/e09, f02/us05/fr02/e07: an approved doc moves with no Owner step, and no moved or rewritten doc is marked draft', () async {
    final root = await writeWriteProject();
    final before = readDoc(root, story2);
    reorder(root, 'user_story:login/sign_out', '1');
    final moved = readDoc(root, '$f/us01_sign_out/USER_STORY.md');
    expect(moved, before);
    final rewritten = readDoc(root, '$f/us03_reset_password/USER_STORY.md');
    expect(rewritten, contains('](../us01_sign_out/USER_STORY.md)'));
    expect('draft: true'.allMatches(rewritten), hasLength(1));
    expect(
      'draft: true'.allMatches(
        readDoc(root, '$f/us02_email_login/USER_STORY.md'),
      ),
      hasLength(1),
    );
  });

  test('f02/us05/fr02/e05, f02/us05/fr02/e06: reorder leaves doc_ref values and implements pointers as written', () async {
    final root = await writeWriteProject();
    final personaBefore = readDoc(root, persona);
    final storyBefore = readDoc(root, story1);
    reorder(root, 'user_story:login/reset_password', '1');
    expect(readDoc(root, persona), personaBefore);
    expect(readDoc(root, '$f/us02_email_login/USER_STORY.md'), storyBefore);
    expect(
      readDoc(root, '$f/us02_email_login/fr01_validate_credentials.md'),
      contains(
        '  - app/lib/src/login/credential_validator.dart:CredentialValidator\n',
      ),
    );
  });

  test('f02/us04/fr03/e03, dw-s03/inv9, nfr-di01: a reorder journal stopped mid-way is finished by the next write', () async {
    final root = await writeWriteProject();
    const moves = [
      ('us03_reset_password', 'us01_reset_password'),
      ('us01_email_login', 'us02_email_login'),
      ('us02_sign_out', 'us03_sign_out'),
    ];
    String path(String name) => 'docs/$f/$name';
    String stage(int i) => '.specstone/trash/stage/$i';
    const linkFile = '$f/us01_email_login/fr02_lock_after_failures.md';
    final linkText = readDoc(root, linkFile);
    writeJournal(root, [
      for (final (i, (from, _)) in moves.indexed)
        MoveStep(path(from), stage(i)),
      for (final (i, (_, to)) in moves.indexed) MoveStep(stage(i), path(to)),
      WriteStep(
        'docs/$f/us02_email_login/fr02_lock_after_failures.md',
        linkText.replaceAll('us03_reset_password', 'us01_reset_password'),
      ),
    ]);
    // The first three moves ran before the stop.
    for (final (i, (from, _)) in moves.indexed) {
      final target = '${root.path}/${stage(i)}';
      Directory(target).parent.createSync(recursive: true);
      Directory('${root.path}/${path(from)}').renameSync(target);
    }

    writeIn(root, (_) {});

    for (final (_, to) in moves) {
      expect(Directory('${root.path}/${path(to)}').existsSync(), isTrue);
    }
    expect(Directory('${root.path}/.specstone/trash').existsSync(), isFalse);
    expect(
      readDoc(root, '$f/us02_email_login/fr02_lock_after_failures.md'),
      contains('](../us01_reset_password/USER_STORY.md#use-case)'),
    );
  });
}
