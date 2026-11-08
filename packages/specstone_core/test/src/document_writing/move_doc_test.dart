import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart'
    show FindingKind;
import 'package:specstone_core/src/document_writing/approval.dart'
    show withApprovalHash;
import 'package:specstone_core/src/document_writing/move_doc.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/index_query/refs.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart'
    show checkOf, doc, projectDoc, spots, techStack, writeCheckProject;
import '../../helpers/failing_rename.dart';
import '../../helpers/nested_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';
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

  test('f02/us05/fr02, dw-s03/inv10: a reordered story links to itself through its own folder, and the link follows it', () async {
    final root = await writeWriteProject();
    docFile(root, story2).writeAsStringSync(
      '\nSee [me](../us02_sign_out/USER_STORY.md#use-case).\n',
      mode: FileMode.append,
    );
    reorder(root, 'user_story:login/sign_out', '1');
    expect(
      readDoc(root, '$f/us01_sign_out/USER_STORY.md'),
      contains('[me](USER_STORY.md#use-case)'),
    );
    expect(
      spots(checkOf(root), FindingKind.linkUnresolved),
      isNot(contains(startsWith('$f/us01_sign_out/'))),
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

  test('f02/us04/fr03/e03, dw-s03/inv9: a replay skips a phase-1 move whose stage slot is taken', () async {
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
    // Slot 0 is taken by a folder of its own while its step's `from` still
    // exists, so the replay must skip that step, not move onto the slot.
    final taken = File('${root.path}/${stage(0)}/taken.md')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('taken');

    writeIn(root, (_) {});

    for (final (_, to) in moves) {
      expect(Directory('${root.path}/${path(to)}').existsSync(), isTrue);
    }
    expect(hasDoc(root, '$f/us03_reset_password/USER_STORY.md'), isTrue);
    expect(
      File('${root.path}/${path('us01_reset_password')}/taken.md')
          .readAsStringSync(),
      'taken',
    );
    expect(taken.existsSync(), isFalse);
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

  test('f02/us05/fr02/e10, f01/us07/fr01: refs and the reorder rewrite read the same mention lines, a link form in a code span and a stray ]( included', () async {
    const domain = 'specs/f01_login/DOMAIN.md';
    const story = '../../$f/us02_sign_out/USER_STORY.md';
    const before =
        '# Login domain\n\n## Entities\n\n'
        '| Entity | Kind | Identity | Owns | Notes |\n'
        '|---|---|---|---|---|\n'
        '| Session | Aggregate root | id | none | none |\n\n'
        '## Invariants\n\n'
        '- **INV-1** A session follows `$story`.\n'
        '- **INV-2** It ends as `[x]($story)` says.\n'
        '- **INV-3** A stray ]($story stays prose.\n';
    final root = await writeWriteProject(extra: {'docs/$domain': before});
    final refs =
        (writeIn(
                      root,
                      (s) => answerRefs(s.index, 'user_story:login/sign_out'),
                    ).json['docs']!
                    as List)
                .single
            as Map;
    final mentioned = [
      for (final key in ['mentions', 'untypedMentions'])
        for (final mention in refs[key]! as List)
          if ((mention as Map)['path'] == domain) mention['line'],
    ];
    final naming = [
      for (final (i, line) in before.split('\n').indexed)
        if (line.contains('us02_sign_out/')) i + 1,
    ];
    expect(mentioned, naming);
    expect(naming, hasLength(3));

    reorder(root, 'user_story:login/sign_out', '3');
    expect(
      readDoc(root, domain),
      before.replaceAll('/us02_sign_out/', '/us03_sign_out/'),
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

  test('f02/us05/fr01/e10, f02/us06/fr01/e10: a doc gone from disk since the index is doc_not_found, not a crash', () async {
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

  test('f02/us06/fr01/e06, dw-s03/inv8, H18: a spec doc whose feature is not indexed still names its feature', () async {
    final root = await writeWriteProject(without: {'docs/$signupFeature'});
    expect(
      () => rename(root, 'architecture:signup', 'register'),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.docTypeNotMovable)
            .having(
              (f) => f.message,
              'message',
              'architecture:signup takes its name from its feature; '
                  'rename feature:signup instead',
            ),
      ),
    );
  });

  test('dw-s03/inv8, H18: a parented file type numbered but unslugged is told it carries no slug', () async {
    final root = await writeWriteProject(
      extra: {
        '.specstone/templates/note.yaml': 'id: note\ndescription: A numbered note\npath: specs/f{nn}_{slug}/note_{nn}.md\nparent: feature\n',
        'docs/specs/f01_login/note_01.md': '# A note\n',
      },
    );
    expect(
      () => rename(root, 'note:login', 'other'),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.docTypeNotMovable)
            .having(
              (f) => f.message,
              'message',
              'note docs carry no slug, so rename cannot rename them',
            ),
      ),
    );
  });

  test('f02/us06/fr01/e02, dw-s03/inv7, H22: two spec folders that sort differently after the rename each move to their own new path', () async {
    final root = await writeTree({
      '.specstone/config.yaml': shippedPinsConfig(),
      '.specstone/templates/spec_a.yaml': 'id: spec_a\ndescription: Spec A\npath: specs/f{nn}_{slug}_a/A.md\nparent: feature\n',
      '.specstone/templates/spec_b.yaml': 'id: spec_b\ndescription: Spec B\npath: specs/f{nn}_b_{slug}/B.md\nparent: feature\n',
      'docs/prds/features/f01_z/FEATURE.md': '# Z\n',
      'docs/specs/f01_z_a/A.md': '# A\n',
      'docs/specs/f01_b_z/B.md': '# B\n',
    });
    expect(rename(root, 'feature:z', 'a').json['moved'], [
      {'from': 'prds/features/f01_z/', 'to': 'prds/features/f01_a/'},
      {'from': 'specs/f01_b_z/', 'to': 'specs/f01_b_a/'},
      {'from': 'specs/f01_z_a/', 'to': 'specs/f01_a_a/'},
    ]);
    expect(hasDoc(root, 'specs/f01_b_a/B.md'), isTrue);
    expect(hasDoc(root, 'specs/f01_a_a/A.md'), isTrue);
  });

  test(
    'f02/us05/fr01/e05, H20: a feature with no spec folder on disk moves alone',
    () async {
      final root = await writeWriteProject();
      Directory('${root.path}/docs/specs/f02_signup')
          .deleteSync(recursive: true);
      expect(reorder(root, 'feature:signup', '1').json['moved'], [
        {
          'from': 'prds/features/f02_signup/',
          'to': 'prds/features/f01_signup/',
        },
        {'from': 'prds/features/f01_login/', 'to': 'prds/features/f02_login/'},
        {'from': 'specs/f01_login/', 'to': 'specs/f02_login/'},
      ]);
      expect(hasDoc(root, 'prds/features/f01_signup/FEATURE.md'), isTrue);
    },
  );

  test('f02/us05/fr01, dw-s03/inv9, X4, H21: the reorder journal lists every stage move first, then every target move, then the rewrites', () async {
    final root = await writeWriteProject();
    expect(
      () => IOOverrides.runWithIOOverrides(
        () => reorder(root, 'user_story:login/reset_password', '1'),
        FailingRenameHook('docs/$f/us03_reset_password'),
      ),
      throwsA(
        isA<RenderFault>().having(
          (e) => e.code,
          'code',
          RenderFaultCode.outputNotWritable,
        ),
      ),
    );

    final journal = jsonDecode(
      File('${root.path}/${MoveJournal.journalPath}').readAsStringSync(),
    ) as Map<String, Object?>;
    final steps = (journal['steps']! as List).cast<Map<String, Object?>>();
    String stage(int i) => '${MoveJournal.stagePath}/$i';
    String path(String name) => 'docs/$f/$name';
    const moves = [
      ('us03_reset_password', 'us01_reset_password'),
      ('us01_email_login', 'us02_email_login'),
      ('us02_sign_out', 'us03_sign_out'),
    ];
    expect(steps.take(6).toList(), [
      for (final (i, (from, _)) in moves.indexed)
        {
          'move': {'from': path(from), 'to': stage(i)},
        },
      for (final (i, (_, to)) in moves.indexed)
        {
          'move': {'from': stage(i), 'to': path(to)},
        },
    ]);
    expect(steps.skip(6).map((s) => s.keys.single).toSet(), {'write'});
    expect(steps.length, greaterThan(6));

    writeIn(root, (_) {});

    expect(hasDoc(root, '$f/us01_reset_password/USER_STORY.md'), isTrue);
    expect(hasDoc(root, '$f/us03_sign_out/USER_STORY.md'), isTrue);
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

  group('nested features', () {
    const shop = 'prds/features/f02_shop';
    const payDomain = 'specs/f02_shop/f02_pay/DOMAIN.md';

    test('f02/us05/fr01/e11, sf-c2: reordering a sub-feature renumbers only its siblings and moves its spec folder', () async {
      final root = await writeNestedProject(
        extra: {'docs/$payDomain': '# Pay domain\n'},
      );
      final answer = reorder(root, 'feature:shop/pay', '1');
      expect(answer.text, contains('moved $shop/f02_pay/ to $shop/f01_pay/\n'));
      expect(answer.text, contains('moved $shop/f01_cart/ to $shop/f02_cart/'));
      expect(
        answer.text,
        contains('moved specs/f02_shop/f02_pay/ to specs/f02_shop/f01_pay/'),
      );
      expect(hasDoc(root, '$shop/f01_pay/FEATURE.md'), isTrue);
      expect(
        hasDoc(root, '$shop/f02_cart/us01_add_item/USER_STORY.md'),
        isTrue,
      );
      expect(hasDoc(root, 'specs/f02_shop/f01_pay/DOMAIN.md'), isTrue);
      expect(hasDoc(root, 'specs/f02_shop/f02_cart/DOMAIN.md'), isTrue);
      expect(hasDoc(root, shopFeature), isTrue);
    });

    test('f02/us05/fr01/e11, sf-c2: reordering a story under a sub-feature moves only the stories of that sub-feature', () async {
      final root = await writeNestedProject();
      final answer = reorder(root, 'user_story:shop/cart/drop_item', '1');
      expect(
        answer.text,
        startsWith(
          'moved $shop/f01_cart/us02_drop_item/ to $shop/f01_cart/us01_drop_item/\n'
          'moved $shop/f01_cart/us01_add_item/ to $shop/f01_cart/us02_add_item/\n',
        ),
      );
      expect(hasDoc(root, '$shop/f02_pay/us01_card/USER_STORY.md'), isTrue);
    });

    test('f02/us06/fr01/e11: renaming a sub-feature moves its folder and spec folder', () async {
      final root = await writeNestedProject();
      final answer = rename(root, 'feature:shop/cart', 'basket');
      expect(
        answer.text,
        startsWith(
          'moved $shop/f01_cart/ to $shop/f01_basket/\n'
          'moved specs/f02_shop/f01_cart/ to specs/f02_shop/f01_basket/\n',
        ),
      );
      expect(hasDoc(root, 'specs/f02_shop/f01_basket/DOMAIN.md'), isTrue);
      expect(
        hasDoc(root, '$shop/f01_basket/us01_add_item/USER_STORY.md'),
        isTrue,
      );
    });

    test('f02/us06/fr01/e06: renaming a sub-feature spec doc names the sub-feature to rename', () async {
      final root = await writeNestedProject();
      expect(
        () => rename(root, 'domain:shop/cart', 'basket'),
        throwsA(
          isA<WriteFault>().having(
            (f) => f.message,
            'message',
            contains('rename feature:shop/cart instead'),
          ),
        ),
      );
    });

    test('f02/us06/fr01/e11: renaming the top feature renames the docs under every sub-feature', () async {
      final root = await writeNestedProject();
      rename(root, 'feature:shop', 'market');
      expect(
        hasDoc(
          root,
          'prds/features/f02_market/f01_cart/us01_add_item/USER_STORY.md',
        ),
        isTrue,
      );
      expect(
        writeIn(root, (s) => s.index.resolve('market/cart/add_item')),
        hasLength(1),
      );
      expect(hasDoc(root, 'specs/f02_market/f01_cart/DOMAIN.md'), isTrue);
      expect(hasDoc(root, 'specs/f02_market/DOMAIN.md'), isTrue);
    });
  });

  group('move', () {
    const shop = 'prds/features/f02_shop';
    const journeyPath = 'prds/journeys/sign_in/JOURNEY.md';
    const notesPath = 'notes/ideas.md';
    const addItemFolder = 'prds/features/f02_shop/f01_cart/us01_add_item';
    const movedFolder = 'prds/features/f02_shop/f02_pay/us03_add_item';

    ReadAnswer move(Directory root, String address, String? under) =>
        writeIn(root, (s) => answerMove(s, address, under: under));

    void appendTo(Directory root, String docPath, String text) =>
        docFile(root, docPath).writeAsStringSync(text, mode: FileMode.append);

    test('f02/us07/s1, sf-r3: a story moves to the last place of another feature with its FR, and the old siblings keep their numbers', () async {
      final root = await writeNestedProject();
      final answer = move(root, 'user_story:shop/cart/add_item', 'shop/pay');
      expect(
        answer.text,
        startsWith('moved $addItemFolder/ to $movedFolder/\n'),
      );
      expect(answer.json['moved'], [
        {'from': '$addItemFolder/', 'to': '$movedFolder/'},
      ]);
      expect(hasDoc(root, '$movedFolder/USER_STORY.md'), isTrue);
      expect(hasDoc(root, '$movedFolder/fr01_check_stock.md'), isTrue);
      expect(hasDoc(root, cartAdd), isFalse);
      expect(hasDoc(root, cartDrop), isTrue);
      expect(hasDoc(root, payCard), isTrue);
      expect(hasDoc(root, payRefund), isTrue);
    });

    test("f02/us07/fr02/e01, sf-r3: shop's api cell and confirmed label become pay/add_item/check_stock, and a step, a link, and a path mention follow", () async {
      final root = await writeNestedProject(
        extra: {
          'docs/$journeyPath':
              '# Sign in\n\n## Goal\nGet in.\n\n## Flow\n\n## Steps\n'
              '### 1. Add\nstep: shop/cart/add_item S1\n',
          'docs/$notesPath':
              '# Ideas\n\nSee `../$addItemFolder/USER_STORY.md` first.\n',
        },
      );
      appendTo(
        root,
        projectDoc,
        '\nSee [add item](features/f02_shop/f01_cart/us01_add_item/USER_STORY.md).\n',
      );
      move(root, 'user_story:shop/cart/add_item', 'shop/pay');
      final api = readDoc(root, shopApi);
      expect(api, contains('| pay/add_item/check_stock | `addItem` |'));
      expect(api, contains('  - pay/add_item/check_stock '));
      expect(api, isNot(contains('cart/add_item')));
      expect(
        readDoc(root, journeyPath),
        contains('step: shop/pay/add_item S1\n'),
      );
      expect(
        readDoc(root, projectDoc),
        contains('(features/f02_shop/f02_pay/us03_add_item/USER_STORY.md)'),
      );
      expect(
        readDoc(root, notesPath),
        contains('`../$movedFolder/USER_STORY.md`'),
      );
    });

    test('f02/us07/fr02/e02: a move under the top feature f03_other leaves the shop cell, and check reports fr_trace_unresolved on it', () async {
      final root = await writeNestedProject();
      const other = 'prds/features/f03_other/FEATURE.md';
      docFile(root, other)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(readDoc(root, payFeature));
      move(root, 'user_story:shop/cart/add_item', 'other');
      expect(
        hasDoc(root, 'prds/features/f03_other/us01_add_item/USER_STORY.md'),
        isTrue,
      );
      expect(
        readDoc(root, shopApi),
        contains('| cart/add_item/check_stock | `addItem` |'),
      );
      expect(
        spots(checkOf(root), FindingKind.frTraceUnresolved),
        contains(startsWith('$shopApi:')),
      );
    });

    for (final (first, second) in [
      ('add_item', 'drop_item'),
      ('drop_item', 'add_item'),
    ]) {
      test(
        'f02/us05/fr02, f02/us07/fr02/e03, dw-s03/inv10: two sibling stories that link each other move under login, $first first, and each link resolves',
        () async {
          final root = await writeNestedProject();
          appendTo(
            root,
            cartAdd,
            '\nSee [drop item](../us02_drop_item/USER_STORY.md).\n',
          );
          appendTo(
            root,
            cartDrop,
            '\nSee [stock check](../us01_add_item/fr01_check_stock.md).\n',
          );
          move(root, 'user_story:shop/cart/$first', 'login');
          move(root, 'user_story:shop/cart/$second', 'login');
          String folderOf(String slug) =>
              slug == first ? 'us02_$slug' : 'us03_$slug';
          expect(
            readDoc(root, '$f/${folderOf('add_item')}/USER_STORY.md'),
            contains('(../${folderOf('drop_item')}/USER_STORY.md)'),
          );
          expect(
            readDoc(root, '$f/${folderOf('drop_item')}/USER_STORY.md'),
            contains('(../${folderOf('add_item')}/fr01_check_stock.md)'),
          );
          expect(spots(checkOf(root), FindingKind.linkUnresolved), isEmpty);
        },
      );
    }

    test('f02/us07/fr02/e03, dw-s03/inv10: a moved story links to itself through its own folder, and the link follows it', () async {
      final root = await writeNestedProject();
      appendTo(
        root,
        cartDrop,
        '\nSee [me](../us02_drop_item/USER_STORY.md#x).\n',
      );
      move(root, 'user_story:shop/cart/drop_item', 'shop/pay');
      expect(
        readDoc(root, '$shop/f02_pay/us03_drop_item/USER_STORY.md'),
        contains('[me](USER_STORY.md#x)'),
      );
      expect(spots(checkOf(root), FindingKind.linkUnresolved), isEmpty);
    });

    test('f02/us07/fr02/e03, dw-s03/inv10: a moved story links to a plain file that stays, and the link follows', () async {
      final root = await writeNestedProject(
        extra: {'docs/$shop/f01_cart/flow.png': 'png'},
      );
      appendTo(root, cartDrop, '\n![flow](../flow.png)\n');
      move(root, 'user_story:shop/cart/drop_item', 'login');
      expect(
        readDoc(root, '$f/us02_drop_item/USER_STORY.md'),
        contains('![flow](../../f02_shop/f01_cart/flow.png)'),
      );
      expect(spots(checkOf(root), FindingKind.linkTargetMissing), isEmpty);
    });

    test('f02/us07/fr02, dw-s03/inv10: a non-UTF-8 moved story whose link must change refuses with output_not_writable, and nothing moves', () async {
      final root = await writeNestedProject();
      appendTo(
        root,
        cartDrop,
        '\nSee [stock](../us01_add_item/fr01_check_stock.md).\n',
      );
      docFile(root, cartDrop).writeAsBytesSync([0xff], mode: FileMode.append);
      expect(
        () => move(root, 'user_story:shop/cart/drop_item', 'shop/pay'),
        throwsA(
          isA<RenderFault>()
              .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
              .having(
                (f) => f.message,
                'message',
                'cannot write $cartDrop: not UTF-8 text',
              ),
        ),
      );
      expect(hasDoc(root, cartDrop), isTrue);
      expect(
        hasDoc(root, '$shop/f02_pay/us03_drop_item/USER_STORY.md'),
        isFalse,
      );
    });

    test('f02/us07/fr02, dw-s03/inv10: a non-UTF-8 moved story whose link still reaches its target moves with every byte kept', () async {
      final root = await writeNestedProject();
      appendTo(
        root,
        cartDrop,
        '\nSee [cart](../../../f02_shop/f01_cart/FEATURE.md).\n',
      );
      docFile(root, cartDrop).writeAsBytesSync([0xff], mode: FileMode.append);
      final bytes = docFile(root, cartDrop).readAsBytesSync();
      move(root, 'user_story:shop/cart/drop_item', 'shop/pay');
      expect(
        docFile(
          root,
          '$shop/f02_pay/us03_drop_item/USER_STORY.md',
        ).readAsBytesSync(),
        bytes,
      );
    });

    test('f02/us07/fr01/e01, sf-c6: no moved doc gains draft, and check reports no confirmed_entry_stale and no suspect link', () async {
      final root = await writeNestedProject();
      final answer = move(root, 'user_story:shop/cart/add_item', 'shop/pay');
      for (final path in [
        '$movedFolder/USER_STORY.md',
        '$movedFolder/fr01_check_stock.md',
        for (final p in answer.json['rewritten']! as List<Object?>) '$p',
      ]) {
        expect(readDoc(root, path), isNot(contains('status: draft')));
      }
      final report = checkOf(root);
      expect(spots(report, FindingKind.confirmedEntryStale), isEmpty);
      expect(spots(report, FindingKind.suspect), isEmpty);
    });

    test('f02/us07/fr01/e02, review focus 2: a sibling with the story slug is doc_exists naming its path, and nothing moves', () async {
      const clash = 'prds/features/f02_shop/f02_pay/us03_add_item';
      final root = await writeNestedProject(
        extra: {'docs/$clash/USER_STORY.md': '# Add item\n'},
      );
      expect(
        () => move(root, 'user_story:shop/cart/add_item', 'shop/pay'),
        throwsA(
          isA<WriteFault>()
              .having((f) => f.code, 'code', WriteFaultCode.docExists)
              .having(
                (f) => f.message,
                'message',
                'a user_story named shop/pay/add_item exists',
              )
              .having((f) => f.file, 'file', '$clash/USER_STORY.md'),
        ),
      );
      expect(hasDoc(root, cartAdd), isTrue);
    });

    test('f02/us07/fr01/e03: a landing path already on disk is doc_exists naming that path, and nothing moves', () async {
      final root = await writeNestedProject(
        extra: {'docs/$movedFolder/note.md': '# Note\n'},
      );
      expect(
        () => move(root, 'user_story:shop/cart/add_item', 'shop/pay'),
        throwsA(
          isA<WriteFault>()
              .having((f) => f.code, 'code', WriteFaultCode.docExists)
              .having((f) => f.file, 'file', '$movedFolder/'),
        ),
      );
      expect(hasDoc(root, cartAdd), isTrue);
    });

    test('f02/us07/fr01/e04, review focus 3: a story moved into the feature it sits in changes nothing', () async {
      final root = await writeNestedProject();
      final answer = move(root, 'user_story:shop/cart/drop_item', 'shop/cart');
      expect(answer.text, isEmpty);
      expect(answer.json['moved'], isEmpty);
      expect(answer.json['rewritten'], isEmpty);
      expect(hasDoc(root, cartDrop), isTrue);
    });

    test('f02/us07/fr01/e05, sf-r1: a feature that holds features takes no story, and nothing moves', () async {
      final root = await writeNestedProject();
      expect(
        () => move(root, 'user_story:shop/cart/add_item', 'shop'),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
              .having(
                (f) => f.message,
                'message',
                'shop (feature) holds sub-features, so it takes no story',
              ),
        ),
      );
      expect(hasDoc(root, cartAdd), isTrue);
    });

    test('f02/us07/fr01/e06: a doc of another type is doc_type_not_movable, and nothing moves', () async {
      final root = await writeNestedProject();
      expect(
        () => move(root, 'fr:shop/cart/add_item/check_stock', 'shop/pay'),
        throwsA(
          isA<WriteFault>()
              .having((f) => f.code, 'code', WriteFaultCode.docTypeNotMovable)
              .having(
                (f) => f.message,
                'message',
                'fr docs cannot move; move takes a user_story',
              ),
        ),
      );
      expect(hasDoc(root, cartAddFr), isTrue);
    });

    test('f02/us07/fr01/e07: no --under is argument_missing', () async {
      final root = await writeNestedProject();
      expect(
        () => move(root, 'user_story:shop/cart/add_item', null),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.argumentMissing)
              .having(
                (f) => f.message,
                'message',
                'move needs a feature, such as specstone move '
                    'user_story:login/reset_password --under account',
              ),
        ),
      );
    });

    test('f02/us07/fr01/e08: an --under no feature carries is doc_not_found, and nothing moves', () async {
      final root = await writeNestedProject();
      expect(
        () => move(root, 'user_story:shop/cart/add_item', 'nothing'),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.docNotFound)
              .having(
                (f) => f.message,
                'message',
                'no feature doc carries the name nothing',
              ),
        ),
      );
      expect(hasDoc(root, cartAdd), isTrue);
    });

    test('f02/us07/fr01/e08: an --under that names no feature doc is doc_not_found naming the value, and nothing moves', () async {
      final root = await writeNestedProject();
      expect(
        () => move(
          root,
          'user_story:shop/cart/add_item',
          'architecture:shop/pay',
        ),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.docNotFound)
              .having(
                (f) => f.message,
                'message',
                contains('architecture:shop/pay'),
              ),
        ),
      );
      expect(hasDoc(root, cartAdd), isTrue);
    });

    test('f02/us07/fr01/e12: --under feature:shop/pay and a path name the feature as a bare name does', () async {
      for (final under in [
        'feature:shop/pay',
        'prds/features/f02_shop/f02_pay/FEATURE.md',
      ]) {
        final root = await writeNestedProject();
        final answer = move(root, 'user_story:shop/cart/add_item', under);
        expect(answer.json['moved'], [
          {'from': '$addItemFolder/', 'to': '$movedFolder/'},
        ], reason: under);
      }
    });

    test('f02/us07/fr01/e13: an --under that names 2 or more feature docs is argument_invalid listing each, and nothing moves', () async {
      final root = await writeNestedProject(
        extra: {'docs/prds/features/f02_shop/f03_pay/FEATURE.md': '# Pay\n'},
      );
      expect(
        () => move(root, 'user_story:shop/cart/add_item', 'shop/pay'),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
              .having(
                (f) => f.message,
                'message',
                allOf(
                  contains(payFeature),
                  contains('prds/features/f02_shop/f03_pay/FEATURE.md'),
                ),
              ),
        ),
      );
      expect(hasDoc(root, cartAdd), isTrue);
    });

    test('f02/us07/fr01/e14: a target that names a feature and its spec docs is argument_invalid, never doc_type_not_movable', () async {
      final root = await writeNestedProject();
      expect(
        () => move(root, 'shop', 'shop/pay'),
        throwsA(
          isA<IndexFault>().having(
            (f) => f.code,
            'code',
            IndexFaultCode.argumentInvalid,
          ),
        ),
      );
    });

    test(
      'f02/us07/fr01/e10, sf-r1: a move out of a mixed parent is allowed',
      () async {
        const orphan = '$shop/us01_orphan';
        final root = await writeNestedProject(
          extra: {'docs/$orphan/USER_STORY.md': '# Orphan\n'},
        );
        final answer = move(root, 'user_story:shop/orphan', 'shop/pay');
        expect(
          answer.text,
          startsWith('moved $orphan/ to $shop/f02_pay/us03_orphan/\n'),
        );
        expect(hasDoc(root, '$shop/f02_pay/us03_orphan/USER_STORY.md'), isTrue);
      },
    );
  });

  group('approval stamp on a reference rewrite', () {
    String? approvedValue(Directory root, String docPath) => RegExp(
      r'^approved: "([^"]+)"$',
      multiLine: true,
    ).firstMatch(readDoc(root, docPath))?.group(1);

    List<String> staleDocs(Directory root) => spots(
      checkOf(root),
      FindingKind.approvalStale,
    ).map((spot) => spot.split(':').first).toList();

    void leaveStale(Directory root, String docPath) => docFile(
      root,
      docPath,
    ).writeAsStringSync('\nA late note.\n', mode: FileMode.append);

    test('document_writing/reorder_doc/rewrite_links_to_moved_docs E07: a rewritten approved doc is stamped with the hash of its new content and stays approved', () async {
      final root = await writeWriteProject();
      final before = approvedValue(root, featuresIndex);
      writeIn(root, (s) => answerReorder(s, 'feature:signup', place: '1'));
      expect(readDoc(root, featuresIndex), contains('f01_signup/FEATURE.md'));
      expect(approvedValue(root, featuresIndex), isNotNull);
      expect(approvedValue(root, featuresIndex), isNot(before));
      expect(staleDocs(root), isEmpty);
    });

    test('document_writing/reorder_doc/rewrite_links_to_moved_docs E07: a rewritten doc whose hash did not match keeps its hash and still awaits approval', () async {
      final root = await writeWriteProject();
      leaveStale(root, featuresIndex);
      final before = approvedValue(root, featuresIndex);
      writeIn(root, (s) => answerReorder(s, 'feature:signup', place: '1'));
      expect(readDoc(root, featuresIndex), contains('f01_signup/FEATURE.md'));
      expect(approvedValue(root, featuresIndex), before);
      expect(staleDocs(root), [featuresIndex]);
    });

    test('document_writing/reorder_doc/rewrite_links_to_moved_docs E07: a rewritten draft keeps draft and gains no approved', () async {
      final root = await writeWriteProject();
      writeIn(
        root,
        (s) => answerReorder(s, 'user_story:login/reset_password', place: '1'),
      );
      final draftStory = readDoc(
        root,
        'prds/features/f01_login/us01_reset_password/USER_STORY.md',
      );
      expect(draftStory, contains('draft: true'));
      expect(draftStory, isNot(contains('approved:')));
    });

    test('document_writing/rename_doc/rewrite_name_references: a rename stamps an approved doc it rewrites and keeps a stale hash stale', () async {
      final root = await writeWriteProject();
      final before = approvedValue(root, featuresIndex);
      rename(root, 'feature:signup', 'register');
      expect(readDoc(root, featuresIndex), contains('f02_register/FEATURE.md'));
      expect(approvedValue(root, featuresIndex), isNot(before));
      expect(staleDocs(root), isEmpty);

      final stale = await writeWriteProject();
      leaveStale(stale, featuresIndex);
      final kept = approvedValue(stale, featuresIndex);
      rename(stale, 'feature:signup', 'register');
      expect(approvedValue(stale, featuresIndex), kept);
      expect(staleDocs(stale), [featuresIndex]);
    });

    test('document_writing/rename_doc/rewrite_name_references: a renamed doc_ref name stamps the approved doc that held it', () async {
      final root = await writeWriteProject();
      final withPersona = readDoc(
        root,
        story2,
      ).replaceFirst('approved:', 'persona:\n  - buyer\napproved:');
      docFile(root, story2).writeAsStringSync(
        writeIn(
          root,
          (s) => withApprovalHash(withPersona, s.docTypeAt(story2)),
        ),
      );
      expect(staleDocs(root), isEmpty);
      rename(root, 'persona:buyer', 'shopper');
      expect(readDoc(root, story2), contains('persona:\n  - shopper\n'));
      expect(staleDocs(root), isEmpty);
    });

    test('document_writing/move_story/rewrite_moved_story_references: a move stamps the approved api doc it rewrites and keeps a stale hash stale', () async {
      final root = await writeNestedProject();
      final before = approvedValue(root, shopApi);
      writeIn(
        root,
        (s) =>
            answerMove(s, 'user_story:shop/cart/add_item', under: 'shop/pay'),
      );
      expect(readDoc(root, shopApi), contains('pay/add_item/check_stock'));
      expect(approvedValue(root, shopApi), isNot(before));
      expect(staleDocs(root), isNot(contains(shopApi)));

      final stale = await writeNestedProject();
      leaveStale(stale, shopApi);
      final kept = approvedValue(stale, shopApi);
      writeIn(
        stale,
        (s) =>
            answerMove(s, 'user_story:shop/cart/add_item', under: 'shop/pay'),
      );
      expect(approvedValue(stale, shopApi), kept);
      expect(staleDocs(stale), contains(shopApi));
    });
  });
  group('doc-name mentions in docs and code files', () {
    String codeText(Directory root, String path) =>
        File('${root.path}/$path').readAsStringSync();

    List<int> codeBytes(Directory root, String path) =>
        File('${root.path}/$path').readAsBytesSync();

    void putBytes(Directory root, String path, List<int> bytes) =>
        File('${root.path}/$path')
          ..createSync(recursive: true)
          ..writeAsBytesSync(bytes);

    ReadAnswer renameLogin(Directory root) =>
        rename(root, 'feature:login', 'signin');

    String? approvedHash(Directory root, String docPath) => RegExp(
      r'^approved: "([^"]+)"$',
      multiLine: true,
    ).firstMatch(readDoc(root, docPath))?.group(1);

    List<String> staleDocs(Directory root) => spots(
      checkOf(root),
      FindingKind.approvalStale,
    ).map((spot) => spot.split(':').first).toList();

    test('document_writing/rename_doc/rewrite_name_references E03: a doc-name mention in any doc follows the rename, its type prefix and section key kept', () async {
      final root = await writeCheckProject(
        extra: {
          'docs/notes.md':
              'See `login/email_login` or `feature:login#problem`, plain '
              'login/email_login, and `login`.\n',
        },
      );
      renameLogin(root);
      expect(
        readDoc(root, 'notes.md'),
        'See `signin/email_login` or `feature:signin#problem`, plain '
        'login/email_login, and `login`.\n',
      );
    });

    test('document_writing/rename_doc/rewrite_name_references E04: a Dart file under a code root has its comment lines rewritten and every other byte kept', () async {
      const before =
          '/// Lays out `login/email_login`.\n'
          'final a = "`login/email_login`";\n'
          '  // see `user_story:login/email_login#acceptance_criteria` and `login`\n'
          'void f() {} // also `login/email_login`\n'
          '// split `login/\n'
          '// email_login`\n'
          "const tag = '`login/email_login`';\n";
      final root = await writeCheckProject(
        extra: {'app/lib/doc.dart': before, 'other/doc.dart': before},
      );
      final answer = renameLogin(root);
      expect(
        codeText(root, 'app/lib/doc.dart'),
        '/// Lays out `signin/email_login`.\n'
        'final a = "`login/email_login`";\n'
        '  // see `user_story:signin/email_login#acceptance_criteria` and `login`\n'
        'void f() {} // also `login/email_login`\n'
        '// split `login/\n'
        '// email_login`\n'
        "const tag = '`login/email_login`';\n",
      );
      expect(codeText(root, 'other/doc.dart'), before);
      expect(answer.json['rewritten'], contains('app/lib/doc.dart'));
      expect(answer.json['rewritten'], isNot(contains('other/doc.dart')));
      expect(answer.text, contains('rewrote app/lib/doc.dart\n'));
    });

    test('document_writing/rename_doc/rewrite_name_references E04: a CRLF or mixed-ending file keeps every line end', () async {
      const before =
          '// `login/email_login`\r\nfinal a = 1;\n// `login/email_login`\r\n'
          '// `login/email_login` x\r\n';
      final root = await writeCheckProject(extra: {'app/lib/crlf.dart': ''});
      File('${root.path}/app/lib/crlf.dart').writeAsStringSync(before);
      renameLogin(root);
      expect(
        codeText(root, 'app/lib/crlf.dart'),
        before.replaceAll('login/email_login', 'signin/email_login'),
      );
    });

    test('document_writing/rename_doc/rewrite_name_references E04: a byte-order mark stays', () async {
      final root = await writeCheckProject();
      putBytes(root, 'app/lib/bom.dart', [
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('// `login/email_login` é\n'),
      ]);
      renameLogin(root);
      expect(codeBytes(root, 'app/lib/bom.dart'), [
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('// `signin/email_login` é\n'),
      ]);
    });

    test('document_writing/rename_doc/rewrite_name_references E04: a PNG and a file of invalid text under a code root leave the rename unblocked and keep their bytes', () async {
      final root = await writeCheckProject();
      final png = [0x89, 0x50, 0x4E, 0x47, 0x60, 0xFF, 0xFE];
      final bad = [...utf8.encode('// `login/email_login`\n'), 0xFF, 0xFE];
      putBytes(root, 'app/lib/logo.png', png);
      putBytes(root, 'app/lib/bad.dart', bad);
      renameLogin(root);
      expect(codeBytes(root, 'app/lib/logo.png'), png);
      expect(codeBytes(root, 'app/lib/bad.dart'), bad);
      expect(hasDoc(root, 'prds/features/f01_signin/FEATURE.md'), isTrue);
    });

    test('document_writing/rename_doc/rewrite_name_references E08: a markdown file under a code root reads as a doc, its fenced code, frontmatter, and plain text kept', () async {
      const before =
          '---\nname: skill\ndescription: Use `login/email_login`.\n'
          'approved: "abc"\n---\n\n# Skill\n\nRun `login/email_login`.\n\n'
          '```sh\n`login/email_login`\n```\n\nPlain login/email_login.\n';
      final root = await writeCheckProject(extra: {'app/lib/SKILL.md': before});
      renameLogin(root);
      expect(
        codeText(root, 'app/lib/SKILL.md'),
        before.replaceFirst(
          'Run `login/email_login`',
          'Run `signin/email_login`',
        ),
      );
    });

    test('document_writing/rename_doc/rewrite_name_references: a read-only code file that would change refuses the rename; one that would not change is left alone', () async {
      final root = await writeCheckProject(
        extra: {
          'app/lib/locked.dart': '// `login/email_login`\n',
          'app/lib/fine.dart': '// nothing here\n',
        },
      );
      for (final name in ['locked', 'fine']) {
        Process.runSync('chmod', ['444', '${root.path}/app/lib/$name.dart']);
        addTearDown(
          () => Process.runSync('chmod', [
            '644',
            '${root.path}/app/lib/$name.dart',
          ]),
        );
      }
      expect(
        () => renameLogin(root),
        throwsA(
          isA<RenderFault>().having(
            (e) => e.code,
            'code',
            RenderFaultCode.outputNotWritable,
          ),
        ),
      );
      expect(hasDoc(root, 'prds/features/f01_login/FEATURE.md'), isTrue);
      expect(codeText(root, 'app/lib/locked.dart'), '// `login/email_login`\n');
    }, skip: unreadablePathSkipReason() ?? false);

    test('document_writing/rename_doc/rewrite_name_references E05: a rewritten draft keeps draft: true; an approved doc is stamped again', () async {
      final root = await writeWriteProject();
      File(
        '${root.path}/docs/$antiPersona',
      ).writeAsStringSync('\nSee `feature:signup`.\n', mode: FileMode.append);
      final approvedText =
          '${readDoc(root, loginFeature)}\nSee `feature:signup`.\n';
      docFile(root, loginFeature).writeAsStringSync(
        writeIn(
          root,
          (s) => withApprovalHash(approvedText, s.docTypeAt(loginFeature)),
        ),
      );
      final before = approvedHash(root, loginFeature);
      expect(staleDocs(root), isEmpty);
      rename(root, 'feature:signup', 'register');
      expect(readDoc(root, antiPersona), contains('draft: true'));
      expect(readDoc(root, antiPersona), contains('`feature:register`'));
      expect(readDoc(root, loginFeature), contains('`feature:register`'));
      expect(approvedHash(root, loginFeature), isNot(before));
      expect(staleDocs(root), isEmpty);
    });

    test('document_writing/move_story/rewrite_moved_story_references E06, E08: a move rewrites a mention in a doc, in a code comment, and in a code markdown file, but not a fenced one or plain text', () async {
      const code =
          '// Adds `shop/cart/add_item` and '
          '`user_story:shop/cart/add_item#acceptance_criteria`.\n'
          'final plain = "shop/cart/add_item";\n';
      const skill =
          'Use `shop/cart/add_item`.\n\n```\n'
          '`shop/cart/add_item`\n```\n\nPlain shop/cart/add_item.\n';
      final root = await writeNestedProject(
        extra: {
          'docs/notes.md': 'See `shop/cart/add_item`.\n',
          'app/lib/cart.dart': code,
          'app/lib/SKILL.md': skill,
        },
      );
      final answer = writeIn(
        root,
        (s) =>
            answerMove(s, 'user_story:shop/cart/add_item', under: 'shop/pay'),
      );
      expect(readDoc(root, 'notes.md'), 'See `shop/pay/add_item`.\n');
      expect(
        codeText(root, 'app/lib/cart.dart'),
        '// Adds `shop/pay/add_item` and '
        '`user_story:shop/pay/add_item#acceptance_criteria`.\n'
        'final plain = "shop/cart/add_item";\n',
      );
      expect(
        codeText(root, 'app/lib/SKILL.md'),
        skill.replaceFirst(
          'Use `shop/cart/add_item`',
          'Use `shop/pay/add_item`',
        ),
      );
      expect(
        answer.json['rewritten'],
        containsAll(['notes.md', 'app/lib/cart.dart', 'app/lib/SKILL.md']),
      );
    });

    test('document_writing/move_story/rewrite_moved_story_references E07: a move stamps an approved doc whose mention it rewrites', () async {
      final root = await writeNestedProject();
      final approvedText =
          '${readDoc(root, shopDomain)}\nSee `shop/cart/add_item`.\n';
      docFile(root, shopDomain).writeAsStringSync(
        writeIn(
          root,
          (s) => withApprovalHash(approvedText, s.docTypeAt(shopDomain)),
        ),
      );
      final before = approvedHash(root, shopDomain);
      writeIn(
        root,
        (s) =>
            answerMove(s, 'user_story:shop/cart/add_item', under: 'shop/pay'),
      );
      expect(readDoc(root, shopDomain), contains('`shop/pay/add_item`'));
      expect(approvedHash(root, shopDomain), isNot(before));
      expect(staleDocs(root), isNot(contains(shopDomain)));
    });

    test('document_writing/rename_doc/rewrite_name_references: a code entry that names a file has that file rewritten', () async {
      const before = '// `login/email_login`\n';
      final root = await writeCheckProject(
        extra: {
          ...doc(techStack, '- app/lib/\n', '- app/lib/note.dart\n'),
          'app/lib/note.dart': before,
          'app/lib/other.dart': before,
        },
      );
      final answer = renameLogin(root);
      expect(codeText(root, 'app/lib/note.dart'), '// `signin/email_login`\n');
      expect(codeText(root, 'app/lib/other.dart'), before);
      expect(answer.json['rewritten'], contains('app/lib/note.dart'));
    });

    test('document_writing/rename_doc/rewrite_name_references: an executable code file stays executable after its rewrite', () async {
      final root = await writeCheckProject(
        extra: {'app/lib/run.sh': '# `login/email_login`\n'},
      );
      Process.runSync('chmod', ['755', '${root.path}/app/lib/run.sh']);
      renameLogin(root);
      expect(codeText(root, 'app/lib/run.sh'), '# `signin/email_login`\n');
      expect(File('${root.path}/app/lib/run.sh').statSync().mode & 0xFFF, 493);
    }, skip: Platform.isWindows ? 'Windows has no permission bits' : false);

    group('a code root outside the project root', () {
      late Directory outside;
      late String folder;

      setUp(() {
        outside = Directory.systemTemp.createTempSync('specstone_outside_');
        addTearDown(() => outside.deleteSync(recursive: true));
        folder = outside.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      });

      Future<Directory> project() async {
        File('${outside.path}/app/lib/doc.dart')
          ..createSync(recursive: true)
          ..writeAsStringSync('// `login/email_login`\n');
        return writeCheckProject(
          extra: {
            '.specstone/config.yaml':
                '${shippedPinsConfig()}code_root: ../$folder\n',
          },
        );
      }

      test('document_writing/rename_doc/rewrite_name_references: rename rewrites its file and lists it by a ../ path', () async {
        final root = await project();
        final answer = renameLogin(root);
        expect(
          File('${outside.path}/app/lib/doc.dart').readAsStringSync(),
          '// `signin/email_login`\n',
        );
        expect(answer.json['rewritten'], ['../$folder/app/lib/doc.dart']);
      });

      test('document_writing/rename_doc/rewrite_name_references: a stopped run replays its write to the same file', () async {
        final root = await project();
        writeJournal(root, [
          WriteStep(
            '../$folder/app/lib/doc.dart',
            '// `signin/email_login`\n',
            before: textHashOf('// `login/email_login`\n'),
          ),
        ]);
        writeIn(root, (s) => s.index.docs.length);
        expect(
          File('${outside.path}/app/lib/doc.dart').readAsStringSync(),
          '// `signin/email_login`\n',
        );
        expect(MoveJournal.pending(root), isFalse);
      });
    });

    group('a replayed write step', () {
      const original = 'old text\n';
      const planned = 'new text\n';
      const edited = 'old text\nthe user added a line\n';

      // A doc and a code file, each with the step the run planned for it.
      final cases = {
        'a doc': ('docs/notes.md', 'notes.md'),
        'a code file': ('app/lib/note.dart', 'app/lib/note.dart'),
      };

      for (final MapEntry(key: label, value: (path, _)) in cases.entries) {
        Future<Directory> stopped(String onDisk) async {
          final root = await writeCheckProject(extra: {path: onDisk});
          writeJournal(root, [
            WriteStep(path, planned, before: textHashOf(original)),
          ]);
          return root;
        }

        String text(Directory root) =>
            File('${root.path}/$path').readAsStringSync();

        test(
          'document_writing/delete_doc_subtree/finish_interrupted_move: $label that holds the step text counts as done',
          () async {
            final root = await stopped(planned);
            writeIn(root, (s) => s.index.docs.length);
            expect(text(root), planned);
            expect(MoveJournal.pending(root), isFalse);
          },
        );

        test(
          'document_writing/delete_doc_subtree/finish_interrupted_move: $label that holds the planned-from text gets the step',
          () async {
            final root = await stopped(original);
            writeIn(root, (s) => s.index.docs.length);
            expect(text(root), planned);
            expect(MoveJournal.pending(root), isFalse);
          },
        );

        test(
          'document_writing/delete_doc_subtree/finish_interrupted_move: $label edited after the stop is left as it is, named in a warning, and the journal still clears',
          () async {
            final root = await stopped(edited);
            final lines = <String>[];
            final target = JournalTarget(
              projectRoot: root,
              docsRoot: Directory('${root.path}/docs'),
              warn: lines.add,
            );
            WriteStep(
              path,
              planned,
              before: textHashOf(original),
            ).apply(target);
            expect(text(root), edited);
            expect(lines, [
              '$path changed since the stopped run; left as it is',
            ]);
            writeIn(root, (s) => s.index.docs.length);
            expect(text(root), edited);
            expect(MoveJournal.pending(root), isFalse);
          },
        );
      }
    });
  });
}
