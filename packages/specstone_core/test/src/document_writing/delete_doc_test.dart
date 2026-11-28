// The file contents are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/document_writing/delete_doc.dart';
import 'package:specstone_core/src/document_writing/move_doc.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/owner_confirmation.dart';
import 'package:specstone_core/src/document_writing/root_trust.dart';
import 'package:specstone_core/src/document_writing/set_doc.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/index_query/refs.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' as check show checkOf, loginApi;
import '../../helpers/failing_rename.dart';
import '../../helpers/git_repo.dart';
import '../../helpers/grouped_fixture.dart';
import '../../helpers/nested_fixture.dart';
import '../../helpers/no_generators.dart';
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

const _loginRecord = '.specstone/records/f01_login/IMPLEMENTATION.md';
const _signupRecord = '.specstone/records/f02_signup/IMPLEMENTATION.md';
const _cartRecord = '.specstone/records/f02_shop/f01_cart/IMPLEMENTATION.md';

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
  '.specstone/templates/implementation.yaml': recordLayerAtRoot,
  '.specstone/config.yaml': '${shippedPinsConfig()}code_root: app\n',
  _loginRecord: login ?? _loginRecordText,
  _signupRecord: recordText(statuses: ['ghost:planned']),
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
        generators: noGenerators,
      ),
    );
  }

  Matcher refusesWith(WriteFaultCode code) =>
      throwsA(isA<WriteFault>().having((f) => f.code, 'code', code));

  test('a delete under a docs root linked outside the project removes the emptied folder', () async {
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

  test(
    'a draft story goes with its requirements, siblings keep their numbers',
    () async {
      final root = await writeWriteProject(extra: withoutLink);
      final prompts = StringBuffer();
      final answer = del(root, [
        'user_story:login/reset_password',
      ], prompts: prompts);
      expect(answer.text, '$story3\n$fr31\n$fr32\n');
      expect(answer.json, {
        'removed': [story3, fr31, fr32],
        'rewritten': <Object>[],
        'deleted': <Object>[],
        'mentions': <Object>[],
      });
      expect(
        Directory(
          '${root.path}/docs/prds/features/f01_login/us03_reset_password',
        ).existsSync(),
        isFalse,
      );
      expect([hasDoc(root, story1), hasDoc(root, story2)], [true, true]);
      expect(Directory('${root.path}/.specstone/trash').existsSync(), isFalse);
      expect(prompts.toString(), isEmpty);
    },
  );

  test('a doc outside that links into the unit is doc_referenced, and nothing is removed', () async {
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

  test(
    'an Agent deleting an approved doc is owner_terminal_required',
    () async {
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
    },
  );

  test('the Owner sees the paths and the prompt; y removes, any other answer keeps', () async {
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

  test('a peer commit while the guarded prompt waits deletes the unit in one '
      'run, with no second prompt', () async {
    final root = await writeWriteProject(extra: approvedSignOut);
    final prompts = StringBuffer();
    var runs = 0;
    var answered = 0;
    final answer = writeIn(root, (s) {
      runs++;
      return answerDelete(
        s,
        ['user_story:login/sign_out'],
        confirmation: OwnerConfirmation.prompt,
        readLine: () {
          if (answered++ > 0) return null;
          final peer = IndexStore.open(s.project.projectRoot);
          try {
            peer.write(() => peer.deleteDoc(persona));
          } finally {
            peer.close();
          }
          return 'y';
        },
        prompts: prompts,
        generators: noGenerators,
      );
    });
    expect(runs, 1);
    expect(answered, 1);
    expect(
      'delete 3 files? [y/N] '.allMatches(prompts.toString()),
      hasLength(1),
    );
    expect(answer.json['removed'], hasLength(3));
    expect(hasDoc(root, story2), isFalse);
  });

  const signOutUnit = [
    story2,
    'prds/features/f01_login/us02_sign_out/fr01_end_session.md',
    'prds/features/f01_login/us02_sign_out/fr02_clear_cookies.md',
  ];

  test('a dry run lists every file the unit removes and its plan '
      'line, and removes nothing', () async {
    final root = await writeWriteProject(extra: approvedSignOut);
    final answer = writeIn(
      root,
      (s) => answerDeleteDryRun(s, [
        'user_story:login/sign_out',
      ], generators: noGenerators),
    );
    final hashed = signOutUnit
        .map((path) => '$path ${baseHashOf(toLf(readDoc(root, path)))}\n')
        .join();
    final hash = baseHashOf(hashed);
    expect(
      answer.text,
      '${signOutUnit.map((path) => '$path (guarded)\n').join()}'
      "guarded: ${signOutUnit.length} docs; the delete needs the Owner's ok\n"
      'plan $hash\ndry run: nothing removed\n',
    );
    expect(answer.json, {
      'files': signOutUnit,
      'guarded': signOutUnit,
      'records': isEmpty,
      'rewritten': <Object>[],
      'deleted': <Object>[],
      'mentions': <Object>[],
      'plan': hash,
    });
    expect(hasDoc(root, story2), isTrue);
  });

  test('a dry run marks each guarded file alone, counts them, and leaves '
      'the plan hash over the paths alone', () async {
    final root = await writeWriteProject(extra: approvedSignOut);
    docFile(
      root,
      'prds/features/f01_login/us02_sign_out/fr01_end_session.md',
    ).writeAsStringSync('---\ndraft: true\n---\n\n# End session\n');
    final answer = writeIn(
      root,
      (s) => answerDeleteDryRun(s, [
        'user_story:login/sign_out',
      ], generators: noGenerators),
    );
    final guarded = [story2, signOutUnit[2]];
    expect(
      answer.text,
      '$story2 (guarded)\n'
      '${signOutUnit[1]}\n'
      '${signOutUnit[2]} (guarded)\n'
      "guarded: 2 docs; the delete needs the Owner's ok\n"
      'plan ${baseHashOf(signOutUnit.map((path) => '$path ${baseHashOf(toLf(readDoc(root, path)))}\n').join())}\n'
      'dry run: nothing removed\n',
    );
    expect(answer.json['guarded'], guarded);
    expect(hasDoc(root, story2), isTrue);
  });

  test('a unit with no guarded file prints no guarded line and an empty '
      'guarded array', () async {
    final root = await writeWriteProject(extra: withoutLink);
    final answer = writeIn(
      root,
      (s) => answerDeleteDryRun(s, [
        'user_story:login/reset_password',
      ], generators: noGenerators),
    );
    expect(answer.text, isNot(contains('guarded:')));
    expect(answer.text, isNot(contains('(guarded)')));
    expect(answer.json['guarded'], isEmpty);
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
          (s) => answerDeleteDryRun(s, [
            'user_story:login/reset_password',
          ], generators: noGenerators),
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

  test('the plan hash is the same outside git, in a repo '
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
              (s) => answerDeleteDryRun(s, [
                'user_story:login/sign_out',
              ], generators: noGenerators),
            ).json['plan']!
            as String;

    expect(planOf(), expected, reason: 'outside git');
    expect(git(root, ['init', '-q']).exitCode, 0);
    expect(planOf(), expected, reason: 'no commit');
    commitAll(root, 'first');
    expect(planOf(), expected, reason: 'a commit');
  }, skip: hasGit ? null : 'git is not available');

  test('an uncommitted edit to a listed file after the dry run is '
      'plan_mismatch, exit 75, and nothing is removed', () async {
    final root = await writeWriteProject(extra: approvedSignOut);
    final hash =
        writeIn(
              root,
              (s) => answerDeleteDryRun(s, [
                'user_story:login/sign_out',
              ], generators: noGenerators),
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
            (s) => answerDeleteDryRun(s, [
              'user_story:login/sign_out',
            ], generators: noGenerators),
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

  for (final change in ['added to', 'removed from']) {
    test('a file added to the unit after the dry run is '
        'plan_mismatch and nothing is removed: $change', () async {
      final root = await writeWriteProject(extra: approvedSignOut);
      final hash = signOutPlan(root);
      final kept = [...signOutUnit];
      if (change == 'added to') {
        const added = 'prds/features/f01_login/us02_sign_out/notes.txt';
        docFile(root, added).writeAsStringSync('late\n');
        kept.add(added);
      } else {
        docFile(root, signOutUnit.last).deleteSync();
        kept.removeLast();
      }

      expectSignOutRefused(root, hash, kept);
    });
  }

  test('a listed file that is not UTF-8 and changes after '
      'the dry run is plan_mismatch and nothing is removed', () async {
    final root = await writeWriteProject(extra: approvedSignOut);
    const blob = 'prds/features/f01_login/us02_sign_out/blob.bin';
    docFile(root, blob).writeAsBytesSync([0xFF, 0xFE, 0xFD]);
    final hash = signOutPlan(root);
    // Same length and the same count of invalid bytes as before.
    docFile(root, blob).writeAsBytesSync([0xFE, 0xFF, 0xFC]);

    expectSignOutRefused(root, hash, [...signOutUnit, blob]);
  });

  test('a dry run refuses a referred unit as the run does', () async {
    final root = await writeWriteProject();
    expect(
      () => writeIn(
        root,
        (s) => answerDeleteDryRun(s, [
          'user_story:login/reset_password',
        ], generators: noGenerators),
      ),
      refusesWith(WriteFaultCode.docReferenced),
    );
  });

  test("--yes with the dry run's plan hash deletes an approved unit "
      "with no prompt, as the Owner's y does", () async {
    final root = await writeWriteProject(extra: approvedSignOut);
    final hash =
        writeIn(
              root,
              (s) => answerDeleteDryRun(s, [
                'user_story:login/sign_out',
              ], generators: noGenerators),
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
    test('--yes with $label is plan_mismatch, exit 75, and nothing '
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

  test('a unit of never-approved docs checks the plan hash under --yes the same way', () async {
    final root = await writeWriteProject(extra: withoutLink);
    String planOf() =>
        writeIn(
              root,
              (s) => answerDeleteDryRun(s, [
                'user_story:login/reset_password',
              ], generators: noGenerators),
            ).json['plan']!
            as String;
    final hash = planOf();
    final original = readDoc(root, fr32);
    docFile(root, fr32).writeAsStringSync('${original}More.\n');

    expect(
      () => del(
        root,
        ['user_story:login/reset_password'],
        confirmation: OwnerConfirmation.given,
        planHash: hash,
      ),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.planMismatch)
            .having((f) => f.exitStatus, 'exitStatus', 75),
      ),
    );
    for (final path in [story3, fr31, fr32]) {
      expect(hasDoc(root, path), isTrue, reason: path);
    }

    docFile(root, fr32).writeAsStringSync(original);
    final answer = del(
      root,
      ['user_story:login/reset_password'],
      confirmation: OwnerConfirmation.given,
      planHash: hash,
    );
    expect(answer.json['removed'], [story3, fr31, fr32]);
  });

  group('mention lines in each git state', () {
    const mentioned =
        'Read `user_story:login/reset_password#use_case` first.\n';
    const tracked = '.claude/rules/tracked.md';
    const untracked = '.claude/rules/untracked.md';

    Future<Directory> agentProject() => writeWriteProject(
      extra: {...withoutLink, 'CLAUDE.md': mentioned, tracked: mentioned},
    );

    List<String> mentionPaths(ReadAnswer answer) => [
      for (final mention in answer.json['mentions']! as List)
        (mention as Map<String, Object?>)['path']! as String,
    ];

    Future<void> expectMentions(Directory root, List<String> paths) async {
      final dry = writeIn(
        root,
        (s) => answerDeleteDryRun(s, [
          'user_story:login/reset_password',
        ], generators: noGenerators),
      );
      expect(mentionPaths(dry), paths);
      final applied = del(
        root,
        ['user_story:login/reset_password'],
        confirmation: OwnerConfirmation.given,
        planHash: dry.json['plan']! as String,
      );
      expect(applied.json['removed'], [story3, fr31, fr32]);
      expect(mentionPaths(applied), paths);
    }

    test(
      'outside any git work tree the instruction files alone are read',
      () async {
        final root = await agentProject();

        await expectMentions(root, ['CLAUDE.md']);
      },
    );

    test(
      'in a git work tree with no commit the instruction files alone are read',
      () async {
        final root = await agentProject();
        expect(git(root, ['init', '-q']).exitCode, 0);

        await expectMentions(root, ['CLAUDE.md']);
      },
      skip: hasGit ? null : 'git is not available',
    );

    test('in a git work tree with a commit the tracked agent files are read and an untracked one is not', () async {
      final root = await agentProject();
      expect(git(root, ['init', '-q']).exitCode, 0);
      commitAll(root, 'first');
      File('${root.path}/$untracked')
        ..createSync(recursive: true)
        ..writeAsStringSync(mentioned);

      await expectMentions(root, [tracked, 'CLAUDE.md']);
    }, skip: hasGit ? null : 'git is not available');
  });

  test('an FR goes alone', () async {
    final root = await writeWriteProject();
    expect(
      del(root, ['fr:login/reset_password/expire_reset_link']).json['removed'],
      [fr32],
    );
    expect([hasDoc(root, fr31), hasDoc(root, story3)], [true, true]);
  });

  test('an FR named by its DocPath goes alone', () async {
    final root = await writeWriteProject();
    expect(del(root, [fr32]).json['removed'], [fr32]);
    expect([hasDoc(root, fr31), hasDoc(root, story3)], [true, true]);
  });

  test('a feature goes with its spec folder', () async {
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
  });

  test('a persona goes with the anti-persona in its folder, and the emptied personas folder goes too', () async {
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

  test('a spec doc goes alone', () async {
    final root = await writeWriteProject();
    expect(del(root, ['architecture:signup']).json['removed'], [signupArch]);
    expect(hasDoc(root, signupFeature), isTrue);
  });

  test('a middle story delete leaves the higher sibling its number until the next reorder closes the gap', () async {
    final root = await writeWriteProject(extra: approvedSignOut);
    del(
      root,
      ['user_story:login/sign_out'],
      confirmation: OwnerConfirmation.prompt,
      answers: ['y'],
    );
    expect(hasDoc(root, story2), isFalse);
    expect([hasDoc(root, story1), hasDoc(root, story3)], [true, true]);

    writeIn(
      root,
      (s) => answerReorder(
        s,
        'user_story:login/reset_password',
        place: '2',
        generators: noGenerators,
      ),
    );

    expect(
      hasDoc(root, 'prds/features/f01_login/us02_reset_password/USER_STORY.md'),
      isTrue,
    );
    expect(hasDoc(root, story3), isFalse);
  });

  test(
    'a bare name that one typed doc carries deletes it like the typed name',
    () async {
      final root = await writeWriteProject(extra: withoutLink);

      final answer = del(root, ['login/reset_password']);

      expect(answer.json['removed'], [story3, fr31, fr32]);
      expect(hasDoc(root, story3), isFalse);
      expect([hasDoc(root, story1), hasDoc(root, story2)], [true, true]);
    },
  );

  test('a doc_ref value from outside is a referrer too', () async {
    final root = await writeWriteProject();
    expect(
      () => del(root, ['user_story:login/email_login']),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.docReferenced)
            .having((f) => f.relatedFiles, 'relatedFiles', [persona]),
      ),
    );
  });

  test(
    'a set on a deleted doc is doc_not_found and recreates nothing',
    () async {
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
            generators: noGenerators,
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
    },
  );

  test('an unreadable unit path names itself', () async {
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
            generators: noGenerators,
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

  test('an unmovable file is output_not_writable; the journal stays and the next write finishes the delete', () async {
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
            .having((f) => f.exitStatus, 'exitStatus', 73)
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

  test('a doc carrying draft and approved counts as approved', () async {
    for (final approved in ['true', '"0123456789ab"']) {
      final root = await writeWriteProject(
        extra: {
          'docs/$fr32':
              '---\ndraft: true\napproved: $approved\ntraced_from: US-03\nverify_method: test\n---\n\n# Expire reset link\n',
        },
      );
      expect(
        () => del(root, ['fr:login/reset_password/expire_reset_link']),
        refusesWith(WriteFaultCode.ownerTerminalRequired),
        reason: 'approved: $approved',
      );
      expect(hasDoc(root, fr32), isTrue, reason: 'approved: $approved');
    }
  });

  test('an untyped .md file with a hash beside draft is guarded', () async {
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

  test('a doc with no draft and no approved value is guarded whatever the config pins say', () async {
    final belowApprove = resolverCarrying({
      'prd-core': '1.6.0',
      'software-tech': '1.3.0',
    });
    for (final (label, config, templates) in [
      (
        'both packs pinned below the pins approve walks it from',
        'packs:\n  prd-core: 1.6.0\n  software-tech: 1.3.0\n',
        belowApprove,
      ),
      (
        'only prd-core pinned',
        shippedPinsConfig(['prd-core']),
        TemplateResolver(),
      ),
    ]) {
      final root = await writeWriteProject(
        extra: {
          '.specstone/config.yaml': config,
          'docs/$fr32': '# Expire reset link\n',
        },
      );

      expect(
        () => writeIn(
          root,
          (s) => answerDelete(
            s,
            ['fr:login/reset_password/expire_reset_link'],
            confirmation: OwnerConfirmation.missing,
            readLine: () => null,
            prompts: StringBuffer(),
            generators: noGenerators,
          ),
          templates: templates,
        ),
        refusesWith(WriteFaultCode.ownerTerminalRequired),
        reason: label,
      );
      expect(hasDoc(root, fr32), isTrue, reason: label);
    }
  });

  test('an approved doc edited after a commit stays guarded, and so does a doc whose hash no longer matches with no draft', () async {
    final root = await writeWriteProject();
    expect(git(root, ['init', '-q']).exitCode, 0);
    commitAll(root, 'approved');
    docFile(root, fr11).writeAsStringSync('${readDoc(root, fr11)}More.\n');
    commitAll(root, 'edit after approval');

    expect(
      () => del(root, ['fr:login/email_login/validate_credentials']),
      refusesWith(WriteFaultCode.ownerTerminalRequired),
    );
    expect(hasDoc(root, fr11), isTrue);

    final other = await writeWriteProject(
      extra: {
        'docs/$fr32': '---\napproved: "0123456789ab"\ntraced_from: US-03\nverify_method: test\n---\n\n# Expire reset link\n',
      },
    );
    expect(
      () => del(other, ['fr:login/reset_password/expire_reset_link']),
      refusesWith(WriteFaultCode.ownerTerminalRequired),
    );
    expect(hasDoc(other, fr32), isTrue);
  }, skip: hasGit ? null : 'git is not available');

  test('a doc whose whole frontmatter is invalid YAML is guarded', () async {
    final root = await writeWriteProject(
      extra: {'docs/$fr32': '---\ndraft: true\n: [unclosed\n---\n\n# Expire\n'},
    );
    expect(
      () => del(root, ['fr:login/reset_password/expire_reset_link']),
      refusesWith(WriteFaultCode.ownerTerminalRequired),
    );
    expect(hasDoc(root, fr32), isTrue);
  });

  test('the delete prompt holds no write lock', () async {
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
        generators: noGenerators,
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
            generators: noGenerators,
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
          generators: noGenerators,
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

  test('a guarded delete whose roots wait for the trust record refuses after the plan and terminal checks, before it lists the files', () async {
    final root = await writeWriteProject(
      without: {
        for (final k in writeProject.keys)
          if (k.startsWith('docs/')) k,
      },
    );
    final outside = await writeTree({
      for (final MapEntry(:key, :value) in {
        ...writeProject,
        ...approvedSignOut,
      }.entries)
        if (key.startsWith('docs/')) key.substring(5): value,
    });
    Link('${root.path}/docs').createSync(outside.path);
    final before = treeBytes(outside);
    final hash =
        writeIn(
              root,
              (s) => answerDeleteDryRun(s, [
                'user_story:login/sign_out',
              ], generators: noGenerators),
            ).json['plan']!
            as String;
    final prompts = StringBuffer();
    Matcher refusesOutside() => throwsA(
      isA<RenderFault>()
          .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
          .having((f) => f.exitStatus, 'exitStatus', 73)
          .having((f) => f.file, 'file', MoveJournal.journalPath),
    );

    expect(
      () => del(root, ['user_story:login/sign_out']),
      refusesWith(WriteFaultCode.ownerTerminalRequired),
    );
    expect(
      () => del(
        root,
        ['user_story:login/sign_out'],
        confirmation: OwnerConfirmation.given,
        planHash: '000000000000',
      ),
      refusesWith(WriteFaultCode.planMismatch),
    );
    expect(
      () => del(
        root,
        ['user_story:login/sign_out'],
        confirmation: OwnerConfirmation.prompt,
        answers: ['y'],
        prompts: prompts,
      ),
      refusesOutside(),
    );
    expect(prompts.toString(), isEmpty);
    expect(
      () => del(
        root,
        ['user_story:login/sign_out'],
        confirmation: OwnerConfirmation.given,
        planHash: hash,
      ),
      refusesOutside(),
    );
    expect(treeBytes(outside), before);
  }, skip: Platform.isWindows ? 'links need privileges on Windows' : false);

  test('the Owner deleting a never-approved unit sees no prompt', () async {
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

  test(
    'a file added while the prompt waits lists the unit and prompts again',
    () async {
      for (final (change, listedAfter) in [
        ('a file added', 4),
        ('a byte changed', 3),
      ]) {
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
              if (asked == 1 && listedAfter == 4) {
                docFile(
                  root,
                  '$_signOut/fr03_new.md',
                ).writeAsStringSync('---\ndraft: true\n---\n\n# New\n');
              } else if (asked == 1) {
                docFile(
                  root,
                  '$_signOut/fr01_end_session.md',
                ).writeAsStringSync(
                  '---\napproved: true\n---\n\n# End sessioN\n',
                );
              }
              return 'y';
            },
            prompts: prompts,
            generators: noGenerators,
          ),
        );
        expect(asked, 2, reason: change);
        expect(
          'delete '.allMatches(prompts.toString()),
          hasLength(2),
          reason: change,
        );
        expect(
          prompts.toString(),
          contains('delete 3 files? [y/N] '),
          reason: change,
        );
        expect(
          prompts.toString(),
          contains('delete $listedAfter files? [y/N] '),
          reason: change,
        );
        expect(answer.json['removed'], hasLength(listedAfter), reason: change);
        expect(
          Directory('${root.path}/docs/$_signOut').existsSync(),
          isFalse,
          reason: change,
        );
      }
    },
  );

  test(
    'an untyped .md file in the unit with no draft counts as approved',
    () async {
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
    },
  );

  test('the end of input at the delete prompt removes nothing', () async {
    final root = await writeWriteProject(extra: approvedSignOut);
    final answer = del(root, [
      'user_story:login/sign_out',
    ], confirmation: OwnerConfirmation.prompt);
    expect(answer.text, isEmpty);
    expect(answer.json, {
      'removed': <String>[],
      'rewritten': <Object>[],
      'deleted': <Object>[],
      'mentions': <Object>[],
    });
    expect(hasDoc(root, story2), isTrue);
  });

  test('a non-.md file in the unit goes to the trash with it', () async {
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

  test('the folder a removed file segment leaves empty goes, and the folder that still holds a doc stays', () async {
    final root = await writeWriteProject(
      extra: {
        'docs/specs/topics/doc_model.md':
            '---\ndraft: true\ncovers:\n  - app/lib/\n---\n\n# Doc model\n',
      },
    );
    expect(del(root, ['charter:doc_model']).json['removed'], [
      'specs/topics/doc_model.md',
    ]);
    expect(Directory('${root.path}/docs/specs/topics').existsSync(), isFalse);
    expect(Directory('${root.path}/docs/specs').existsSync(), isTrue);
  });

  test('an empty subfolder and a symlink in the unit go, and so does the unit folder', () async {
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

  test('a link added while the prompt waits refuses doc_referenced', () async {
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
          generators: noGenerators,
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

  test('a replay fault during the refresh after y is a RenderFault and the session closes once', () async {
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
          generators: noGenerators,
        ),
      ),
      throwsA(isA<RenderFault>()),
    );
    expect(hasDoc(root, story2), isTrue);
  });

  test('referrersOf: doc_ref referrers, then link referrers, each once in tree order', () async {
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

    test('an untyped DocPath deletes that one file only', () async {
      for (final prefix in ['', 'docs/']) {
        final root = await writeWriteProject(extra: untyped);
        final answer = del(root, ['$prefix$scratch']);
        expect(answer.json, {
          'removed': [scratch],
          'rewritten': <Object>[],
          'deleted': <Object>[],
          'mentions': <Object>[],
        }, reason: 'prefix "$prefix"');
        expect(hasDoc(root, scratch), isFalse, reason: 'prefix "$prefix"');
        expect(hasDoc(root, loginArch), isTrue, reason: 'prefix "$prefix"');
      }
    });

    test(
      'an untyped single-file delete moves the file to the trash folder',
      () async {
        final root = await writeWriteProject(extra: untyped);
        expect(
          () => IOOverrides.runWithIOOverrides(
            () => del(root, [scratch]),
            FailingRenameHook('docs/$scratch'),
          ),
          throwsA(isA<RenderFault>()),
        );

        final journal = File('${root.path}/${MoveJournal.journalPath}');
        expect(journal.existsSync(), isTrue);
        expect(
          journal.readAsStringSync(),
          contains('.specstone/trash/files/docs/$scratch'),
        );
        writeIn(root, (s) => s.index.docs.length);
        expect(hasDoc(root, scratch), isFalse);
        expect(hasDoc(root, notes), isTrue);
        expect(
          Directory('${root.path}/.specstone/trash').existsSync(),
          isFalse,
        );
      },
    );

    test('three untyped docs that link to each other go in one call', () async {
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
        'rewritten': <Object>[],
        'deleted': <Object>[],
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

    test('several targets name the set in the Owner gate', () async {
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
    });

    test('a story outside two docs that links into one is doc_referenced, and neither goes', () async {
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

    test('a link from an untyped file outside the checked folders does not block; the delete warns it will dangle', () async {
      final root = await writeWriteProject(extra: withPlan);

      final answer = del(root, [scratch]);

      expect(answer.json, {
        'removed': [scratch],
        'rewritten': <Object>[],
        'deleted': <Object>[],
        'mentions': <Object>[],
      });
      expect(answer.warnings, [
        '$plan links into $scratch; the link will dangle',
      ]);
      expect(hasDoc(root, scratch), isFalse);
      expect(readDoc(root, plan), planText);
    });

    test(
      'a dry run warns of the link that will dangle, as the run does',
      () async {
        final root = await writeWriteProject(extra: withPlan);

        final answer = writeIn(
          root,
          (s) => answerDeleteDryRun(s, [scratch], generators: noGenerators),
        );

        expect(answer.json['files'], [scratch]);
        expect(answer.warnings, [
          '$plan links into $scratch; the link will dangle',
        ]);
        expect(hasDoc(root, scratch), isTrue);
      },
    );

    test('an old untyped file under specs/ that links in is doc_referenced; the plan beside it is not listed', () async {
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

    test(
      'a typed doc outside the checked folders that links in is doc_referenced',
      () async {
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
      },
    );

    test(
      'a link from one file of the set to another neither blocks nor warns',
      () async {
        final root = await writeWriteProject(extra: withPlan);

        final answer = del(
          root,
          [scratch, plan],
          confirmation: OwnerConfirmation.prompt,
          answers: ['y'],
        );

        expect(answer.json, {
          'removed': [scratch, plan]..sort(),
          'rewritten': <Object>[],
          'deleted': <Object>[],
          'mentions': <Object>[],
        });
        expect(answer.warnings, isEmpty);
      },
    );

    test('a target inside the unit of another counts each file once', () async {
      final root = await writeWriteProject(extra: withoutLink);
      final answer = del(root, [
        'user_story:login/reset_password',
        'fr:login/reset_password/expire_reset_link',
      ]);
      expect(answer.json, {
        'removed': [story3, fr31, fr32],
        'rewritten': <Object>[],
        'deleted': <Object>[],
        'mentions': <Object>[],
      });
    });

    test('the prompt counts each file of a target inside another target once', () async {
      final root = await writeWriteProject(
        extra: {
          'docs/prds/FEATURES.md': '# Feature index\n\n## Systems\n- [Signup](features/f02_signup/FEATURE.md)\n',
          'docs/$persona':
              '---\ndraft: true\n---\n\n# Buyer\n\n## Profile\nBuys things.\n',
        },
      );
      final alone =
          writeIn(
                root,
                (s) => answerDeleteDryRun(s, [
                  'feature:login',
                ], generators: noGenerators),
              ).json['files']!
              as List;
      final prompts = StringBuffer();

      final answer = del(
        root,
        ['feature:login', 'user_story:login/email_login'],
        confirmation: OwnerConfirmation.prompt,
        answers: ['y'],
        prompts: prompts,
      );

      expect(answer.json['removed'], alone);
      expect(
        prompts.toString(),
        endsWith('delete ${alone.length} files? [y/N] '),
      );
      for (final path in alone) {
        expect(
          '$path\n'.allMatches(prompts.toString()),
          hasLength(1),
          reason: '$path',
        );
      }
    });

    test('the same target twice removes its file once', () async {
      final root = await writeWriteProject(extra: untyped);
      final answer = del(root, [scratch, scratch]);
      expect(answer.json, {
        'removed': [scratch],
        'rewritten': <Object>[],
        'deleted': <Object>[],
        'mentions': <Object>[],
      });
    });

    test('one target of several that names no doc is doc_not_found, and nothing goes', () async {
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

    test(
      'a bare name 2 docs carry among several targets is argument_invalid',
      () async {
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
      },
    );
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

    test('a typed doc outside the unit that mentions a doc of it makes the delete warn; the delete goes on', () async {
      final root = await mentioning({
        project: '# Project context\n\nSee `features/f01_login/FEATURE.md`.\n',
      });

      final answer = delLogin(root);

      expect(answer.json['removed'], contains(loginFeature));
      expect(answer.warnings, [mentionWarning]);
      expect(hasDoc(root, loginFeature), isFalse);
      expect(hasDoc(root, project), isTrue);
    });

    test('a dry run warns of the mention, as the run does', () async {
      final root = await mentioning({
        project: '# Project context\n\nSee `features/f01_login/FEATURE.md`.\n',
      });

      final answer = writeIn(
        root,
        (s) =>
            answerDeleteDryRun(s, ['feature:login'], generators: noGenerators),
      );

      expect(answer.warnings, [mentionWarning]);
      expect(hasDoc(root, loginFeature), isTrue);
    });

    test('two mentions on two lines of one doc give one warning', () async {
      final root = await mentioning({
        project:
            '# Project context\n\nSee `features/f01_login/FEATURE.md`.\n\n'
            'Again `features/f01_login/FEATURE.md`.\n',
      });

      expect(delLogin(root).warnings, [mentionWarning]);
    });

    test('a mention from inside the unit gives no warning', () async {
      for (final mention in [
        '`features/f01_login/FEATURE.md`',
        '`feature:login` and `login/reset_password`',
      ]) {
        final root = await mentioning({
          'prds/features/f01_login/us01_email_login/USER_STORY.md':
              writeProject['docs/$story1']!.replaceFirst(
                'Sign in with an email.',
                'Sign in with an email, see $mention.',
              ),
        });

        expect(delLogin(root).warnings, isEmpty, reason: mention);
      }
    });

    test(
      'the mentioning doc keeps its bytes whatever form its mentions take',
      () async {
        const text =
            '# Project context\n\nSee `features/f01_login/FEATURE.md`,\n'
            '`feature:login`, and `login/reset_password`.\n';
        final root = await mentioning({project: text});

        final answer = delLogin(root);

        expect(answer.json['removed'], contains(loginFeature));
        expect(answer.warnings, isNotEmpty);
        expect(readDoc(root, project), text);
      },
    );

    test('a mention from an untyped doc gives no warning', () async {
      for (final mention in [
        'features/f01_login/FEATURE.md',
        'feature:login',
      ]) {
        final root = await mentioning({
          'prds/d02_notes.md': '# Notes\n\nSee `$mention`.\n',
        });

        expect(delLogin(root).warnings, isEmpty, reason: mention);
      }
    });

    test('the link warning comes first, then the mentions in tree order of the mentioned docs, then of the mentioning docs', () async {
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

    test(
      'a doc that links into the unit still refuses, with no mention warning',
      () async {
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
      },
    );

    test('a mermaid node naming a doc of the unit warns once and the delete '
        'goes ahead', () async {
      final root = await mentioning({
        project:
            '# Project context\n\n```mermaid\nflowchart LR\n'
            '  N[login/reset_password E02]\n  M[login/reset_password]\n```\n',
      });

      final answer = delLogin(root);

      expect(answer.json['removed'], contains(story3));
      expect(answer.warnings, [
        '$project mentions $story3; the mention will dangle',
      ]);
      expect(hasDoc(root, project), isTrue);
    });

    test("another language's fence or a longer code span gives no warning", () async {
      final root = await mentioning({
        project:
            '# Project context\n\n```text\nN[login/reset_password E02]\n```\n\n'
            'See `login/reset_password E02`.\n',
      });

      expect(delLogin(root).warnings, isEmpty);
    });

    test('a doc-name mention of the feature warns as a path mention does, the delete going on', () async {
      final root = await mentioning({
        project: '# Project context\n\nSee `feature:login`.\n',
      });

      final answer = delLogin(root);

      expect(answer.json['removed'], contains(loginFeature));
      expect(answer.warnings, [mentionWarning]);
      expect(hasDoc(root, project), isTrue);
    });

    test('a bare name and a typed name of one doc on two lines give one warning, and a dry run warns the same', () async {
      final root = await mentioning({
        project:
            '# Project context\n\nSee `login/reset_password`.\n\n'
            'And `user_story:login/reset_password`.\n',
      });

      final answer = writeIn(
        root,
        (s) =>
            answerDeleteDryRun(s, ['feature:login'], generators: noGenerators),
      );

      expect(answer.warnings, [
        '$project mentions $story3; the mention will dangle',
      ]);
      expect(hasDoc(root, story3), isTrue);
    });
  });

  test('delete of a story an FR of another feature traces is doc_referenced listing that FR', () async {
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

    test('delete of a story a journey step names is doc_referenced', () async {
      final root = await writeWriteProject(extra: _onlyJourneyRefers('S1'));
      expect(
        () => del(root, ['user_story:login/reset_password']),
        refusedForJourney(story3),
      );
      expect(hasDoc(root, story3), isTrue);
      expect(hasDoc(root, _journeyPath), isTrue);
    });

    test("delete of the story's feature is doc_referenced", () async {
      final root = await writeWriteProject(extra: _onlyJourneyRefers('S1'));
      expect(
        () => del(root, ['feature:login']),
        refusedForJourney(loginFeature),
      );
      expect(hasDoc(root, loginFeature), isTrue);
    });

    test('delete of the journey removes its folder; its steps point out of the unit', () async {
      final root = await writeWriteProject(extra: _onlyJourneyRefers('S1'));
      expect(del(root, ['journey:sign_in']).json['removed'], [_journeyPath]);
      expect(
        Directory('${root.path}/docs/prds/journeys/sign_in').existsSync(),
        isFalse,
      );
      expect(hasDoc(root, story3), isTrue);
    });

    test('the journey and the story in one call are removed', () async {
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
    });

    test('a step naming a missing scenario of a story in the unit still refers to it', () async {
      final root = await writeWriteProject(extra: _onlyJourneyRefers('S9'));
      expect(
        () => del(root, ['user_story:login/reset_password']),
        refusedForJourney(story3),
      );
      expect(hasDoc(root, story3), isTrue);
    });

    test('a journey step outside a several-target set refuses and removes neither target', () async {
      final root = await writeWriteProject(extra: _onlyJourneyRefers('S1'));
      expect(
        () => del(root, [
          'user_story:login/reset_password',
          'architecture:signup',
        ]),
        refusedForJourney(story3),
      );
      expect([hasDoc(root, story3), hasDoc(root, signupArch)], [true, true]);
    });
  });

  test('deleting a sub-feature takes its folder and its spec folder, and the top feature stays', () async {
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

  test(
    'deleting a grouped feature removes its own folder and keeps the group',
    () async {
      final root = await writeGroupedProject(
        extra: {'docs/specs/kitchen/f02_menus/ARCHITECTURE.md': '# Menus\n'},
      );
      del(
        root,
        ['feature:kitchen/recipes'],
        confirmation: OwnerConfirmation.prompt,
        answers: ['y'],
      );
      expect(hasDoc(root, kitchenMenus), isTrue);
      for (final folder in [
        'prds/features/kitchen/f01_recipes',
        'specs/kitchen/f01_recipes',
      ]) {
        expect(Directory('${root.path}/docs/$folder').existsSync(), isFalse);
      }
      for (final group in ['prds/features/kitchen', 'specs/kitchen']) {
        expect(Directory('${root.path}/docs/$group').existsSync(), isTrue);
      }
    },
  );

  test(
    'deleting the only feature of a group prunes the emptied group folders',
    () async {
      final root = await writeGroupedProject(
        extra: {
          'docs/prds/features/garden/f01_herbs/FEATURE.md': '# Herbs\n',
          'docs/specs/garden/f01_herbs/ARCHITECTURE.md': '# Herbs\n',
        },
      );
      del(
        root,
        ['feature:garden/herbs'],
        confirmation: OwnerConfirmation.prompt,
        answers: ['y'],
      );
      for (final folder in ['prds/features/garden', 'specs/garden']) {
        expect(Directory('${root.path}/docs/$folder').existsSync(), isFalse);
      }
      expect(hasDoc(root, kitchenRecipes), isTrue);
    },
  );

  test('a doc outside that links into a sub-feature is doc_referenced, and nothing is removed', () async {
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

    test('a story delete drops the entries of the story and of its FRs from the record, marks it draft, and lists only the removed files', () async {
      final root = await writeWriteProject(extra: _withRecords());
      final signupBefore = readDoc(root, _signupRecord);
      final answer = del(root, ['user_story:login/reset_password']);
      expect(answer.json, {
        'removed': removedStory3,
        'rewritten': <Object>[],
        'deleted': <Object>[],
        'mentions': <Object>[],
      });
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

    test(
      'a story delete drops the tests lines of the story and of its FRs',
      () async {
        final root = await writeWriteProject(
          extra: _withRecords(
            login: recordText(
              statuses: ['email_login:implemented'],
              tests: [
                'email_login:app/test/login_test.dart',
                'reset_password:app/test/reset_test.dart',
                'reset_password/send_reset_link:app/test/reset_test.dart:sends',
              ],
            ),
          ),
        );
        del(root, ['user_story:login/reset_password']);
        final record = readDoc(root, _loginRecord);
        expect(record, contains("'email_login:app/test/login_test.dart'"));
        expect(record, isNot(contains('reset_password')));
      },
    );

    test('an FR delete drops the entry of that FR alone', () async {
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

    test('a record left with no entry stays', () async {
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

    test('a record that holds no entry of the unit is not written', () async {
      final root = await writeWriteProject(
        extra: _withRecords(
          login: recordText(statuses: ['email_login:planned']),
        ),
      );
      final before = readDoc(root, _loginRecord);
      del(root, ['user_story:login/reset_password']);
      expect(readDoc(root, _loginRecord), before);
    });

    test('a nested feature record names its items relative to it, and a record of another feature is left', () async {
      final root = await writeNestedProject(
        extra: {
          '.specstone/templates/implementation.yaml': recordLayerAtRoot,
          _cartRecord: recordText(
            statuses: [
              'add_item:implemented',
              'add_item/check_stock:implemented',
              'drop_item:planned',
            ],
          ),
          '.specstone/records/f02_shop/IMPLEMENTATION.md': recordText(
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
        readDoc(root, '.specstone/records/f02_shop/IMPLEMENTATION.md'),
        contains("'drop_item:planned'"),
      );
    });

    test('a read-only record refuses output_not_writable in the dry run as in the run, and nothing is removed', () async {
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
          (s) => answerDeleteDryRun(s, [
            'user_story:login/reset_password',
          ], generators: noGenerators),
        ),
        refusesRecord(),
      );
      expect(
        () => del(root, ['user_story:login/reset_password']),
        refusesRecord(),
      );
      expect(hasDoc(root, story3), isTrue);
    }, skip: unreadablePathSkipReason() ?? false);

    test('a record whose implements block is not valid YAML refuses in the dry run as in the run, and nothing is removed', () async {
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
          (s) => answerDeleteDryRun(s, [
            'user_story:login/reset_password',
          ], generators: noGenerators),
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

    test(
      'a record with CRLF line ends and a byte-order mark keeps both',
      () async {
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
      },
    );

    test('a feature delete removes no entry, its record leaving with the spec folder', () async {
      final root = await writeNestedProject(
        extra: {
          '.specstone/templates/implementation.yaml': recordLayerAtRoot,
          _cartRecord: recordText(statuses: ['add_item:implemented']),
          // no doc links into the sub-feature once the API doc is freed
          'docs/$shopApi': '# Shop API\n',
          'docs/$cartDomain': recordText(),
        },
      );
      final answer = writeIn(
        root,
        (s) => answerDeleteDryRun(s, [
          'feature:shop/cart',
        ], generators: noGenerators),
      );
      expect(answer.json['records'], isEmpty);
      expect(answer.json['files'], contains(_cartRecord));
      expect(answer.text, isNot(contains('rewrites')));
    });

    const recordEntries =
        'rewrites $_loginRecord: reset_password, '
        'reset_password/send_reset_link, reset_password/expire_reset_link';

    test('a dry run lists each record it rewrites after the files, and its plan hash covers the text of the record', () async {
      final root = await writeWriteProject(extra: _withRecords());
      final answer = writeIn(
        root,
        (s) => answerDeleteDryRun(s, [
          'user_story:login/reset_password',
        ], generators: noGenerators),
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
        'guarded': isEmpty,
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
        'rewritten': <Object>[],
        'deleted': <Object>[],
        'mentions': <Object>[],
        'plan': hash,
      });
      expect(readDoc(root, _loginRecord), _loginRecordText);
      expect(hasDoc(root, story3), isTrue);
    });

    test('--yes --plan deletes and rewrites the record while it is as the dry run saw it, and refuses plan_mismatch once it is edited', () async {
      final root = await writeWriteProject(extra: _withRecords());
      String planOf() =>
          writeIn(
                root,
                (s) => answerDeleteDryRun(s, [
                  'user_story:login/reset_password',
                ], generators: noGenerators),
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
      expect(answer.json, {
        'removed': removedStory3,
        'rewritten': <Object>[],
        'deleted': <Object>[],
        'mentions': <Object>[],
      });
      expect(hasDoc(root, story3), isFalse);
      expect(readDoc(root, _loginRecord), isNot(contains('reset_password')));
    });

    test('the mentions lines follow the rewrites lines, a tracked CLAUDE.md among them, and the apply keeps those files as they are', () async {
      const code = '// `login/reset_password` goes\n';
      const agent = 'Details: `docs/$story3`.\n';
      final root = await writeWriteProject(
        extra: {
          ..._withRecords(),
          'docs/specs/TECH_STACK.md':
              '---\ncode:\n  - lib/\n---\n\n# Tech stack\n\n## Stack\n\n'
              '| Slot | Choice |\n|---|---|\n| Language | Dart |\n\n'
              '## Naming\n\n- snake_case file names\n',
          'app/lib/reset.dart': code,
          'CLAUDE.md': agent,
        },
      );
      expect(git(root, ['init', '-q']).exitCode, 0);
      commitAll(root, 'first');
      const mentions =
          'mentions CLAUDE.md:1 docs/$story3\n'
          'mentions app/lib/reset.dart:1 login/reset_password\n';

      final dry = writeIn(
        root,
        (s) => answerDeleteDryRun(s, [
          'user_story:login/reset_password',
        ], generators: noGenerators),
      );
      expect(
        dry.text,
        '${removedStory3.join('\n')}\n$recordEntries\n${mentions}plan '
        '${dry.json['plan']}\ndry run: nothing removed\n',
      );

      final applied = del(root, ['user_story:login/reset_password']);
      expect(applied.text, '${removedStory3.join('\n')}\n$mentions');
      expect(File('${root.path}/CLAUDE.md').readAsStringSync(), agent);
      expect(File('${root.path}/app/lib/reset.dart').readAsStringSync(), code);
    }, skip: hasGit ? null : 'git is not available');

    test('the Owner prompt lists each record with its entries and counts the files of the unit alone; a record edited while it waits shows the list again, and nothing is written', () async {
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
          generators: noGenerators,
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

    group('matrix rows', () {
      const sendRow =
          '- reset_password/send_reset_link E01: `sends a link` 5d1e0c4b7a92';
      const sendSkip =
          '- reset_password/send_reset_link E02 skipped: needs a mail server  '
          '9a1c03be55d2';
      const expireRow =
          '- reset_password/expire_reset_link E01: `expires a link` '
          '1b2c3d4e5f60';
      const validateRow =
          '- email_login/validate_credentials E01: `checks the email` '
          '7f6e5d4c3b2a';
      const noRows = '\n## Verification matrix\n\n';

      /// The `login` record with a matrix section holding [rows].
      String recordWithRows(List<String> rows) =>
          '$_loginRecordText$noRows${rows.join('\n')}\n';

      Future<Directory> projectWithRows(List<String> rows) =>
          writeWriteProject(extra: _withRecords(login: recordWithRows(rows)));

      test("deleting an FR removes that FR's rows alone", () async {
        final root = await projectWithRows([
          sendRow,
          validateRow,
          sendSkip,
          expireRow,
        ]);
        del(root, ['fr:login/reset_password/expire_reset_link']);

        final record = readDoc(root, _loginRecord);
        expect(record, isNot(contains('expire_reset_link')));
        for (final kept in [sendRow, validateRow, sendSkip]) {
          expect(record, contains('\n$kept\n'));
        }
        expect(record, contains("'reset_password/send_reset_link:planned'"));
      });

      test('a record without the section is untouched', () async {
        final prose =
            '${recordText(statuses: ['email_login:implemented'])}\n'
            '## Notes\n\n$sendRow\n';
        final root = await writeWriteProject(extra: _withRecords(login: prose));
        del(root, ['user_story:login/reset_password']);

        expect(readDoc(root, _loginRecord), prose);
      });

      test(
        'a delete replayed from its journal ends with the rows gone',
        () async {
          final root = await projectWithRows([sendRow, validateRow, expireRow]);
          final before = readDoc(root, _loginRecord);
          expect(
            () => IOOverrides.runWithIOOverrides(
              () => del(root, ['user_story:login/reset_password']),
              FailingRenameHook('docs/$fr31'),
            ),
            throwsA(isA<RenderFault>()),
          );
          expect(readDoc(root, _loginRecord), before);

          writeIn(root, (s) => s.index.docs.length);

          final record = readDoc(root, _loginRecord);
          expect(record, contains('\n$validateRow\n'));
          expect(record, isNot(contains('reset_password')));
          expect(record, contains('draft: true'));
          expect(
            File('${root.path}/${MoveJournal.journalPath}').existsSync(),
            isFalse,
          );
        },
      );

      test('a dry run lists an item whose rows alone leave', () async {
        final root = await writeWriteProject(
          extra: _withRecords(
            login:
                '${recordText(statuses: ['email_login:implemented'])}'
                '$noRows$expireRow\n',
          ),
        );
        final answer = writeIn(
          root,
          (s) => answerDeleteDryRun(s, [
            'fr:login/reset_password/expire_reset_link',
          ], generators: noGenerators),
        );

        expect(answer.json['records'], [
          {
            'path': _loginRecord,
            'entries': ['reset_password/expire_reset_link'],
          },
        ]);
        expect(
          answer.text,
          contains(
            'rewrites $_loginRecord: reset_password/expire_reset_link\n',
          ),
        );
      });
    });
  });

  group('with two code targets', () {
    final twinStatuses = [
      'email_login:implemented',
      'email_login/check_password:implemented',
    ];
    const twinItems = ['email_login', 'email_login/check_password'];
    const flutterRecord =
        '.specstone/records/flutter/f01_login/IMPLEMENTATION.md';
    const jasprRecord = '.specstone/records/jaspr/f01_login/IMPLEMENTATION.md';

    Future<Directory> twins() => writeTwinProject(
      extra: {
        flutterRecord: recordText(statuses: twinStatuses),
        jasprRecord: recordText(statuses: twinStatuses),
        // the API doc names the story's FR in its trace; free it of the link
        'docs/${check.loginApi}': '# Login API\n',
        // the feature map's catalog links the feature; free it of the link
        'docs/prds/FEATURES.md': '# Feature map\n',
      },
    );

    test('a feature delete removes its folder and the spec folder of each target, each record among them', () async {
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

    test('a story delete drops its entries from the record of every target, and check reports no unresolved entry it made', () async {
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
      final report = await check.checkOf(root);
      expect([
        for (final f in report.findings)
          if (f.kind == FindingKind.recordEntryUnresolved) f.path,
      ], isEmpty);
    });

    test('--target names one twin of a per-target doc, and the delete takes that file alone', () async {
      final root = await twins();
      expect(
        () => writeIn(
          root,
          (s) => answerDeleteDryRun(s, [
            'architecture:login',
          ], generators: noGenerators),
        ),
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
        (s) => answerDeleteDryRun(
          s,
          ['architecture:login'],
          codeTarget: 'jaspr',
          generators: noGenerators,
        ),
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

    test('a code target keeps the names of one target, and a target the project lacks is argument_invalid', () async {
      final root = await twins();
      final answer = writeIn(
        root,
        (s) => answerDeleteDryRun(
          s,
          ['user_story:login/email_login'],
          codeTarget: 'jaspr',
          generators: noGenerators,
        ),
      );
      expect(answer.json['files'], hasLength(3));
      expect(answer.json['records'], [
        {'path': flutterRecord, 'entries': twinItems},
        {'path': jasprRecord, 'entries': twinItems},
      ]);
      expect(
        () => writeIn(
          root,
          (s) => answerDeleteDryRun(
            s,
            ['user_story:login/email_login'],
            codeTarget: 'dart',
            generators: noGenerators,
          ),
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

  group('records under .specstone/records/', () {
    // The files that leave no doc outside the login feature pointing into it.
    final freeOfLoginReferrers = {
      'docs/prds/FEATURES.md': '# Feature index\n\n## Systems\n- [Signup](features/f02_signup/FEATURE.md)\n',
      'docs/$persona':
          '---\ndraft: true\n---\n\n# Buyer\n\n## Profile\nBuys things.\n',
    };

    const record = '.specstone/records/f01_login/IMPLEMENTATION.md';
    final recordBody = recordText(statuses: ['email_login:implemented']);

    File recordFile(Directory root) => File(
      '${root.path}${Platform.pathSeparator}'
      '${record.replaceAll('/', Platform.pathSeparator)}',
    );

    Future<Directory> recordProject() => writeWriteProject(
      extra: {
        ...freeOfLoginReferrers,
        ...recordsRootTemplates,
        record: recordBody,
      },
    );

    test('a feature delete removes its record folder and names the record by its project path', () async {
      final root = await recordProject();
      final prompts = StringBuffer();
      final answer = del(
        root,
        ['feature:login'],
        confirmation: OwnerConfirmation.prompt,
        answers: ['y'],
        prompts: prompts,
      );
      expect(answer.json['removed'], contains(record));
      expect(prompts.toString(), contains('$record\n'));
      expect(recordFile(root).existsSync(), isFalse);
      expect(recordFile(root).parent.existsSync(), isFalse);
    });

    test('the delete plan lists the record by its project path', () async {
      final root = await recordProject();
      final answer = writeIn(
        root,
        (s) =>
            answerDeleteDryRun(s, ['feature:login'], generators: noGenerators),
      );
      expect(answer.json['files'], contains(record));
      expect(answer.text, contains('$record (guarded)\n'));
      expect(recordFile(root).existsSync(), isTrue);
    });

    group('an approved record is the only guard of a feature', () {
      const signupRecord = '.specstone/records/f02_signup/IMPLEMENTATION.md';

      // signup holds only drafts, so its record is the one doc that can gate.
      Future<Directory> signupProject({required bool approved}) =>
          writeWriteProject(
            extra: {
              ...recordsRootTemplates,
              'docs/prds/FEATURES.md':
                  '# Feature index\n\n## Systems\n'
                  '- [Login](features/f01_login/FEATURE.md)\n',
              'docs/prds/d01_context.md': '# Context\n',
              signupRecord: recordText(
                front: approved ? 'approved: true\n' : 'draft: true\n',
                statuses: ['ghost:planned'],
              ),
            },
          );

      test('guards the delete under its project path until the Owner says yes', () async {
        final root = await signupProject(approved: true);
        final answer = writeIn(
          root,
          (s) => answerDeleteDryRun(s, [
            'feature:signup',
          ], generators: noGenerators),
        );
        expect(answer.json['guarded'], [signupRecord]);
        expect(
          () => del(root, ['feature:signup']),
          refusesWith(WriteFaultCode.ownerTerminalRequired),
        );
        expect(
          File(
            '${root.path}/${signupRecord.replaceAll('/', Platform.pathSeparator)}',
          ).existsSync(),
          isTrue,
        );
      });

      test('a draft record leaves the same feature free to delete', () async {
        final root = await signupProject(approved: false);
        final answer = del(root, ['feature:signup']);
        expect(answer.json['removed'], contains(signupRecord));
        expect(
          Directory('${root.path}/.specstone/records/f02_signup').existsSync(),
          isFalse,
        );
      });
    });

    group('nested feature records', () {
      const cartRecord =
          '.specstone/records/f02_shop/f01_cart/IMPLEMENTATION.md';
      const payRecord = '.specstone/records/f02_shop/f02_pay/IMPLEMENTATION.md';

      Future<Directory> nestedProject() => writeNestedProject(
        without: {'docs/$shopApi'},
        extra: {
          ...recordsRootTemplates,
          cartRecord: recordText(statuses: ['add_item:planned']),
          payRecord: recordText(statuses: ['card:planned']),
        },
      );

      bool exists(Directory root, String path) => File(
        '${root.path}${Platform.pathSeparator}'
        '${path.replaceAll('/', Platform.pathSeparator)}',
      ).existsSync();

      test(
        'deleting a sub-feature removes its nested record folder alone',
        () async {
          final root = await nestedProject();
          final answer = del(
            root,
            ['feature:shop/cart'],
            confirmation: OwnerConfirmation.prompt,
            answers: ['y'],
          );
          expect(answer.json['removed'], contains(cartRecord));
          expect(exists(root, cartRecord), isFalse);
          expect(exists(root, payRecord), isTrue);
        },
      );

      test(
        'deleting the top feature removes the records of its sub-features',
        () async {
          final root = await nestedProject();
          final answer = del(
            root,
            ['feature:shop'],
            confirmation: OwnerConfirmation.prompt,
            answers: ['y'],
          );
          expect(answer.json['removed'], containsAll([cartRecord, payRecord]));
          expect(
            Directory('${root.path}/.specstone/records/f02_shop').existsSync(),
            isFalse,
          );
        },
      );
    });

    test(
      'a feature delete with no record folder removes the feature alone',
      () async {
        final root = await writeWriteProject(
          extra: {...freeOfLoginReferrers, ...recordsRootTemplates},
        );
        final answer = del(
          root,
          ['feature:login'],
          confirmation: OwnerConfirmation.prompt,
          answers: ['y'],
        );
        expect(
          (answer.json['removed']! as List).cast<String>(),
          isNot(contains(startsWith('.specstone/records/'))),
        );
      },
    );
  });
}
