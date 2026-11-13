import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/document_writing/delete_doc.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/owner_confirmation.dart';
import 'package:specstone_core/src/document_writing/root_trust.dart';
import 'package:specstone_core/src/document_writing/set_doc.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/index_query/refs.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' as check show checkOf, loginApi;
import '../../helpers/failing_rename.dart';
import '../../helpers/git_repo.dart';
import '../../helpers/nested_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/record_fixture.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/target_fixture.dart';
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

const _loginRecord = 'specs/f01_login/IMPLEMENTATION.md';
const _signupRecord = 'specs/f02_signup/IMPLEMENTATION.md';
const _cartRecord = 'specs/f02_shop/f01_cart/IMPLEMENTATION.md';

/// The `login` record of the write project: the statuses and code paths of
/// [story1] and of [story3] with its two FRs.
final String _loginRecordText = recordText(
  front: 'approved: true\n',
  statuses: [
    'email_login:implemented',
    'reset_password:implemented',
    'reset_password/send_reset_link:planned',
    'reset_password/expire_reset_link:planned',
  ],
  code: [
    'email_login:app/lib/login.dart:SignIn',
    'reset_password:app/lib/reset.dart:ResetPage',
  ],
);

/// A record layer, one code root, and a record for `login` and for `signup`,
/// on top of [freeStory3].
Map<String, String> _withRecords({String? login}) => {
  ...withoutLink,
  '.specstone/templates/implementation.yaml': recordLayer,
  '.specstone/config.yaml': '${shippedPinsConfig()}code_root: app\n',
  'docs/$_loginRecord': login ?? _loginRecordText,
  'docs/$_signupRecord': recordText(statuses: ['ghost:planned']),
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
    OwnerConfirmation confirmation = OwnerConfirmation.missing,
    List<String?> answers = const [],
    StringBuffer? prompts,
    String? planHash,
    String? codeTarget,
  }) {
    final queue = [...answers];
    return writeIn(
      root,
      (s) => answerDelete(
        s,
        targets,
        confirmation: confirmation,
        planHash: planHash,
        codeTarget: codeTarget,
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
    RootTrust.locate(root, homeDirectory: testHome()).record();
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
      'mentions': <Object>[],
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
              "fr:login/email_login/validate_credentials holds guarded docs; only the Owner deletes them, at an interactive terminal, or with --yes after the Owner's ok in the chat",
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
        confirmation: OwnerConfirmation.prompt,
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
        confirmation: OwnerConfirmation.prompt,
        answers: ['y'],
      ).json['removed'],
      hasLength(3),
    );
    expect(hasDoc(root, story2), isFalse);
  });

  const signOutUnit = [
    story2,
    'prds/features/f01_login/us02_sign_out/fr01_end_session.md',
    'prds/features/f01_login/us02_sign_out/fr02_clear_cookies.md',
  ];

  test('ms-r11: a dry run lists every file the unit removes and its plan '
      'line, and removes nothing', () async {
    final root = await writeWriteProject(extra: approvedSignOut);
    final answer = writeIn(
      root,
      (s) => answerDeleteDryRun(s, ['user_story:login/sign_out']),
    );
    final list = signOutUnit.map((path) => '$path\n').join();
    final hashed = signOutUnit
        .map((path) => '$path ${baseHashOf(toLf(readDoc(root, path)))}\n')
        .join();
    final hash = baseHashOf(hashed);
    expect(answer.text, '${list}plan $hash\ndry run: nothing removed\n');
    expect(answer.json, {
      'files': signOutUnit,
      'records': isEmpty,
      'mentions': <Object>[],
      'plan': hash,
    });
    expect(hasDoc(root, story2), isTrue);
  });

  group('mentions in code files and agent files', () {
    const code =
        '// `login/reset_password` goes\n'
        '// `login/email_login` stays\n'
        '// docs/$story3 is gone\n'
        '// `login/reset_password/send_reset_link`\n';
    const agent = 'Read `user_story:login/reset_password#use_case` first.\n';

    Future<Directory> withMentions() => writeWriteProject(
      extra: {
        ...withoutLink,
        'docs/specs/TECH_STACK.md':
            '---\ncode:\n  - app/lib/\n---\n\n# Tech stack\n\n## Stack\n\n'
            '| Slot | Choice |\n|---|---|\n| Language | Dart |\n\n'
            '## Naming\n\n- snake_case file names\n',
        'app/lib/reset.dart': code,
        'CLAUDE.md': agent,
      },
    );

    const listed =
        'mentions CLAUDE.md:1 user_story:login/reset_password#use_case\n'
        'mentions app/lib/reset.dart:1 login/reset_password\n'
        'mentions app/lib/reset.dart:3 docs/$story3\n'
        'mentions app/lib/reset.dart:4 login/reset_password/send_reset_link\n';

    test(
      'a dry run lists them after the files and before the plan line',
      () async {
        final root = await withMentions();
        final answer = writeIn(
          root,
          (s) => answerDeleteDryRun(s, ['user_story:login/reset_password']),
        );
        expect(
          answer.text,
          contains(
            '$fr32\n$listed'
            'plan ',
          ),
        );
        expect(answer.json['mentions'], [
          {
            'path': 'CLAUDE.md',
            'line': 1,
            'mention': 'user_story:login/reset_password#use_case',
          },
          {
            'path': 'app/lib/reset.dart',
            'line': 1,
            'mention': 'login/reset_password',
          },
          {'path': 'app/lib/reset.dart', 'line': 3, 'mention': 'docs/$story3'},
          {
            'path': 'app/lib/reset.dart',
            'line': 4,
            'mention': 'login/reset_password/send_reset_link',
          },
        ]);
      },
    );

    test('a delete lists them after the removed paths and keeps every byte '
        'of those files', () async {
      final root = await withMentions();
      final answer = del(root, ['user_story:login/reset_password']);
      expect(answer.text, endsWith('$fr32\n$listed'));
      expect(answer.json['mentions'], hasLength(4));
      expect(File('${root.path}/app/lib/reset.dart').readAsStringSync(), code);
      expect(File('${root.path}/CLAUDE.md').readAsStringSync(), agent);
    });
  });

  test('f02/us04/fr06/e08: the plan hash is the same outside git, in a repo '
      'with no commit, and in one with a commit', () async {
    final root = await writeWriteProject(extra: approvedSignOut);
    final expected = baseHashOf(
      signOutUnit
          .map((path) => '$path ${baseHashOf(toLf(readDoc(root, path)))}\n')
          .join(),
    );
    String planOf() =>
        writeIn(
              root,
              (s) => answerDeleteDryRun(s, ['user_story:login/sign_out']),
            ).json['plan']!
            as String;

    expect(planOf(), expected, reason: 'outside git');
    expect(git(root, ['init', '-q']).exitCode, 0);
    expect(planOf(), expected, reason: 'no commit');
    commitAll(root, 'first');
    expect(planOf(), expected, reason: 'a commit');
  }, skip: hasGit ? null : 'git is not available');

  test('f02/us04/fr06/e04: a commit of an unrelated file after the dry run '
      'leaves the plan valid; a committed edit to a listed file is '
      'plan_mismatch and removes nothing', () async {
    final root = await writeWriteProject(extra: approvedSignOut);
    expect(git(root, ['init', '-q']).exitCode, 0);
    commitAll(root, 'first');
    String planOf() =>
        writeIn(
              root,
              (s) => answerDeleteDryRun(s, ['user_story:login/sign_out']),
            ).json['plan']!
            as String;
    final hash = planOf();

    File('${root.path}/unrelated.txt').writeAsStringSync('x\n');
    commitAll(root, 'unrelated');
    final edited = signOutUnit[1];
    docFile(root, edited).writeAsStringSync('${readDoc(root, edited)}More.\n');
    commitAll(root, 'edit a listed file');
    expect(
      () => del(
        root,
        ['user_story:login/sign_out'],
        confirmation: OwnerConfirmation.given,
        planHash: hash,
      ),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.planMismatch)
            .having((f) => f.exitStatus, 'exitStatus', 75),
      ),
    );
    for (final path in signOutUnit) {
      expect(hasDoc(root, path), isTrue, reason: path);
    }
  }, skip: hasGit ? null : 'git is not available');

  test('f02/us04/fr06/e04: a dry run, then a commit of an unrelated file, '
      'then --yes --plan removes the unit', () async {
    final root = await writeWriteProject(extra: approvedSignOut);
    expect(git(root, ['init', '-q']).exitCode, 0);
    commitAll(root, 'first');
    final hash =
        writeIn(
              root,
              (s) => answerDeleteDryRun(s, ['user_story:login/sign_out']),
            ).json['plan']!
            as String;
    File('${root.path}/unrelated.txt').writeAsStringSync('x\n');
    commitAll(root, 'unrelated');

    final answer = del(
      root,
      ['user_story:login/sign_out'],
      confirmation: OwnerConfirmation.given,
      planHash: hash,
    );
    expect(answer.json['removed'], signOutUnit);
    expect(hasDoc(root, story2), isFalse);
  }, skip: hasGit ? null : 'git is not available');

  test('ms-r11: an uncommitted edit to a listed file after the dry run is '
      'plan_mismatch, exit 75, and nothing is removed', () async {
    final root = await writeWriteProject(extra: approvedSignOut);
    final hash =
        writeIn(
              root,
              (s) => answerDeleteDryRun(s, ['user_story:login/sign_out']),
            ).json['plan']!
            as String;
    final edited = signOutUnit[1];
    docFile(root, edited).writeAsStringSync('${readDoc(root, edited)}More.\n');

    expect(
      () => del(
        root,
        ['user_story:login/sign_out'],
        confirmation: OwnerConfirmation.given,
        planHash: hash,
      ),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.planMismatch)
            .having((f) => f.exitStatus, 'exitStatus', 75),
      ),
    );
    for (final path in signOutUnit) {
      expect(hasDoc(root, path), isTrue, reason: path);
    }
  });

  String signOutPlan(Directory root) =>
      writeIn(
            root,
            (s) => answerDeleteDryRun(s, ['user_story:login/sign_out']),
          ).json['plan']!
          as String;

  void expectSignOutRefused(
    Directory root,
    String hash,
    Iterable<String> kept,
  ) {
    expect(
      () => del(
        root,
        ['user_story:login/sign_out'],
        confirmation: OwnerConfirmation.given,
        planHash: hash,
      ),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.planMismatch)
            .having((f) => f.exitStatus, 'exitStatus', 75),
      ),
    );
    for (final path in kept) {
      expect(hasDoc(root, path), isTrue, reason: path);
    }
  }

  test('f02/us04/fr06/e04: a file added to the unit after the dry run is '
      'plan_mismatch and nothing is removed', () async {
    final root = await writeWriteProject(extra: approvedSignOut);
    final hash = signOutPlan(root);
    const added = 'prds/features/f01_login/us02_sign_out/notes.txt';
    docFile(root, added).writeAsStringSync('late\n');

    expectSignOutRefused(root, hash, [...signOutUnit, added]);
  });

  test('f02/us04/fr06/e04: a file removed from the unit after the dry run is '
      'plan_mismatch and nothing is removed', () async {
    final root = await writeWriteProject(extra: approvedSignOut);
    final hash = signOutPlan(root);
    docFile(root, signOutUnit.last).deleteSync();

    expectSignOutRefused(root, hash, signOutUnit.take(2));
  });

  test('f02/us04/fr06/e04: a listed file that is not UTF-8 and changes after '
      'the dry run is plan_mismatch and nothing is removed', () async {
    final root = await writeWriteProject(extra: approvedSignOut);
    const blob = 'prds/features/f01_login/us02_sign_out/blob.bin';
    docFile(root, blob).writeAsBytesSync([0xFF, 0xFE, 0xFD]);
    final hash = signOutPlan(root);
    // Same length and the same count of invalid bytes as before.
    docFile(root, blob).writeAsBytesSync([0xFE, 0xFF, 0xFC]);

    expectSignOutRefused(root, hash, [...signOutUnit, blob]);
  });

  test('ms-r11: a dry run refuses a referred unit as the run does', () async {
    final root = await writeWriteProject();
    expect(
      () => writeIn(
        root,
        (s) => answerDeleteDryRun(s, ['user_story:login/reset_password']),
      ),
      refusesWith(WriteFaultCode.docReferenced),
    );
  });

  test("ms-r11: --yes with the dry run's plan hash deletes an approved unit "
      "with no prompt, as the Owner's y does", () async {
    final root = await writeWriteProject(extra: approvedSignOut);
    final hash =
        writeIn(
              root,
              (s) => answerDeleteDryRun(s, ['user_story:login/sign_out']),
            ).json['plan']!
            as String;
    final prompts = StringBuffer();
    final answer = del(
      root,
      ['user_story:login/sign_out'],
      confirmation: OwnerConfirmation.given,
      prompts: prompts,
      planHash: hash,
    );
    expect(prompts.toString(), isEmpty);
    expect(answer.json['removed'], signOutUnit);
    expect(hasDoc(root, story2), isFalse);
  });

  for (final (label, planHash) in [
    ('a unit changed since the dry run', '000000000000'),
    ('no plan hash', null),
  ]) {
    test('ms-r11: --yes with $label is plan_mismatch, exit 75, and nothing '
        'is removed', () async {
      final root = await writeWriteProject(extra: approvedSignOut);
      expect(
        () => del(
          root,
          ['user_story:login/sign_out'],
          confirmation: OwnerConfirmation.given,
          planHash: planHash,
        ),
        throwsA(
          isA<WriteFault>()
              .having((f) => f.code, 'code', WriteFaultCode.planMismatch)
              .having((f) => f.exitStatus, 'exitStatus', 75)
              .having(
                (f) => f.message,
                'message',
                'the delete list is not the one the Owner saw in the dry run; '
                    'run specstone delete --dry-run again, show it, and ask '
                    'for a new ok',
              ),
        ),
      );
      for (final path in signOutUnit) {
        expect(hasDoc(root, path), isTrue, reason: path);
      }
    });
  }

  test('f02/us04/fr01/e02: an FR goes alone', () async {
    final root = await writeWriteProject();
    expect(
      del(root, ['fr:login/reset_password/expire_reset_link']).json['removed'],
      [fr32],
    );
    expect([hasDoc(root, fr31), hasDoc(root, story3)], [true, true]);
  });

  test('f01/us04/fr01/e09, f02/us04/fr01/e02: an FR named by its DocPath goes alone', () async {
    final root = await writeWriteProject();
    expect(del(root, [fr32]).json['removed'], [fr32]);
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
            confirmation: OwnerConfirmation.missing,
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

  test('document_writing/delete_doc_subtree/gate_approved_delete E05: a doc carrying draft beside a hash is guarded', () async {
    final root = await writeWriteProject(
      extra: {
        'docs/$fr32': '---\ndraft: true\napproved: "0123456789ab"\ntraced_from: US-03\nverify_method: test\n---\n\n# Expire reset link\n',
      },
    );
    expect(
      () => del(root, ['fr:login/reset_password/expire_reset_link']),
      refusesWith(WriteFaultCode.ownerTerminalRequired),
    );
    expect(hasDoc(root, fr32), isTrue);
  });

  test('document_writing/delete_doc_subtree/gate_approved_delete E04: a doc with no frontmatter at all is guarded', () async {
    final root = await writeWriteProject(
      extra: {'docs/$fr32': '# Expire reset link\n'},
    );
    expect(
      () => del(root, ['fr:login/reset_password/expire_reset_link']),
      refusesWith(WriteFaultCode.ownerTerminalRequired),
    );
    expect(hasDoc(root, fr32), isTrue);
  });

  test('document_writing/delete_doc_subtree/gate_approved_delete E08: an untyped .md file with a hash beside draft is guarded', () async {
    final root = await writeWriteProject(
      extra: {
        ...withoutLink,
        'docs/prds/features/f01_login/us03_reset_password/notes.md':
            '---\ndraft: true\napproved: "0123456789ab"\n---\n\n# Notes\n',
      },
    );
    expect(
      () => del(root, ['user_story:login/reset_password']),
      refusesWith(WriteFaultCode.ownerTerminalRequired),
    );
    expect(hasDoc(root, story3), isTrue);
  });

  test('document_writing/delete_doc_subtree/gate_approved_delete E04: a doc whose whole frontmatter is invalid YAML is guarded', () async {
    final root = await writeWriteProject(
      extra: {'docs/$fr32': '---\ndraft: true\n: [unclosed\n---\n\n# Expire\n'},
    );
    expect(
      () => del(root, ['fr:login/reset_password/expire_reset_link']),
      refusesWith(WriteFaultCode.ownerTerminalRequired),
    );
    expect(hasDoc(root, fr32), isTrue);
  });

  test('document_writing/edit_one_section_or_field/serialize_writes E04: the delete prompt holds no write lock', () async {
    final root = await writeWriteProject(extra: approvedSignOut);
    writeIn(root, (_) {}); // creates the index
    var otherWriteLanded = false;
    final answer = writeIn(
      root,
      (s) => answerDelete(
        s,
        ['user_story:login/sign_out'],
        confirmation: OwnerConfirmation.prompt,
        readLine: () {
          writeIn(
            root,
            (other) => other.locked(() => otherWriteLanded = true),
            busyTimeout: const Duration(milliseconds: 200),
          );
          return 'y';
        },
        prompts: StringBuffer(),
      ),
    );
    expect(otherWriteLanded, isTrue);
    expect(answer.json['removed'], hasLength(3));
  });

  test(
    'a guarded delete with no home folder refuses before its prompt',
    () async {
      final root = await writeWriteProject(extra: approvedSignOut);
      getDoc(root, 'user_story:login/sign_out');
      final before = treeBytes(root);
      final prompts = StringBuffer();

      expect(
        () => writeInNoHome(
          root,
          (s) => answerDelete(
            s,
            ['user_story:login/sign_out'],
            confirmation: OwnerConfirmation.prompt,
            readLine: () => 'y',
            prompts: prompts,
          ),
        ),
        throwsA(
          isA<RenderFault>()
              .having((f) => f.exitStatus, 'exit', 73)
              .having((f) => f.file, 'file', MoveJournal.journalPath),
        ),
      );

      expect(prompts.toString(), isEmpty);
      expect(treeBytes(root), before);
    },
  );

  test('a guarded delete with a relative home folder refuses before its '
      'prompt', () async {
    final root = await writeWriteProject(extra: approvedSignOut);
    getDoc(root, 'user_story:login/sign_out');
    final before = treeBytes(root);
    final prompts = StringBuffer();

    expect(
      () => WriteSession.run(
        (s) => answerDelete(
          s,
          ['user_story:login/sign_out'],
          confirmation: OwnerConfirmation.prompt,
          readLine: () => 'y',
          prompts: prompts,
        ),
        templates: TemplateResolver(),
        workingDirectory: root,
        homeDirectory: Directory('relative_home'),
      ),
      throwsA(
        isA<RenderFault>()
            .having((f) => f.exitStatus, 'exit', 73)
            .having((f) => f.file, 'file', MoveJournal.journalPath),
      ),
    );

    expect(prompts.toString(), isEmpty);
    expect(treeBytes(root), before);
  });

  test('f02/us04/fr02/e06: the Owner deleting a never-approved unit sees no prompt', () async {
    final root = await writeWriteProject(extra: withoutLink);
    final prompts = StringBuffer();
    expect(
      del(
        root,
        ['user_story:login/reset_password'],
        confirmation: OwnerConfirmation.prompt,
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
        confirmation: OwnerConfirmation.prompt,
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
    final answer = del(root, [
      'user_story:login/sign_out',
    ], confirmation: OwnerConfirmation.prompt);
    expect(answer.text, isEmpty);
    expect(answer.json, {'removed': <String>[], 'mentions': <Object>[]});
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
          confirmation: OwnerConfirmation.prompt,
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
          confirmation: OwnerConfirmation.prompt,
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
        confirmation: OwnerConfirmation.prompt,
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
          'mentions': <Object>[],
        });
        expect(hasDoc(root, scratch), isFalse);
        expect(hasDoc(root, loginArch), isTrue);
      },
    );

    test('f01/us04/fr01/e10, f02/us04/fr04/e01: docs/ and an untyped DocPath deletes that one file only', () async {
      final root = await writeWriteProject(extra: untyped);
      expect(del(root, ['docs/$scratch']).json, {
        'removed': [scratch],
        'mentions': <Object>[],
      });
      expect(hasDoc(root, scratch), isFalse);
      expect(hasDoc(root, loginArch), isTrue);
    });

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
        confirmation: OwnerConfirmation.prompt,
        answers: ['y'],
        prompts: prompts,
      );
      expect(prompts.toString(), endsWith('delete 3 files? [y/N] '));
      expect(answer.json, {
        'removed': [errors, notes, index]..sort(),
        'mentions': <Object>[],
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
              'the delete set holds guarded docs; only the Owner deletes '
                  'them, at an interactive terminal, or with --yes after the '
                  "Owner's ok in the chat",
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
        () => del(
          root,
          [notes, errors],
          confirmation: OwnerConfirmation.prompt,
          answers: ['y'],
        ),
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

    const plan = 'superpowers/plans/2026-11-01-retire.md';
    const planText =
        '# Retire\n\nSee [notes](../../specs/f01_login/api_notes.md), '
        '[errors](../../specs/f01_login/api_errors.md), and '
        '[scratch](../../specs/f01_login/scratch.md).\n';
    final withPlan = {...untyped, 'docs/$plan': planText};

    test('f02/us04/fr04/e08: a link from an untyped file outside the checked folders does not block; the delete warns it will dangle', () async {
      final root = await writeWriteProject(extra: withPlan);

      final answer = del(root, [scratch]);

      expect(answer.json, {
        'removed': [scratch],
        'mentions': <Object>[],
      });
      expect(answer.warnings, [
        '$plan links into $scratch; the link will dangle',
      ]);
      expect(hasDoc(root, scratch), isFalse);
      expect(readDoc(root, plan), planText);
    });

    test('f02/us04/fr04/e08, ms-r11: a dry run warns of the link that will dangle, as the run does', () async {
      final root = await writeWriteProject(extra: withPlan);

      final answer = writeIn(root, (s) => answerDeleteDryRun(s, [scratch]));

      expect(answer.json['files'], [scratch]);
      expect(answer.warnings, [
        '$plan links into $scratch; the link will dangle',
      ]);
      expect(hasDoc(root, scratch), isTrue);
    });

    test('f02/us04/fr04/e08, f02/us04/fr04/e02: after the Owner answers y, the delete warns of the link that will dangle', () async {
      final root = await writeWriteProject(extra: withPlan);

      final answer = del(
        root,
        [notes],
        confirmation: OwnerConfirmation.prompt,
        answers: ['y'],
      );

      expect(answer.json, {
        'removed': [notes],
        'mentions': <Object>[],
      });
      expect(answer.warnings, [
        '$plan links into $notes; the link will dangle',
      ]);
    });

    test('f02/us04/fr04/e04, f02/us04/fr04/e08: an old untyped file under specs/ that links in is doc_referenced; the plan beside it is not listed', () async {
      final root = await writeWriteProject(extra: withPlan);

      expect(
        () => del(root, [errors]),
        throwsA(
          isA<WriteFault>()
              .having((f) => f.code, 'code', WriteFaultCode.docReferenced)
              .having((f) => f.relatedFiles, 'relatedFiles', [notes]),
        ),
      );
      expect(hasDoc(root, errors), isTrue);
    });

    test('f02/us04/fr04/e04, f02/us04/fr04/e08: a typed doc outside the checked folders that links in is doc_referenced', () async {
      const memo = 'retire_memo.md';
      final root = await writeWriteProject(
        extra: {
          ...untyped,
          '.specstone/templates/memo.yaml':
              'id: memo\ndescription: A memo\npath: "{slug}_memo.md"\n',
          'docs/$memo':
              '# Retire\n\nSee [scratch](specs/f01_login/scratch.md).\n',
        },
      );

      expect(
        () => del(root, [scratch]),
        throwsA(
          isA<WriteFault>()
              .having((f) => f.code, 'code', WriteFaultCode.docReferenced)
              .having((f) => f.relatedFiles, 'relatedFiles', [memo]),
        ),
      );
      expect(hasDoc(root, scratch), isTrue);
    });

    test('f02/us04/fr04/e08: a link from one file of the set to another neither blocks nor warns', () async {
      final root = await writeWriteProject(extra: withPlan);

      final answer = del(
        root,
        [scratch, plan],
        confirmation: OwnerConfirmation.prompt,
        answers: ['y'],
      );

      expect(answer.json, {
        'removed': [scratch, plan]..sort(),
        'mentions': <Object>[],
      });
      expect(answer.warnings, isEmpty);
    });

    test('f02/us04/fr04/e05: a target inside the unit of another counts each file once', () async {
      final root = await writeWriteProject(extra: withoutLink);
      final answer = del(root, [
        'user_story:login/reset_password',
        'fr:login/reset_password/expire_reset_link',
      ]);
      expect(answer.json, {
        'removed': [story3, fr31, fr32],
        'mentions': <Object>[],
      });
    });

    test(
      'f02/us04/fr04/e05: the same target twice removes its file once',
      () async {
        final root = await writeWriteProject(extra: untyped);
        final answer = del(root, [scratch, scratch]);
        expect(answer.json, {
          'removed': [scratch],
          'mentions': <Object>[],
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

    test('f02/us04/fr01/e10: a bare name 2 docs carry among several targets is argument_invalid', () async {
      final root = await writeWriteProject(extra: untyped);
      expect(
        () => del(root, [scratch, 'login']),
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

  group('mentions of the unit', () {
    const project = 'prds/PROJECT.md';
    const mentionWarning =
        '$project mentions $loginFeature; the mention will dangle';

    /// A project where nothing but [files] points into the login feature.
    Future<Directory> mentioning(
      Map<String, String> files,
    ) => writeWriteProject(
      extra: {
        'docs/prds/FEATURES.md': '# Feature index\n\n## Systems\n- [Signup](features/f02_signup/FEATURE.md)\n',
        'docs/$persona':
            '---\ndraft: true\n---\n\n# Buyer\n\n## Profile\nBuys things.\n',
        for (final MapEntry(:key, :value) in files.entries) 'docs/$key': value,
      },
    );

    ReadAnswer delLogin(Directory root) => del(
      root,
      ['feature:login'],
      confirmation: OwnerConfirmation.prompt,
      answers: ['y'],
    );

    test('f02/us04/fr01/e13: a typed doc outside the unit that mentions a doc of it makes the delete warn; the delete goes on', () async {
      final root = await mentioning({
        project: '# Project context\n\nSee `features/f01_login/FEATURE.md`.\n',
      });

      final answer = delLogin(root);

      expect(answer.json['removed'], contains(loginFeature));
      expect(answer.warnings, [mentionWarning]);
      expect(hasDoc(root, loginFeature), isFalse);
      expect(hasDoc(root, project), isTrue);
    });

    test('f02/us04/fr01/e13, ms-r11: a dry run warns of the mention, as the run does', () async {
      final root = await mentioning({
        project: '# Project context\n\nSee `features/f01_login/FEATURE.md`.\n',
      });

      final answer = writeIn(
        root,
        (s) => answerDeleteDryRun(s, ['feature:login']),
      );

      expect(answer.warnings, [mentionWarning]);
      expect(hasDoc(root, loginFeature), isTrue);
    });

    test('f02/us04/fr01/e13: two mentions on two lines of one doc give one warning', () async {
      final root = await mentioning({
        project:
            '# Project context\n\nSee `features/f01_login/FEATURE.md`.\n\n'
            'Again `features/f01_login/FEATURE.md`.\n',
      });

      expect(delLogin(root).warnings, [mentionWarning]);
    });

    test(
      'f02/us04/fr01/e13: a mention from inside the unit gives no warning',
      () async {
        final root = await mentioning({
          'prds/features/f01_login/us01_email_login/USER_STORY.md':
              writeProject['docs/$story1']!.replaceFirst(
                'Sign in with an email.',
                'Sign in with an email, see `features/f01_login/FEATURE.md`.',
              ),
        });

        expect(delLogin(root).warnings, isEmpty);
      },
    );

    test(
      'f02/us04/fr01/e13: a mention from an untyped doc gives no warning',
      () async {
        final root = await mentioning({
          'prds/d02_notes.md':
              '# Notes\n\nSee `features/f01_login/FEATURE.md`.\n',
        });

        expect(delLogin(root).warnings, isEmpty);
      },
    );

    test('f02/us04/fr01/e13: the link warning comes first, then the mentions in tree order of the mentioned docs, then of the mentioning docs', () async {
      const plan = 'superpowers/plans/2026-11-01-retire.md';
      const gnfr = 'prds/GNFR.md';
      final root = await mentioning({
        plan: '# Retire\n\nSee [story](../../prds/features/f01_login/us01_email_login/USER_STORY.md).\n',
        project:
            '# Project context\n\n`features/f01_login/FEATURE.md` and '
            '`features/f01_login/us01_email_login/USER_STORY.md`.\n',
        gnfr: '# Global non-functional requirements\n\n`features/f01_login/us01_email_login/USER_STORY.md`.\n',
      });

      expect(delLogin(root).warnings, [
        '$plan links into $story1; the link will dangle',
        '$project mentions $loginFeature; the mention will dangle',
        '$gnfr mentions $story1; the mention will dangle',
        '$project mentions $story1; the mention will dangle',
      ]);
    });

    test('f02/us04/fr01/e13: a doc that links into the unit still refuses, with no mention warning', () async {
      final root = await mentioning({
        project:
            '# Project context\n\n[login](features/f01_login/FEATURE.md)\n'
            'and `features/f01_login/FEATURE.md`.\n',
      });

      expect(
        () => delLogin(root),
        throwsA(
          isA<WriteFault>().having(
            (f) => f.code,
            'code',
            WriteFaultCode.docReferenced,
          ),
        ),
      );
    });

    test(
      'document_writing/delete_doc_subtree/delete_doc_subtree E13: a doc-name '
      'mention of the feature warns as a path mention does, the delete '
      'going on',
      () async {
        final root = await mentioning({
          project: '# Project context\n\nSee `feature:login`.\n',
        });

        final answer = delLogin(root);

        expect(answer.json['removed'], contains(loginFeature));
        expect(answer.warnings, [mentionWarning]);
        expect(hasDoc(root, project), isTrue);
      },
    );

    test('document_writing/delete_doc_subtree/delete_doc_subtree E13: a bare '
        'name and a typed name of one doc on two lines give one warning, and '
        'a dry run warns the same', () async {
      final root = await mentioning({
        project:
            '# Project context\n\nSee `login/reset_password`.\n\n'
            'And `user_story:login/reset_password`.\n',
      });

      final answer = writeIn(
        root,
        (s) => answerDeleteDryRun(s, ['feature:login']),
      );

      expect(answer.warnings, [
        '$project mentions $story3; the mention will dangle',
      ]);
      expect(hasDoc(root, story3), isTrue);
    });

    test('document_writing/delete_doc_subtree/delete_doc_subtree E13: a '
        'doc-name mention from an untyped doc gives no warning', () async {
      final root = await mentioning({
        'prds/d02_notes.md': '# Notes\n\nSee `feature:login`.\n',
      });

      expect(delLogin(root).warnings, isEmpty);
    });
  });

  test('document_writing/delete_doc_subtree/delete_doc_subtree E06: delete of a story an FR of another feature traces is doc_referenced listing that FR', () async {
    const tracer =
        'prds/features/f02_signup/us01_create_account/fr09_trace_reset.md';
    final root = await writeWriteProject(
      extra: {
        ...withoutLink,
        ...freeStory3,
        'docs/prds/features/f02_signup/us01_create_account/USER_STORY.md': '---\ndraft: true\n---\n\n# Create account\n\n## Use Case\nCreate an account.\n',
        'docs/$tracer': '---\ndraft: true\ntraced_from:\n  - login/reset_password#S1\n---\n\n# Trace reset\n\n## Statement\nThe system shall trace.\n',
      },
    );
    expect(
      () => del(root, ['user_story:login/reset_password']),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.docReferenced)
            .having((f) => f.file, 'file', story3)
            .having((f) => f.relatedFiles, 'relatedFiles', [tracer]),
      ),
    );
    expect(hasDoc(root, story3), isTrue);
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

  test('f02/us04/fr01/e14: deleting a sub-feature takes its folder and its spec folder, and the top feature stays', () async {
    final root = await writeNestedProject(
      extra: {'docs/$shopApi': '# Shop API\n'},
    );
    final answer = del(
      root,
      ['feature:shop/cart'],
      confirmation: OwnerConfirmation.prompt,
      answers: ['y'],
    );
    expect(
      answer.json['removed'],
      containsAll([cartFeature, cartAdd, cartAddFr, cartDrop, cartDomain]),
    );
    for (final folder in [
      'prds/features/f02_shop/f01_cart',
      'specs/f02_shop/f01_cart',
    ]) {
      expect(Directory('${root.path}/docs/$folder').existsSync(), isFalse);
    }
    expect(hasDoc(root, shopFeature), isTrue);
    expect(hasDoc(root, payCard), isTrue);
    expect(hasDoc(root, shopDomain), isTrue);
  });

  test('f02/us04/fr01/e06, f02/us04/fr01/e14: a doc outside that links into a sub-feature is doc_referenced, and nothing is removed', () async {
    final root = await writeNestedProject();
    expect(
      () => del(root, ['feature:shop/cart']),
      throwsA(
        isA<WriteFault>().having(
          (f) => f.code,
          'code',
          WriteFaultCode.docReferenced,
        ),
      ),
    );
    expect(
      Directory('${root.path}/docs/prds/features/f02_shop/f01_cart')
          .existsSync(),
      isTrue,
    );
    expect(hasDoc(root, cartDomain), isTrue);
  });

  group('record entries', () {
    final removedStory3 = [story3, fr31, fr32];

    test('document_writing/delete_doc_subtree/delete_doc_subtree E16, E17: a story delete drops the entries of the story and of its FRs from the record, marks it draft, and lists only the removed files', () async {
      final root = await writeWriteProject(extra: _withRecords());
      final signupBefore = readDoc(root, _signupRecord);
      final answer = del(root, ['user_story:login/reset_password']);
      expect(answer.json, {'removed': removedStory3, 'mentions': <Object>[]});
      expect(answer.text, '${removedStory3.join('\n')}\n');
      expect(
        readDoc(root, _loginRecord),
        '---\n'
        'draft: true\n'
        'approved: true\n'
        'statuses:\n'
        "  - 'email_login:implemented'\n"
        'implements:\n'
        "  - 'email_login:app/lib/login.dart:SignIn'\n"
        '---\n\n# Record\n',
      );
      expect(readDoc(root, _signupRecord), signupBefore);
    });

    test('document_writing/delete_doc_subtree/delete_doc_subtree E16: an FR delete drops the entry of that FR alone', () async {
      final root = await writeWriteProject(extra: _withRecords());
      del(root, ['fr:login/reset_password/expire_reset_link']);
      final record = readDoc(root, _loginRecord);
      expect(record, isNot(contains('expire_reset_link')));
      for (final kept in [
        'email_login:implemented',
        'reset_password:implemented',
        'reset_password/send_reset_link:planned',
        'reset_password:app/lib/reset.dart:ResetPage',
      ]) {
        expect(record, contains("'$kept'"));
      }
      expect(record, contains('draft: true'));
    });

    test('document_writing/delete_doc_subtree/delete_doc_subtree E16: a record left with no entry stays', () async {
      final root = await writeWriteProject(
        extra: _withRecords(
          login: recordText(
            statuses: ['reset_password:implemented'],
            code: ['reset_password:app/lib/reset.dart:ResetPage'],
          ),
        ),
      );
      del(root, ['user_story:login/reset_password']);
      expect(
        readDoc(root, _loginRecord),
        '---\ndraft: true\n---\n\n# Record\n',
      );
    });

    test('document_writing/delete_doc_subtree/delete_doc_subtree E16: a record that holds no entry of the unit is not written', () async {
      final root = await writeWriteProject(
        extra: _withRecords(
          login: recordText(statuses: ['email_login:planned']),
        ),
      );
      final before = readDoc(root, _loginRecord);
      del(root, ['user_story:login/reset_password']);
      expect(readDoc(root, _loginRecord), before);
    });

    test('document_writing/delete_doc_subtree/delete_doc_subtree E16: a nested feature record names its items relative to it, and a record of another feature is left', () async {
      final root = await writeNestedProject(
        extra: {
          '.specstone/templates/implementation.yaml': recordLayer,
          'docs/$_cartRecord': recordText(
            statuses: [
              'add_item:implemented',
              'add_item/check_stock:implemented',
              'drop_item:planned',
            ],
          ),
          'docs/specs/f02_shop/IMPLEMENTATION.md': recordText(
            statuses: ['drop_item:planned'],
          ),
        },
      );
      del(
        root,
        ['user_story:shop/cart/drop_item'],
        confirmation: OwnerConfirmation.prompt,
        answers: ['y'],
      );
      expect(
        readDoc(root, _cartRecord),
        contains("'add_item/check_stock:implemented'"),
      );
      expect(readDoc(root, _cartRecord), isNot(contains('drop_item')));
      expect(
        readDoc(root, 'specs/f02_shop/IMPLEMENTATION.md'),
        contains("'drop_item:planned'"),
      );
    });

    test('document_writing/delete_doc_subtree/delete_doc_subtree E16: a read-only record refuses output_not_writable in the dry run as in the run, and nothing is removed', () async {
      final root = await writeWriteProject(extra: _withRecords());
      final record = docFile(root, _loginRecord);
      expect(Process.runSync('chmod', ['444', record.path]).exitCode, 0);
      addTearDown(() => Process.runSync('chmod', ['644', record.path]));
      Matcher refusesRecord() => throwsA(
        isA<RenderFault>().having(
          (f) => f.message,
          'message',
          contains(_loginRecord),
        ),
      );
      expect(
        () => writeIn(
          root,
          (s) => answerDeleteDryRun(s, ['user_story:login/reset_password']),
        ),
        refusesRecord(),
      );
      expect(
        () => del(root, ['user_story:login/reset_password']),
        refusesRecord(),
      );
      expect(hasDoc(root, story3), isTrue);
    }, skip: unreadablePathSkipReason() ?? false);

    test('document_writing/delete_doc_subtree/delete_doc_subtree E16: a record whose implements block is not valid YAML refuses in the dry run as in the run, and nothing is removed', () async {
      const broken =
          "---\nstatuses:\n  - 'reset_password:implemented'\n"
          "implements:\n  - 'reset_password:app/lib/reset.dart\n"
          '---\n\n# Record\n';
      final root = await writeWriteProject(extra: _withRecords(login: broken));
      final refusesRecord = throwsA(
        isA<RenderFault>()
            .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
            .having(
              (f) => f.message,
              'message',
              'cannot write $_loginRecord: its implements block is not valid '
                  'YAML',
            ),
      );
      expect(
        () => writeIn(
          root,
          (s) => answerDeleteDryRun(s, ['user_story:login/reset_password']),
        ),
        refusesRecord,
      );
      expect(
        () => del(root, ['user_story:login/reset_password']),
        refusesRecord,
      );
      expect(hasDoc(root, story3), isTrue);
      expect(readDoc(root, _loginRecord), broken);
    });

    test('document_writing/delete_doc_subtree/delete_doc_subtree E16: a record with CRLF line ends and a byte-order mark keeps both', () async {
      final record = recordText(
        statuses: ['email_login:implemented', 'reset_password:implemented'],
      ).replaceAll('\n', '\r\n');
      final root = await writeWriteProject(
        extra: _withRecords(login: '\uFEFF$record'),
      );
      del(root, ['user_story:login/reset_password']);
      final bytes = docFile(root, _loginRecord).readAsBytesSync();
      expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
      final text = utf8.decode(bytes);
      expect(text, isNot(contains('reset_password')));
      expect(text, contains('draft: true'));
      expect(text.replaceAll('\r\n', ''), isNot(contains('\n')));
    });

    test('document_writing/delete_doc_subtree/delete_doc_subtree E17: a feature delete removes no entry, its record leaving with the spec folder', () async {
      final root = await writeNestedProject(
        extra: {
          '.specstone/templates/implementation.yaml': recordLayer,
          'docs/$_cartRecord': recordText(statuses: ['add_item:implemented']),
          // no doc links into the sub-feature once the API doc is freed
          'docs/$shopApi': '# Shop API\n',
          'docs/$cartDomain': recordText(),
        },
      );
      final answer = writeIn(
        root,
        (s) => answerDeleteDryRun(s, ['feature:shop/cart']),
      );
      expect(answer.json['records'], isEmpty);
      expect(answer.json['files'], contains(_cartRecord));
      expect(answer.text, isNot(contains('rewrites')));
    });

    test('document_writing/delete_doc_subtree/delete_doc_subtree E17: an interrupted delete finishes the record rewrite with its file moves', () async {
      final root = await writeWriteProject(extra: _withRecords());
      final before = readDoc(root, _loginRecord);
      expect(
        () => IOOverrides.runWithIOOverrides(
          () => del(root, ['user_story:login/reset_password']),
          FailingRenameHook('docs/$fr31'),
        ),
        throwsA(isA<RenderFault>()),
      );
      expect(
        File('${root.path}/${MoveJournal.journalPath}').existsSync(),
        isTrue,
      );
      expect(readDoc(root, _loginRecord), before);
      writeIn(root, (s) => s.index.docs.length);
      expect(readDoc(root, _loginRecord), isNot(contains('reset_password')));
      expect(readDoc(root, _loginRecord), contains('draft: true'));
      expect(Directory('${root.path}/.specstone/trash').existsSync(), isFalse);
      expect(
        File('${root.path}/${MoveJournal.journalPath}').existsSync(),
        isFalse,
      );
    });

    const recordEntries =
        'rewrites $_loginRecord: reset_password, '
        'reset_password/send_reset_link, reset_password/expire_reset_link';

    test('document_writing/delete_doc_subtree/delete_after_the_owners_ok_in_the_chat E11: a dry run lists each record it rewrites after the files, and its plan hash covers the text of the record', () async {
      final root = await writeWriteProject(extra: _withRecords());
      final answer = writeIn(
        root,
        (s) => answerDeleteDryRun(s, ['user_story:login/reset_password']),
      );
      final hashed = [
        for (final path in removedStory3)
          '$path ${baseHashOf(toLf(readDoc(root, path)))}\n',
        '$_loginRecord ${baseHashOf(toLf(readDoc(root, _loginRecord)))}\n',
      ].join();
      final hash = baseHashOf(hashed);
      expect(
        answer.text,
        '${removedStory3.join('\n')}\n$recordEntries\n'
        'plan $hash\ndry run: nothing removed\n',
      );
      expect(answer.json, {
        'files': removedStory3,
        'records': [
          {
            'path': _loginRecord,
            'entries': [
              'reset_password',
              'reset_password/send_reset_link',
              'reset_password/expire_reset_link',
            ],
          },
        ],
        'mentions': <Object>[],
        'plan': hash,
      });
      expect(readDoc(root, _loginRecord), _loginRecordText);
      expect(hasDoc(root, story3), isTrue);
    });

    test('document_writing/delete_doc_subtree/delete_after_the_owners_ok_in_the_chat E11: --yes --plan deletes and rewrites the record while it is as the dry run saw it, and refuses plan_mismatch once it is edited', () async {
      final root = await writeWriteProject(extra: _withRecords());
      String planOf() =>
          writeIn(
                root,
                (s) =>
                    answerDeleteDryRun(s, ['user_story:login/reset_password']),
              ).json['plan']!
              as String;
      final hash = planOf();
      final record = docFile(root, _loginRecord)
        ..writeAsStringSync(
          _loginRecordText.replaceFirst('# Record', '# Record\n\nEdited.'),
        );
      final edited = readDoc(root, _loginRecord);
      expect(
        () => del(
          root,
          ['user_story:login/reset_password'],
          confirmation: OwnerConfirmation.given,
          planHash: hash,
        ),
        refusesWith(WriteFaultCode.planMismatch),
      );
      expect(hasDoc(root, story3), isTrue);
      expect(readDoc(root, _loginRecord), edited);

      record.writeAsStringSync(_loginRecordText);
      final answer = del(
        root,
        ['user_story:login/reset_password'],
        confirmation: OwnerConfirmation.given,
        planHash: hash,
      );
      expect(answer.json, {'removed': removedStory3, 'mentions': <Object>[]});
      expect(hasDoc(root, story3), isFalse);
      expect(readDoc(root, _loginRecord), isNot(contains('reset_password')));
    });

    test('document_writing/delete_doc_subtree/gate_approved_delete E10: the Owner prompt lists each record with its entries and counts the files of the unit alone; a record edited while it waits shows the list again, and nothing is written', () async {
      final root = await writeWriteProject(
        extra: {
          ...approvedSignOut,
          ..._withRecords(
            login: recordText(statuses: ['sign_out:implemented']),
          ),
        },
      );
      final prompts = StringBuffer();
      var asked = 0;
      final unchanged = readDoc(root, _loginRecord);
      final answer = writeIn(
        root,
        (s) => answerDelete(
          s,
          ['user_story:login/sign_out'],
          confirmation: OwnerConfirmation.prompt,
          readLine: () {
            asked++;
            if (asked == 1) {
              docFile(
                root,
                _loginRecord,
              ).writeAsStringSync('$unchanged\nMore.\n');
              return 'y';
            }
            return 'n';
          },
          prompts: prompts,
        ),
      );
      const list =
          '$story2\nprds/features/f01_login/us02_sign_out/fr01_end_session.md\n'
          'prds/features/f01_login/us02_sign_out/fr02_clear_cookies.md\n'
          'rewrites $_loginRecord: sign_out\ndelete 3 files? [y/N] ';
      expect(prompts.toString(), '$list$list');
      expect(answer.json['removed'], isEmpty);
      expect(hasDoc(root, story2), isTrue);
      expect(readDoc(root, _loginRecord), '$unchanged\nMore.\n');
    });
  });

  group('with two code targets', () {
    final twinStatuses = [
      'email_login:implemented',
      'email_login/check_password:implemented',
    ];
    const twinItems = ['email_login', 'email_login/check_password'];
    const flutterRecord = 'specs/flutter/f01_login/IMPLEMENTATION.md';
    const jasprRecord = 'specs/jaspr/f01_login/IMPLEMENTATION.md';

    Future<Directory> twins() => writeTwinProject(
      extra: {
        'docs/$flutterRecord': recordText(statuses: twinStatuses),
        'docs/$jasprRecord': recordText(statuses: twinStatuses),
        // the API doc names the story's FR in its trace; free it of the link
        'docs/${check.loginApi}': '# Login API\n',
      },
    );

    test('document_writing/delete_doc_subtree/delete_doc_subtree E15: a feature delete removes its folder and the spec folder of each target, each record among them', () async {
      final root = await twins();
      final answer = del(
        root,
        ['feature:login'],
        confirmation: OwnerConfirmation.prompt,
        answers: ['y'],
      );
      final removed = (answer.json['removed']! as List).cast<String>();
      expect(
        removed,
        containsAll([
          flutterArchitecture,
          jasprArchitecture,
          flutterRecord,
          jasprRecord,
        ]),
      );
      for (final folder in [
        'prds/features/f01_login',
        'specs/flutter/f01_login',
        'specs/jaspr/f01_login',
      ]) {
        expect(Directory('${root.path}/docs/$folder').existsSync(), isFalse);
      }
    });

    test('document_writing/delete_doc_subtree/delete_doc_subtree E16: a story delete drops its entries from the record of every target, and check reports no unresolved entry it made', () async {
      final root = await twins();
      del(
        root,
        ['user_story:login/email_login'],
        confirmation: OwnerConfirmation.prompt,
        answers: ['y'],
      );
      for (final path in [flutterRecord, jasprRecord]) {
        expect(
          readDoc(root, path),
          '---\ndraft: true\n---\n\n# Record\n',
          reason: path,
        );
      }
      final report = check.checkOf(root);
      expect([
        for (final f in report.findings)
          if (f.kind == FindingKind.recordEntryUnresolved) f.path,
      ], isEmpty);
    });

    test('document_writing/delete_doc_subtree/delete_doc_subtree: --target names one twin of a per-target doc, and the delete takes that file alone', () async {
      final root = await twins();
      expect(
        () =>
            writeIn(root, (s) => answerDeleteDryRun(s, ['architecture:login'])),
        throwsA(
          isA<IndexFault>().having(
            (f) => f.code,
            'code',
            IndexFaultCode.argumentInvalid,
          ),
        ),
      );
      final dry = writeIn(
        root,
        (s) =>
            answerDeleteDryRun(s, ['architecture:login'], codeTarget: 'jaspr'),
      );
      expect(dry.json['files'], [jasprArchitecture]);
      final answer = del(
        root,
        ['architecture:login'],
        confirmation: OwnerConfirmation.prompt,
        answers: ['y'],
        codeTarget: 'jaspr',
      );
      expect(answer.json['removed'], [jasprArchitecture]);
      expect(hasDoc(root, flutterArchitecture), isTrue);
    });

    test('document_writing/delete_doc_subtree/delete_doc_subtree: a code target keeps the names of one target, and a target the project lacks is argument_invalid', () async {
      final root = await twins();
      final answer = writeIn(
        root,
        (s) => answerDeleteDryRun(s, [
          'user_story:login/email_login',
        ], codeTarget: 'jaspr'),
      );
      expect(answer.json['files'], hasLength(3));
      expect(answer.json['records'], [
        {'path': flutterRecord, 'entries': twinItems},
        {'path': jasprRecord, 'entries': twinItems},
      ]);
      expect(
        () => writeIn(
          root,
          (s) => answerDeleteDryRun(s, [
            'user_story:login/email_login',
          ], codeTarget: 'dart'),
        ),
        throwsA(
          isA<IndexFault>().having(
            (f) => f.code,
            'code',
            IndexFaultCode.argumentInvalid,
          ),
        ),
      );
    });
  });
}
