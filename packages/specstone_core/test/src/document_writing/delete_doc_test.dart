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

import '../../helpers/failing_rename.dart';
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

const _journeyPath = 'prds/journeys/sign_in/JOURNEY.md';

/// A journey whose step 1 names [scenario] of the story reset_password.
Map<String, String> _journeyNaming(String scenario) => {
  'docs/$_journeyPath':
      '---\ndraft: true\n---\n\n# Sign in\n\n## Goal\nGet in.\n\n'
      '## Flow\n\n## Steps\n'
      '### 1. Reset\nstep: login/reset_password $scenario\n',
};

/// A project where only the journey refers into the login feature.
Map<String, String> _onlyJourneyRefers(String scenario) => {
  ...withoutLink,
  ...freeStory3,
  'docs/prds/FEATURES.md': '# Feature index\n\n## Systems\n- [Signup](features/f02_signup/FEATURE.md)\n',
  'docs/prds/d01_context.md': '# Context\n',
  'docs/$persona':
      '---\ndraft: true\n---\n\n# Buyer\n\n## Profile\nBuys things.\n',
  ..._journeyNaming(scenario),
};

void main() {
  ReadAnswer del(
    Directory root,
    List<String> targets, {
    bool interactive = false,
    List<String?> answers = const [],
    StringBuffer? prompts,
  }) {
    final queue = [...answers];
    return writeIn(
      root,
      (s) => answerDelete(
        s,
        targets,
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
    del(root, ['user_story:login/reset_password']);
    expect(
      Directory('${outside.path}/prds/features/f01_login/us03_reset_password')
          .existsSync(),
      isFalse,
    );
  }, skip: Platform.isWindows ? 'links need privileges on Windows' : false);

  test('f02/us04/s1, f02/us04/fr01, f02/us04/fr01/e01, f02/us04/fr01/e07, f02/us04/fr02/e01, dw-s03/inv7, dw-s03/inv9: a draft story goes with its requirements, siblings keep their numbers', () async {
    final root = await writeWriteProject(extra: withoutLink);
    final prompts = StringBuffer();
    final answer = del(root, [
      'user_story:login/reset_password',
    ], prompts: prompts);
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
      () => del(root, ['user_story:login/reset_password']),
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
      () => del(root, ['fr:login/email_login/validate_credentials']),
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
        ['user_story:login/sign_out'],
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
        ['user_story:login/sign_out'],
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
      del(root, ['fr:login/reset_password/expire_reset_link']).json['removed'],
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
      expect(del(root, ['feature:signup']).json['removed'], [
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
    expect(del(root, ['persona:buyer']).json['removed'], [
      antiPersona,
      persona,
    ]);
    expect(Directory('${root.path}/docs/prds/personas').existsSync(), isFalse);
    expect(Directory('${root.path}/docs').existsSync(), isTrue);
  });

  test('f02/us04/fr01/e05: a spec doc goes alone', () async {
    final root = await writeWriteProject();
    expect(del(root, ['architecture:signup']).json['removed'], [signupArch]);
    expect(hasDoc(root, signupFeature), isTrue);
  });

  test(
    'f02/us04/fr01/e06: a doc_ref value from outside is a referrer too',
    () async {
      final root = await writeWriteProject();
      expect(
        () => del(root, ['user_story:login/email_login']),
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
    del(root, ['user_story:login/reset_password']);
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

  test('f02/us04/fr01/e07, final Important 3: an unreadable unit path names itself', () async {
    const folder = 'prds/features/f01_login/us03_reset_password';
    for (final (name, mode, target) in [
      ('folder', '000', folder),
      ('file', '000', '$folder/fr01_send_reset_link.md'),
    ]) {
      final root = await writeWriteProject(extra: withoutLink);
      final entity = '${root.path}/docs/$target';
      addTearDown(() => Process.runSync('chmod', ['755', entity]));
      expect(
        () => writeIn(root, (s) {
          Process.runSync('chmod', [mode, entity]);
          return answerDelete(
            s,
            ['user_story:login/reset_password'],
            interactive: false,
            readLine: () => null,
            prompts: StringBuffer(),
          );
        }),
        throwsA(
          isA<RenderFault>()
              .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
              .having(
                (f) => f.message,
                '$name message',
                startsWith('cannot read $target: '),
              ),
        ),
      );
    }
  }, skip: unreadablePathSkipReason() ?? false);

  test('f02/us04/fr01/e12, nfr-di01: an unmovable file is output_not_writable; the journal stays and the next write finishes the delete', () async {
    final root = await writeWriteProject(extra: withoutLink);
    final locked = Directory(
      '${root.path}/docs/prds/features/f01_login/us03_reset_password',
    );
    expect(
      () => IOOverrides.runWithIOOverrides(
        () => del(root, ['user_story:login/reset_password']),
        FailingRenameHook('docs/$fr31'),
      ),
      throwsA(
        isA<RenderFault>()
            .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
            .having((f) => f.message, 'message', contains(fr31)),
      ),
    );
    expect(
      File('${root.path}/${MoveJournal.journalPath}').existsSync(),
      isTrue,
    );
    writeIn(root, (s) => s.index.docs.length);
    expect(locked.existsSync(), isFalse);
    expect(Directory('${root.path}/.specstone/trash').existsSync(), isFalse);
  });

  test(
    'f02/us04/fr02/e05: a doc carrying draft and approved counts as approved',
    () async {
      final root = await writeWriteProject(
        extra: {
          'docs/$fr32': '---\ndraft: true\napproved: true\ntraced_from: US-03\nverify_method: test\n---\n\n# Expire reset link\n',
        },
      );
      expect(
        () => del(root, ['fr:login/reset_password/expire_reset_link']),
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
        ['user_story:login/reset_password'],
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
        ['user_story:login/sign_out'],
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
      () => del(root, ['user_story:login/reset_password']),
      refusesWith(WriteFaultCode.ownerTerminalRequired),
    );
    expect(hasDoc(root, story3), isTrue);
  });

  test('f02/us04/fr02/e03: review focus 5, PD9: the end of input at the delete prompt removes nothing', () async {
    final root = await writeWriteProject(extra: approvedSignOut);
    final answer = del(root, ['user_story:login/sign_out'], interactive: true);
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
      del(root, ['user_story:login/reset_password']).json['removed'],
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
    expect(del(root, ['topic:doc_model']).json['removed'], [
      'specs/topics/doc_model.md',
    ]);
    expect(Directory('${root.path}/docs/specs/topics').existsSync(), isFalse);
    expect(Directory('${root.path}/docs/specs').existsSync(), isTrue);
  });

  test('f02/us04/fr01, dw-s03/inv7, H09: an empty subfolder and a symlink in the unit go, and so does the unit folder', () async {
    final root = await writeWriteProject(extra: withoutLink);
    final outside = Directory.systemTemp.createTempSync('specstone_keep_');
    addTearDown(() => outside.deleteSync(recursive: true));
    File('${outside.path}/keep.md').writeAsStringSync('keep\n');
    final unit =
        '${root.path}/docs/prds/features/f01_login/us03_reset_password';
    Directory('$unit/empty/deeper').createSync(recursive: true);
    Link('$unit/shortcut').createSync(outside.path);
    Link('$unit/dangling').createSync('${outside.path}/missing.md');

    del(root, ['user_story:login/reset_password']);

    expect(Directory(unit).existsSync(), isFalse);
    expect(File('${outside.path}/keep.md').readAsStringSync(), 'keep\n');
  }, skip: Platform.isWindows ? 'links need privileges on Windows' : false);

  test('f02/us04/fr02/e07, dw-s03/inv7, HD2: a link added while the prompt waits refuses doc_referenced', () async {
    final root = await writeWriteProject(extra: approvedSignOut);
    final outsider = docFile(root, story1);
    final before = outsider.readAsStringSync();
    Object? caught;
    try {
      writeIn(
        root,
        (s) => answerDelete(
          s,
          ['user_story:login/sign_out'],
          interactive: true,
          readLine: () {
            outsider.writeAsStringSync(
              '$before\nSee [out](../us02_sign_out/fr01_end_session.md).\n',
            );
            return 'y';
          },
          prompts: StringBuffer(),
        ),
      );
    } on WriteFault catch (fault) {
      caught = fault;
    }
    expect(caught, isA<WriteFault>());
    final fault = caught! as WriteFault;
    expect(fault.code, WriteFaultCode.docReferenced);
    expect(fault.relatedFiles, [story1]);
    expect(hasDoc(root, '$_signOut/fr01_end_session.md'), isTrue);
    expect(hasDoc(root, story2), isTrue);
    expect(Directory('${root.path}/.specstone/trash').existsSync(), isFalse);
  });

  test('f02/us04/fr02/e07, nfr-di01, dw-s03/inv9: a replay fault during the refresh after y is a RenderFault and the session closes once', () async {
    final root = await writeWriteProject(extra: approvedSignOut);
    expect(
      () => writeIn(
        root,
        (s) => answerDelete(
          s,
          ['user_story:login/sign_out'],
          interactive: true,
          readLine: () {
            File('${root.path}/${MoveJournal.journalPath}')
              ..parent.createSync(recursive: true)
              ..writeAsStringSync('not json');
            return 'y';
          },
          prompts: StringBuffer(),
        ),
      ),
      throwsA(isA<RenderFault>()),
    );
    expect(hasDoc(root, story2), isTrue);
  });

  test('f02/us04/fr02/e07, H12: a byte changed while the prompt waits lists the unit and prompts again', () async {
    final root = await writeWriteProject(extra: approvedSignOut);
    final changed = docFile(root, '$_signOut/fr01_end_session.md');
    final prompts = StringBuffer();
    var asked = 0;
    final answer = writeIn(
      root,
      (s) => answerDelete(
        s,
        ['user_story:login/sign_out'],
        interactive: true,
        readLine: () {
          asked++;
          if (asked == 1) {
            changed.writeAsStringSync(
              '---\napproved: true\n---\n\n# End sessioN\n',
            );
          }
          return 'y';
        },
        prompts: prompts,
      ),
    );
    expect(asked, 2);
    expect(
      'delete 3 files? [y/N] '.allMatches(prompts.toString()),
      hasLength(2),
    );
    expect(answer.json['removed'], hasLength(3));
    expect(Directory('${root.path}/docs/$_signOut').existsSync(), isFalse);
  });

  test('f02/us04/fr01/e06, H11: referrersOf: doc_ref referrers, then link referrers, each once in tree order', () async {
    // The persona refers to story1 by doc_ref and by link: still listed once,
    // in the doc_ref group. d01_context and fr11 link to it; d01_context comes
    // first in tree order.
    final root = await writeWriteProject(
      extra: {
        'docs/$persona': '---\ndraft: true\nreference:\n  - login/email_login\n---\n\n# Buyer\n\n## Profile\nBuys things. See [login](../../features/f01_login/us01_email_login/USER_STORY.md).\n',
        'docs/prds/d01_context.md': '# Context\n\n## Features\nSee [signup](features/f02_signup/FEATURE.md) and [login](features/f01_login/us01_email_login/USER_STORY.md).\n',
        'docs/$fr11': writeProject['docs/$fr11']!.replaceFirst(
          'The system shall check',
          'See [story](USER_STORY.md). The system shall check',
        ),
      },
    );
    List<String> referrers(String docPath) => writeIn(
      root,
      (s) => [
        for (final doc in referrersOf(s.index, s.index.at(docPath)!))
          doc.docPath,
      ],
    );
    expect(referrers(story1), [persona, 'prds/d01_context.md', fr11]);
    expect(referrers(story3), [fr12]);
  });

  group('untyped DocPaths and several targets', () {
    const notes = 'specs/f01_login/api_notes.md';
    const errors = 'specs/f01_login/api_errors.md';
    const index = 'specs/INDEX.md';
    const scratch = 'specs/f01_login/scratch.md';
    final untyped = <String, String>{
      'docs/$notes': '# Notes\n\nSee [errors](api_errors.md).\n',
      'docs/$errors': '# Errors\n\nSee [index](../INDEX.md).\n',
      'docs/$index': '# Index\n\nNothing links here but api_errors.md.\n',
      'docs/$scratch': '---\ndraft: true\n---\n\n# Scratch\n',
    };

    test(
      'f02/us04/fr04/e01: an untyped DocPath deletes that one file only',
      () async {
        final root = await writeWriteProject(extra: untyped);
        final answer = del(root, [scratch]);
        expect(answer.json, {
          'removed': [scratch],
        });
        expect(hasDoc(root, scratch), isFalse);
        expect(hasDoc(root, loginArch), isTrue);
      },
    );

    test("f02/us04/fr04/e02: an Agent's delete of an untyped doc with no draft is owner_terminal_required", () async {
      final root = await writeWriteProject(extra: untyped);
      expect(
        () => del(root, [notes]),
        refusesWith(WriteFaultCode.ownerTerminalRequired),
      );
      expect(hasDoc(root, notes), isTrue);
    });

    test('f02/us04/s8, f02/us04/fr04, f02/us04/fr04/e03: three untyped docs that link to each other go in one call', () async {
      final root = await writeWriteProject(extra: untyped);
      final prompts = StringBuffer();
      final answer = del(
        root,
        [notes, errors, index],
        interactive: true,
        answers: ['y'],
        prompts: prompts,
      );
      expect(prompts.toString(), endsWith('delete 3 files? [y/N] '));
      expect(answer.json, {
        'removed': [errors, notes, index]..sort(),
      });
      for (final path in [notes, errors, index]) {
        expect(hasDoc(root, path), isFalse);
      }
      expect(
        File('${root.path}/${MoveJournal.journalPath}').existsSync(),
        isFalse,
      );
    });

    test(
      'f02/us04/fr04/e02: several targets name the set in the Owner gate',
      () async {
        final root = await writeWriteProject(extra: untyped);
        expect(
          () => del(root, [notes, errors, index]),
          throwsA(
            isA<WriteFault>().having(
              (f) => f.message,
              'message',
              'the delete set holds approved docs; only the Owner deletes '
                  'them, at an interactive terminal',
            ),
          ),
        );
      },
    );

    test('f02/us04/s9, f02/us04/fr04/e04: a story outside two docs that links into one is doc_referenced, and neither goes', () async {
      final root = await writeWriteProject(
        extra: {
          ...untyped,
          'docs/$story1':
              '${writeProject['docs/$story1']}\n'
              'See [errors](../../../../specs/f01_login/api_errors.md).\n',
        },
      );
      expect(
        () => del(root, [notes, errors], interactive: true, answers: ['y']),
        throwsA(
          isA<WriteFault>()
              .having((f) => f.code, 'code', WriteFaultCode.docReferenced)
              .having(
                (f) => f.message,
                'message',
                'docs outside the delete set link into it',
              )
              .having((f) => f.file, 'file', errors)
              .having((f) => f.relatedFiles, 'relatedFiles', [story1]),
        ),
      );
      expect(hasDoc(root, notes), isTrue);
      expect(hasDoc(root, errors), isTrue);
    });

    test('f02/us04/fr04/e05: a target inside the unit of another counts each file once', () async {
      final root = await writeWriteProject(extra: withoutLink);
      final answer = del(root, [
        'user_story:login/reset_password',
        'fr:login/reset_password/expire_reset_link',
      ]);
      expect(answer.json, {
        'removed': [story3, fr31, fr32],
      });
    });

    test(
      'f02/us04/fr04/e05: the same target twice removes its file once',
      () async {
        final root = await writeWriteProject(extra: untyped);
        final answer = del(root, [scratch, scratch]);
        expect(answer.json, {
          'removed': [scratch],
        });
      },
    );

    test('f02/us04/fr04/e06: one target of several that names no doc is doc_not_found, and nothing goes', () async {
      final root = await writeWriteProject(extra: untyped);
      expect(
        () => del(root, [scratch, 'user_story:login/no_such_story']),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.docNotFound)
              .having((f) => f.message, 'message', contains('no_such_story')),
        ),
      );
      expect(hasDoc(root, scratch), isTrue);
    });

    test('f02/us04/fr01/e10: a bare typed name among several targets stays argument_invalid', () async {
      final root = await writeWriteProject(extra: untyped);
      expect(
        () => del(root, [scratch, 'email_login']),
        throwsA(
          isA<IndexFault>().having(
            (f) => f.code,
            'code',
            IndexFaultCode.argumentInvalid,
          ),
        ),
      );
      expect(hasDoc(root, scratch), isTrue);
    });
  });

  group('journeys as referrers', () {
    Matcher refusedForJourney(String file) => throwsA(
      isA<WriteFault>()
          .having((f) => f.code, 'code', WriteFaultCode.docReferenced)
          .having((f) => f.file, 'file', file)
          .having((f) => f.relatedFiles, 'relatedFiles', [_journeyPath]),
    );

    test('f02/us04/s10, f02/us04/fr05/e01: delete of a story a journey step names is doc_referenced', () async {
      final root = await writeWriteProject(extra: _onlyJourneyRefers('S1'));
      expect(
        () => del(root, ['user_story:login/reset_password']),
        refusedForJourney(story3),
      );
      expect(hasDoc(root, story3), isTrue);
      expect(hasDoc(root, _journeyPath), isTrue);
    });

    test(
      "f02/us04/fr05/e02: delete of the story's feature is doc_referenced",
      () async {
        final root = await writeWriteProject(extra: _onlyJourneyRefers('S1'));
        expect(
          () => del(root, ['feature:login']),
          refusedForJourney(loginFeature),
        );
        expect(hasDoc(root, loginFeature), isTrue);
      },
    );

    test('f02/us04/fr05/e03: delete of the journey removes its folder; its steps point out of the unit', () async {
      final root = await writeWriteProject(extra: _onlyJourneyRefers('S1'));
      expect(del(root, ['journey:sign_in']).json['removed'], [_journeyPath]);
      expect(
        Directory('${root.path}/docs/prds/journeys/sign_in').existsSync(),
        isFalse,
      );
      expect(hasDoc(root, story3), isTrue);
    });

    test(
      'f02/us04/fr05/e04: the journey and the story in one call are removed',
      () async {
        final root = await writeWriteProject(extra: _onlyJourneyRefers('S1'));
        expect(
          del(root, [
            'journey:sign_in',
            'user_story:login/reset_password',
          ]).json['removed'],
          containsAll([_journeyPath, story3]),
        );
        expect(
          [hasDoc(root, _journeyPath), hasDoc(root, story3)],
          [false, false],
        );
      },
    );

    test('f02/us04/fr05/e05: a step naming a missing scenario of a story in the unit still refers to it', () async {
      final root = await writeWriteProject(extra: _onlyJourneyRefers('S9'));
      expect(
        () => del(root, ['user_story:login/reset_password']),
        refusedForJourney(story3),
      );
      expect(hasDoc(root, story3), isTrue);
    });
  });
}
