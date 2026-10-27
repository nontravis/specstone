import 'dart:io';

import 'package:specstone_core/src/document_writing/delete_doc.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/set_doc.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/index_query/refs.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:test/test.dart';

import '../../helpers/posix_modes.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart';

/// [fr12] without its link into [story3], so the unit of [story3] is free.
const withoutLink = {
  'docs/$fr12': '---\ndraft: true\ntraced_from: US-01\nverify_method: test\n---\n\n# Lock after failures\n\n## Statement\nThe system shall lock the account.\n',
};

/// [story3] without its link into [story2], so the unit of [story2] is free.
const freeStory3 = {
  'docs/$story3': '---\nstatus: planned\ndraft: true\n---\n\n# Reset password\n\n## Use Case\nReset a password.\n',
};

const _signOut = 'prds/features/f01_login/us02_sign_out';

/// Two approved FRs in the folder of [story2], which is approved itself.
const Map<String, String> approvedSignOut = {
  ...freeStory3,
  'docs/$_signOut/fr01_end_session.md':
      '---\napproved: true\n---\n\n# End session\n',
  'docs/$_signOut/fr02_clear_cookies.md':
      '---\napproved: true\n---\n\n# Clear cookies\n',
};

void main() {
  ReadAnswer del(
    Directory root,
    String address, {
    bool interactive = false,
    List<String?> answers = const [],
    StringBuffer? prompts,
  }) {
    final queue = [...answers];
    return writeIn(
      root,
      (s) => answerDelete(
        s,
        address,
        interactive: interactive,
        readLine: () => queue.isEmpty ? null : queue.removeAt(0),
        prompts: prompts ?? StringBuffer(),
      ),
    );
  }

  Matcher refusesWith(WriteFaultCode code) =>
      throwsA(isA<WriteFault>().having((f) => f.code, 'code', code));

  test('dw-s03/inv7: a delete under a docs root linked outside the project removes the emptied folder', () async {
    final root = await writeWriteProject(
      without: {
        for (final k in writeProject.keys)
          if (k.startsWith('docs/')) k,
      },
    );
    final outside = await writeTree({
      for (final MapEntry(:key, :value) in {
        ...writeProject,
        ...withoutLink,
      }.entries)
        if (key.startsWith('docs/')) key.substring(5): value,
    });
    Link('${root.path}/docs').createSync(outside.path);
    del(root, 'user_story:login/reset_password');
    expect(
      Directory('${outside.path}/prds/features/f01_login/us03_reset_password')
          .existsSync(),
      isFalse,
    );
  }, skip: Platform.isWindows ? 'links need privileges on Windows' : false);

  test('f02/us04/s1, f02/us04/fr01, f02/us04/fr01/e01, f02/us04/fr01/e07, f02/us04/fr02/e01, dw-s03/inv7, dw-s03/inv9: a draft story goes with its requirements, siblings keep their numbers', () async {
    final root = await writeWriteProject(extra: withoutLink);
    final prompts = StringBuffer();
    final answer = del(
      root,
      'user_story:login/reset_password',
      prompts: prompts,
    );
    expect(answer.text, '$story3\n$fr31\n$fr32\n');
    expect(answer.json, {
      'removed': [story3, fr31, fr32],
    });
    expect(
      Directory('${root.path}/docs/prds/features/f01_login/us03_reset_password')
          .existsSync(),
      isFalse,
    );
    expect([hasDoc(root, story1), hasDoc(root, story2)], [true, true]);
    expect(Directory('${root.path}/.specstone/trash').existsSync(), isFalse);
    expect(prompts.toString(), isEmpty);
  });

  test('f02/us04/s5, f02/us04/fr01/e06: a doc outside that links into the unit is doc_referenced, and nothing is removed', () async {
    final root = await writeWriteProject();
    expect(
      () => del(root, 'user_story:login/reset_password'),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.docReferenced)
            .having(
              (f) => f.message,
              'message',
              'docs outside user_story:login/reset_password link into it',
            )
            .having((f) => f.file, 'file', story3)
            .having((f) => f.relatedFiles, 'relatedFiles', [fr12]),
      ),
    );
    expect(hasDoc(root, story3), isTrue);
  });

  test('f02/us04/s6, f02/us04/fr02, f02/us04/fr02/e02, f02/us04/fr02/e04: an Agent deleting an approved doc is owner_terminal_required', () async {
    final root = await writeWriteProject();
    expect(
      () => del(root, 'fr:login/email_login/validate_credentials'),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.exitStatus, 'exitStatus', 77)
            .having(
              (f) => f.message,
              'message',
              'fr:login/email_login/validate_credentials holds approved docs; only the Owner deletes them, at an interactive terminal',
            ),
      ),
    );
    expect(hasDoc(root, fr11), isTrue);
  });

  test('f02/us04/s3, f02/us04/fr02/e03: the Owner sees the paths and the prompt; y removes, any other answer keeps', () async {
    final root = await writeWriteProject(extra: approvedSignOut);
    final prompts = StringBuffer();
    expect(
      del(
        root,
        'user_story:login/sign_out',
        interactive: true,
        answers: ['n'],
        prompts: prompts,
      ).text,
      '',
    );
    expect(hasDoc(root, story2), isTrue);
    expect(
      prompts.toString(),
      '$story2\nprds/features/f01_login/us02_sign_out/fr01_end_session.md\n'
      'prds/features/f01_login/us02_sign_out/fr02_clear_cookies.md\ndelete 3 files? [y/N] ',
    );
    expect(
      del(
        root,
        'user_story:login/sign_out',
        interactive: true,
        answers: ['y'],
      ).json['removed'],
      hasLength(3),
    );
    expect(hasDoc(root, story2), isFalse);
  });

  test('f02/us04/fr01/e02: an FR goes alone', () async {
    final root = await writeWriteProject();
    expect(
      del(root, 'fr:login/reset_password/expire_reset_link').json['removed'],
      [fr32],
    );
    expect([hasDoc(root, fr31), hasDoc(root, story3)], [true, true]);
  });

  test(
    'f02/us04/s2, f02/us04/fr01/e03: a feature goes with its spec folder',
    () async {
      final root = await writeWriteProject(
        extra: {
          'docs/prds/FEATURES.md': '# Feature index\n\n## Systems\n- [Login](features/f01_login/FEATURE.md)\n',
          'docs/prds/d01_context.md': '# Context\n',
        },
      );
      expect(del(root, 'feature:signup').json['removed'], [
        signupFeature,
        signupArch,
      ]);
      expect(
        Directory('${root.path}/docs/prds/features/f02_signup').existsSync(),
        isFalse,
      );
      expect(
        Directory('${root.path}/docs/specs/f02_signup').existsSync(),
        isFalse,
      );
    },
  );

  test('f02/us04/fr01/e04, f02/us04/fr01/e08: a persona goes with the anti-persona in its folder, and the emptied personas folder goes too', () async {
    final root = await writeWriteProject(
      extra: {
        'docs/$story1': '---\nstatus: planned\ndraft: true\nvision:\n  - PV-01\n---\n\n# Sign in with email\n\n## Use Case\nSign in with an email.\n',
      },
    );
    expect(del(root, 'persona:buyer').json['removed'], [antiPersona, persona]);
    expect(Directory('${root.path}/docs/prds/personas').existsSync(), isFalse);
    expect(Directory('${root.path}/docs').existsSync(), isTrue);
  });

  test('f02/us04/fr01/e05: a spec doc goes alone', () async {
    final root = await writeWriteProject();
    expect(del(root, 'architecture:signup').json['removed'], [signupArch]);
    expect(hasDoc(root, signupFeature), isTrue);
  });

  test(
    'f02/us04/fr01/e06: a doc_ref value from outside is a referrer too',
    () async {
      final root = await writeWriteProject();
      expect(
        () => del(root, 'user_story:login/email_login'),
        throwsA(
          isA<WriteFault>()
              .having((f) => f.code, 'code', WriteFaultCode.docReferenced)
              .having((f) => f.relatedFiles, 'relatedFiles', [persona]),
        ),
      );
    },
  );

  test('f02/us04/s7, f02/us04/fr01/e11: a set on a deleted doc is doc_not_found and recreates nothing', () async {
    final root = await writeWriteProject(extra: withoutLink);
    del(root, 'user_story:login/reset_password');
    expect(
      () => writeIn(
        root,
        (s) => answerSet(
          s,
          SetRequest.parse(
            'user_story:login/reset_password#use_case',
            base: 'abc',
          ),
          'Back again.\n',
        ),
      ),
      throwsA(
        isA<IndexFault>().having(
          (f) => f.code,
          'code',
          IndexFaultCode.docNotFound,
        ),
      ),
    );
    expect(hasDoc(root, story3), isFalse);
  });

  test('f02/us04/fr01/e12, nfr-di01: an unmovable file is output_not_writable; the journal stays and the next write finishes the delete', () async {
    final root = await writeWriteProject(extra: withoutLink);
    final locked = Directory(
      '${root.path}/docs/prds/features/f01_login/us03_reset_password',
    );
    Process.runSync('chmod', ['555', locked.path]);
    addTearDown(() => Process.runSync('chmod', ['755', locked.path]));
    expect(
      () => del(root, 'user_story:login/reset_password'),
      throwsA(
        isA<RenderFault>().having(
          (f) => f.code,
          'code',
          RenderFaultCode.outputNotWritable,
        ),
      ),
    );
    expect(
      File('${root.path}/${MoveJournal.journalPath}').existsSync(),
      isTrue,
    );
    Process.runSync('chmod', ['755', locked.path]);
    writeIn(root, (s) => s.index.docs.length);
    expect(locked.existsSync(), isFalse);
    expect(Directory('${root.path}/.specstone/trash').existsSync(), isFalse);
  }, skip: unreadablePathSkipReason() ?? false);

  test(
    'f02/us04/fr02/e05: a doc carrying draft and approved counts as approved',
    () async {
      final root = await writeWriteProject(
        extra: {
          'docs/$fr32': '---\ndraft: true\napproved: true\ntraced_from: US-03\nverify_method: test\n---\n\n# Expire reset link\n',
        },
      );
      expect(
        () => del(root, 'fr:login/reset_password/expire_reset_link'),
        refusesWith(WriteFaultCode.ownerTerminalRequired),
      );
      expect(hasDoc(root, fr32), isTrue);
    },
  );

  test('f02/us04/fr02/e06: the Owner deleting a never-approved unit sees no prompt', () async {
    final root = await writeWriteProject(extra: withoutLink);
    final prompts = StringBuffer();
    expect(
      del(
        root,
        'user_story:login/reset_password',
        interactive: true,
        prompts: prompts,
      ).json['removed'],
      hasLength(3),
    );
    expect(prompts.toString(), isEmpty);
  });

  test('f02/us04/fr02/e07: a file added while the prompt waits lists the unit and prompts again', () async {
    final root = await writeWriteProject(extra: approvedSignOut);
    final prompts = StringBuffer();
    var asked = 0;
    final answer = writeIn(
      root,
      (s) => answerDelete(
        s,
        'user_story:login/sign_out',
        interactive: true,
        readLine: () {
          asked++;
          if (asked == 1) {
            docFile(
              root,
              '$_signOut/fr03_new.md',
            ).writeAsStringSync('---\ndraft: true\n---\n\n# New\n');
          }
          return 'y';
        },
        prompts: prompts,
      ),
    );
    expect(asked, 2);
    expect('delete '.allMatches(prompts.toString()), hasLength(2));
    expect(prompts.toString(), contains('delete 3 files? [y/N] '));
    expect(prompts.toString(), contains('delete 4 files? [y/N] '));
    expect(answer.json['removed'], hasLength(4));
    expect(Directory('${root.path}/docs/$_signOut').existsSync(), isFalse);
  });

  test('f02/us04/fr02/e08: an untyped .md file in the unit with no draft counts as approved', () async {
    final root = await writeWriteProject(
      extra: {
        ...withoutLink,
        'docs/prds/features/f01_login/us03_reset_password/notes.md':
            '# Notes\n',
      },
    );
    expect(
      () => del(root, 'user_story:login/reset_password'),
      refusesWith(WriteFaultCode.ownerTerminalRequired),
    );
    expect(hasDoc(root, story3), isTrue);
  });

  test('f02/us04/fr02/e03: review focus 5, PD9: the end of input at the delete prompt removes nothing', () async {
    final root = await writeWriteProject(extra: approvedSignOut);
    final answer = del(root, 'user_story:login/sign_out', interactive: true);
    expect(answer.text, isEmpty);
    expect(answer.json, {'removed': <String>[]});
    expect(hasDoc(root, story2), isTrue);
  });

  test('f02/us04/s1, dw-s03/inv7: a non-.md file in the unit goes to the trash with it', () async {
    final root = await writeWriteProject(
      extra: {
        ...withoutLink,
        'docs/prds/features/f01_login/us03_reset_password/flow.png': 'png',
      },
    );
    expect(
      del(root, 'user_story:login/reset_password').json['removed'],
      [
        story3,
        fr31,
        fr32,
        'prds/features/f01_login/us03_reset_password/flow.png',
      ]..sort(),
    );
    expect(
      Directory('${root.path}/docs/prds/features/f01_login/us03_reset_password')
          .existsSync(),
      isFalse,
    );
  });

  test('f02/us04/s6, dw-s03/inv7: the folder a removed file segment leaves empty goes, and the folder that still holds a doc stays', () async {
    final root = await writeWriteProject(
      extra: {
        'docs/specs/topics/doc_model.md':
            '---\ndraft: true\ncovers:\n  - app/lib/\n---\n\n# Doc model\n',
      },
    );
    expect(del(root, 'topic:doc_model').json['removed'], [
      'specs/topics/doc_model.md',
    ]);
    expect(Directory('${root.path}/docs/specs/topics').existsSync(), isFalse);
    expect(Directory('${root.path}/docs/specs').existsSync(), isTrue);
  });

  test('f02/us04/fr01/e06: referrersOf: doc_ref referrers, then link referrers, each once in tree order', () async {
    final root = await writeWriteProject();
    List<String> referrers(String docPath) => writeIn(
      root,
      (s) => [
        for (final doc in referrersOf(s.index, s.index.at(docPath)!))
          doc.docPath,
      ],
    );
    expect(referrers(story1), [persona]);
    expect(referrers(story3), [fr12]);
  });
}
