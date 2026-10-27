import 'dart:io';

import 'package:specstone_core/src/document_writing/move_doc.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:test/test.dart';

import '../../helpers/posix_modes.dart';
import '../../helpers/write_fixture.dart';

void main() {
  ReadAnswer reorder(Directory root, String address, String place) =>
      writeIn(root, (s) => answerReorder(s, address, place: place));

  ReadAnswer rename(Directory root, String address, String slug) =>
      writeIn(root, (s) => answerRename(s, address, slug: slug));

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

  test('fix round 2, f02/us05/fr01, dw-s03/inv9: a reorder stages under .specstone/trash/stage, never in the project root', () async {
    final root = await writeWriteProject();
    final answer = reorder(root, 'user_story:login/reset_password', '1');
    expect(answer.text, startsWith('moved '));
    expect(
      Directory('${root.path}/MoveJournal.stagePath').existsSync(),
      isFalse,
    );
    expect(
      Directory('${root.path}/${MoveJournal.stagePath}').existsSync(),
      isFalse,
    );
  });

  test('fix round 2, f02/us04/fr03/e03, dw-s03/inv9: a stopped reorder replays and the phase-1 stage skip fires on a taken slot', () async {
    final root = await writeWriteProject();
    final moves = [
      ('us03_reset_password', 'us01_reset_password'),
      ('us01_email_login', 'us02_email_login'),
      ('us02_sign_out', 'us03_sign_out'),
    ];
    String path(String name) => 'docs/$f/$name';
    String stage(int i) => '${MoveJournal.stagePath}/$i';
    writeJournal(root, [
      for (final (i, (from, _)) in moves.indexed)
        MoveStep(path(from), stage(i)),
      for (final (i, (_, to)) in moves.indexed) MoveStep(stage(i), path(to)),
    ]);
    // The run stopped after one phase-1 move, and slot 0 already holds its doc.
    for (final (i, (from, _)) in moves.indexed.take(1)) {
      Directory('${root.path}/${stage(i)}/../'.replaceAll('../', ''))
          .createSync(recursive: true);
      Directory('${root.path}/${path(from)}')
          .renameSync('${root.path}/${stage(i)}');
    }

    writeIn(root, (_) {});

    for (final (_, to) in moves) {
      expect(Directory('${root.path}/${path(to)}').existsSync(), isTrue);
    }
    expect(Directory('${root.path}/.specstone/trash').existsSync(), isFalse);
    expect(
      Directory('${root.path}/MoveJournal.stagePath').existsSync(),
      isFalse,
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

  test('f02/us05/fr01/e06: a doc gone from disk since the index is doc_not_found, not a crash', () async {
    Future<void> expectNotFound(void Function(WriteSession) body) async {
      final fresh = await writeWriteProject();
      expect(
        () => writeIn(fresh, (s) {
          Directory('${fresh.path}/docs/$f/us03_reset_password')
              .deleteSync(recursive: true);
          body(s);
        }),
        throwsA(
          isA<IndexFault>().having(
            (e) => e.code,
            'code',
            IndexFaultCode.docNotFound,
          ),
        ),
      );
    }

    await expectNotFound(
      (s) => answerReorder(s, 'user_story:login/reset_password', place: '1'),
    );
    await expectNotFound(
      (s) => answerRename(s, 'user_story:login/reset_password', slug: 'x'),
    );
  });

  test('f02/us05/fr02, dw-s03/inv10, final Important 2: a read-only rewrite target stops a rename', () async {
    final root = await writeWriteProject();
    final linker = docFile(root, fr12);
    Process.runSync('chmod', ['444', linker.path]);
    addTearDown(() => Process.runSync('chmod', ['644', linker.path]));
    final before = readDoc(root, fr12);
    expect(
      () => rename(root, 'user_story:login/reset_password', 'recover'),
      throwsA(
        isA<RenderFault>()
            .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
            .having(
              (f) => f.message,
              'message',
              'cannot write $fr12: read-only',
            ),
      ),
    );
    expect(readDoc(root, fr12), before);
    expect(hasDoc(root, story3), isTrue);
    expect(Directory('${root.path}/.specstone/trash').existsSync(), isFalse);
  }, skip: unreadablePathSkipReason() ?? false);

  test('f02/us06/s1, f02/us06/fr01, f02/us06/fr01/e01, f02/us06/fr01/e08, f02/us05/fr02, dw-s03/inv10: a story takes a new slug, keeps its number and title, and links follow', () async {
    final root = await writeWriteProject();
    expect(
      rename(root, 'user_story:login/reset_password', 'recover_account').text,
      'moved $f/us03_reset_password/ to $f/us03_recover_account/\n'
      'rewrote $f/us01_email_login/fr02_lock_after_failures.md\n',
    );
    expect(
      readDoc(root, '$f/us03_recover_account/USER_STORY.md'),
      contains('\n# Reset password\n'),
    );
    expect(
      readDoc(root, fr12),
      contains('](../us03_recover_account/USER_STORY.md#use-case)'),
    );
    expect(
      writeIn(
        root,
        (s) => s.target('user_story:login/recover_account').docPath,
      ),
      '$f/us03_recover_account/USER_STORY.md',
    );
  });

  test('f02/us06/s2, f02/us06/fr01/e02, f02/us06/fr02/e02: a feature renames with its spec folder, and names under it follow in doc_ref values', () async {
    final root = await writeWriteProject();
    expect(rename(root, 'feature:login', 'signin').json, {
      'moved': [
        {'from': 'prds/features/f01_login/', 'to': 'prds/features/f01_signin/'},
        {'from': 'specs/f01_login/', 'to': 'specs/f01_signin/'},
      ],
      'rewritten': ['prds/FEATURES.md', 'prds/personas/buyer/PERSONA.md'],
    });
    expect(
      readDoc(root, persona),
      contains('reference:\n  - signin/email_login\n'),
    );
  });

  test('f02/us06/s3, f02/us06/fr01/e03, f02/us06/fr02, f02/us06/fr02/e01: a persona renames with the anti-persona in its folder', () async {
    final root = await writeWriteProject();
    rename(root, 'persona:buyer', 'shopper');
    expect(
      [
        hasDoc(root, 'prds/personas/shopper/PERSONA.md'),
        hasDoc(root, 'prds/personas/shopper/ANTI_PERSONA.md'),
      ],
      [true, true],
    );
    expect(readDoc(root, story1), contains('persona:\n  - shopper\n'));
  });

  test('f02/us06/s5, f02/us06/fr01/e05: a slug a sibling carries is doc_exists naming it, and nothing moves', () async {
    final root = await writeWriteProject();
    expect(
      () => rename(root, 'user_story:login/reset_password', 'sign_out'),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.docExists)
            .having(
              (f) => f.message,
              'message',
              'a user_story named login/sign_out exists',
            )
            .having((f) => f.file, 'file', story2),
      ),
    );
    expect(hasDoc(root, story3), isTrue);
  });

  test('f02/us06/s6, f02/us06/fr01/e06, dw-s03/inv8: a spec doc refuses and names its feature', () async {
    final root = await writeWriteProject();
    expect(
      () => rename(root, 'architecture:login', 'signin'),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.docTypeNotMovable)
            .having(
              (f) => f.message,
              'message',
              'architecture:login takes its name from its feature; '
                  'rename feature:login instead',
            ),
      ),
    );
  });

  test('f02/us06/fr01/e04: an FR file takes the new slug', () async {
    final root = await writeWriteProject();
    rename(root, 'fr:login/reset_password/expire_reset_link', 'expire_link');
    expect(hasDoc(root, '$f/us03_reset_password/fr02_expire_link.md'), isTrue);
    expect(hasDoc(root, fr32), isFalse);
  });

  test(
    'f02/us06/fr01/e06: a doc type with no slug is doc_type_not_movable',
    () async {
      final root = await writeWriteProject();
      expect(
        () => rename(root, 'features:features', 'index'),
        throwsA(
          isA<WriteFault>()
              .having((f) => f.code, 'code', WriteFaultCode.docTypeNotMovable)
              .having(
                (f) => f.message,
                'message',
                'features docs carry no slug, so rename cannot rename them',
              ),
        ),
      );
    },
  );

  test('f02/us06/fr01/e07: a bad or missing slug is refused', () async {
    final root = await writeWriteProject();
    expect(
      () => rename(root, 'user_story:login/reset_password', 'Recover'),
      throwsA(
        isA<IndexFault>().having(
          (f) => f.code,
          'code',
          IndexFaultCode.argumentInvalid,
        ),
      ),
    );
    expect(
      () => writeIn(
        root,
        (s) => answerRename(s, 'user_story:login/reset_password', slug: null),
      ),
      throwsA(
        isA<IndexFault>()
            .having((f) => f.code, 'code', IndexFaultCode.argumentMissing)
            .having(
              (f) => f.message,
              'message',
              'rename needs a slug, such as specstone rename user_story:login/reset_password --to recover_account',
            ),
      ),
    );
    expect(hasDoc(root, story3), isTrue);
  });

  test(
    'f02/us06/fr01/e08: the slug a doc already carries changes nothing',
    () async {
      final root = await writeWriteProject();
      final answer = rename(
        root,
        'user_story:login/reset_password',
        'reset_password',
      );
      expect(answer.text, '');
      expect(answer.json, {'moved': <Object>[], 'rewritten': <Object>[]});
      expect(hasDoc(root, story3), isTrue);
    },
  );

  test('f02/us06/s4, f02/us06/fr01/e09, f02/us06/fr02/e05: an approved doc renames with no Owner step, and every mark stays', () async {
    final root = await writeWriteProject();
    final before = readDoc(root, story2);
    rename(root, 'user_story:login/sign_out', 'log_out');
    expect(readDoc(root, '$f/us02_log_out/USER_STORY.md'), before);
    final linked = readDoc(root, story3);
    expect(linked, contains('](../us02_log_out/USER_STORY.md)'));
    expect('draft: true'.allMatches(linked), hasLength(1));
  });

  test('f02/us06/fr02/e03, f02/us06/fr02/e04, f02/us06/fr02/e06: prose, code, and unrelated values stay', () async {
    final root = await writeWriteProject();
    final apiBefore = readDoc(root, fr11);
    rename(root, 'feature:login', 'signin');
    final personaText = readDoc(root, persona);
    expect(personaText, contains('draft: true'));
    expect(personaText, contains('# Buyer\n\n## Profile\nBuys things.\n'));
    expect(
      readDoc(
        root,
        'prds/features/f01_signin/us01_email_login/fr01_validate_credentials.md',
      ),
      apiBefore,
    );
    expect(
      readDoc(root, 'prds/features/f01_signin/us01_email_login/USER_STORY.md'),
      contains('persona:\n  - buyer\n'),
    );
    expect(
      readDoc(root, 'prds/FEATURES.md'),
      contains('- [Login](features/f01_signin/FEATURE.md)\n'),
    );
  });

  test('PD12: a folder already at the new path is doc_exists', () async {
    final root = await writeWriteProject(
      extra: {
        'docs/prds/personas/shopper/ANTI_PERSONA.md': '# Not a shopper\n',
      },
    );
    expect(
      () => rename(root, 'persona:buyer', 'shopper'),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.docExists)
            .having((f) => f.file, 'file', 'prds/personas/shopper/'),
      ),
    );
    expect(hasDoc(root, persona), isTrue);
  });

  test('f02/us04/fr03/e02, nfr-di01: a rename stopped before its link rewrite is finished by the next write', () async {
    final root = await writeWriteProject();
    const linkFile = '$f/us01_email_login/fr02_lock_after_failures.md';
    final linkText = readDoc(root, linkFile);
    writeJournal(root, [
      const MoveStep(
        'docs/$f/us03_reset_password',
        'docs/$f/us03_recover_account',
      ),
      WriteStep(
        'docs/$linkFile',
        linkText.replaceAll('us03_reset_password', 'us03_recover_account'),
      ),
    ]);
    // The move ran before the stop.
    Directory('${root.path}/docs/$f/us03_reset_password')
        .renameSync('${root.path}/docs/$f/us03_recover_account');

    writeIn(root, (_) {});

    expect(
      readDoc(root, linkFile),
      contains('](../us03_recover_account/USER_STORY.md#use-case)'),
    );
  });
}
