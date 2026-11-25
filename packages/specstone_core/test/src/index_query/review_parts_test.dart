// The test names and file literals are plan text kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/document_writing/approve_drafts.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/index_query/review_parts.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/git_repo.dart';
import '../../helpers/write_fixture.dart';

const _story = 'prds/features/f02_signup/us01_register/USER_STORY.md';
const _checkEmail =
    'prds/features/f02_signup/us01_register/fr01_check_email.md';
const _sendCode = 'prds/features/f02_signup/us01_register/fr02_send_code.md';
const _checkName = 'signup/register/check_email';
const _sendName = 'signup/register/send_code';

const _storyText =
    '---\ndraft: true\n---\n\n# Register\n\n## Use Case\n\nRegister with an email.\n';

const _feature =
    '---\napproved: true\n---\n\n# Signup\n\n'
    '## Problem\n\nUsers create an account.\n\n'
    '## Benefit hypothesis\n\nUsers finish signup faster.\n\n'
    '## Feature flow\n\nThe user types an email.\n\n'
    '## Out-of-scope\n\n- Social login.\n';

/// An FR text: [edgeCases] lines under its edge cases, [statement] under its statement.
String _fr({
  String mark = 'approved: true',
  String statement = 'The system shall check the email.',
  String edgeCases =
      '1. E01 — A blank email is refused. It names the field.\n'
      '2. E02 — A long email is cut.',
  String extraSections = '',
  String extraFields = '',
}) =>
    '---\n$mark\n${extraFields}traced_from: US-01\nverify_method: test\n---\n\n'
    '# Check email\n\n## Statement\n\n$statement\n\n'
    '## Edge cases\n\n$edgeCases\n$extraSections';

/// The FR a second FR cites from, with edge cases of its own.
String _sendFr({
  String mark = 'approved: true',
  String statement = 'The system shall send a code.',
}) => _fr(
  mark: mark,
  statement: statement,
  edgeCases: '1. E01 — A code is sent once.',
);

/// A repository whose first commit holds [approved] and whose second holds
/// [drafts] over them, as the approve dry run reads two commits.
Future<Directory> _repo({
  Map<String, String> approved = const {},
  Map<String, String> drafts = const {},
}) async {
  final root = await writeWriteProject(
    extra: {for (final e in approved.entries) 'docs/${e.key}': e.value},
  );
  expect(git(root, ['init', '-q']).exitCode, 0);
  expect(git(root, ['config', 'core.autocrlf', 'false']).exitCode, 0);
  commitAll(root, 'approved');
  for (final MapEntry(:key, :value) in drafts.entries) {
    final file = docFile(root, key);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(value);
  }
  commitAll(root, 'edited as a draft');
  return root;
}

ReviewParts _review(Directory root, List<String> targets) {
  final session = ReadSession.open(
    templates: TemplateResolver(),
    workingDirectory: root,
    homeDirectory: testHome(),
  );
  try {
    return pickReviewParts(
      session.index,
      targets,
      draftViewsOf(session, names: targets),
    );
  } finally {
    session.close();
  }
}

Iterable<ReviewPart> _ofKind(ReviewParts review, ReviewPartKind kind) =>
    review.parts.where((part) => part.kind == kind);

/// Returns `<pattern id> <listing doc name>` per pattern part of [review].
List<String> _patternLabels(ReviewParts review) => [
  for (final part in _ofKind(review, ReviewPartKind.pattern))
    '${part.featurePattern} ${part.doc.name}',
];

const _verifyFr =
    'prds/features/f02_signup/f01_verify/us01_confirm/fr01_match_code.md';

/// A repository whose `signup` feature lists [signupPattern] and whose
/// `signup/verify` sub-feature lists [verifyPattern], with the verify FR a
/// draft, and the check-email FR one too when [draftsCheckEmail].
Future<Directory> _nestedPatternRepo({
  required String signupPattern,
  required String verifyPattern,
  bool draftsCheckEmail = false,
}) => _repo(
  approved: {
    'prds/features/f02_signup/FEATURE.md': _feature.replaceFirst(
      'approved: true\n',
      'approved: true\npatterns:\n  - $signupPattern\n',
    ),
    'prds/features/f02_signup/f01_verify/FEATURE.md':
        '---\napproved: true\npatterns:\n  - $verifyPattern\n---\n\n# Verify\n\n'
        '## Problem\n\nUsers mistype codes.\n',
    'prds/features/f02_signup/f01_verify/us01_confirm/USER_STORY.md':
        _storyText,
    _verifyFr: _fr(),
    _story: _storyText,
    _checkEmail: _fr(),
  },
  drafts: {
    _verifyFr: _fr(
      mark: 'draft: true',
      statement: 'The system shall match the code.',
    ),
    if (draftsCheckEmail)
      _checkEmail: _fr(
        mark: 'draft: true',
        statement: 'The system shall check the email twice.',
      ),
  },
);

void main() {
  final skipGit = hasGit ? null : 'git is not available';

  test('a changed item prints whole in its new text with its dropped sentences under it', () async {
    final root = await _repo(
      approved: {_story: _storyText, _checkEmail: _fr()},
      drafts: {
        _checkEmail: _fr(
          mark: 'draft: true',
          edgeCases:
              '1. E01 — A blank email is refused with a message.\n'
              '2. E02 — A long email is cut.',
        ),
      },
    );

    final changed = _ofKind(
      _review(root, ['fr:$_checkName']),
      ReviewPartKind.changedUnit,
    ).single;

    expect(changed.doc.name, _checkName);
    expect(changed.sectionKey, 'edge_cases');
    expect(changed.itemId, 'E01');
    expect(
      changed.text,
      contains('1. E01 — A blank email is refused with a message.'),
    );
    expect(changed.text, isNot(contains('E02')));
    expect(
      changed.text,
      endsWith(
        'Dropped sentences:\n'
        '- E01 — A blank email is refused.\n'
        '- It names the field.',
      ),
    );
  }, skip: skipGit);

  test(
    'a section the dry run names with no sentence change prints whole',
    () async {
      const fence = '```text\nA -> B\n```';
      final root = await _repo(
        approved: {
          _story: _storyText,
          _checkEmail: _fr(extraSections: '\n## Behavior\n\n$fence\n'),
        },
        drafts: {
          _checkEmail: _fr(
            mark: 'draft: true',
            extraSections: '\n## Behavior\n\n```text\nA -> C\n```\n',
          ),
        },
      );

      final changed = _ofKind(
        _review(root, ['fr:$_checkName']),
        ReviewPartKind.changedUnit,
      ).single;

      expect(changed.sectionKey, 'behavior');
      expect(changed.itemId, isNull);
      expect(changed.text, startsWith('## Behavior\n'));
      expect(changed.text, contains('A -> C'));
      expect(changed.text, isNot(contains('Dropped sentences:')));
    },
    skip: skipGit,
  );

  test('a removed item prints under its old section by its ID with its dropped sentences and its citers', () async {
    final root = await _repo(
      approved: {
        _story: _storyText,
        _checkEmail: _fr(),
        _sendCode: _sendFr(
          statement: 'The system shall send a code after [E02](fr01_check_email.md#edge-cases).',
        ),
      },
      drafts: {
        _checkEmail: _fr(
          mark: 'draft: true',
          edgeCases: '1. E01 — A blank email is refused. It names the field.',
        ),
      },
    );

    final review = _review(root, ['fr:$_checkName']);

    final removed = _ofKind(review, ReviewPartKind.removedUnit).single;
    expect(removed.sectionKey, 'edge_cases');
    expect(removed.itemId, 'E02');
    expect(removed.text, 'Dropped sentences:\n- E02 — A long email is cut.');
    final citer = _ofKind(review, ReviewPartKind.citer).single;
    expect(citer.doc.name, _sendName);
    expect(citer.sectionKey, 'statement');
    expect(citer.cites, ['$_checkName (fr) E02']);
    expect(citer.text, contains('[E02](fr01_check_email.md#edge-cases)'));
  }, skip: skipGit);

  test('a citer of two changed units prints once naming each', () async {
    final root = await _repo(
      approved: {
        _story: _storyText,
        _checkEmail: _fr(),
        _sendCode: _sendFr(
          statement: 'The system shall send a code after [E01](fr01_check_email.md#edge-cases) and [E02](fr01_check_email.md#edge-cases).',
        ),
      },
      drafts: {
        _checkEmail: _fr(
          mark: 'draft: true',
          edgeCases:
              '1. E01 — A blank email is refused with a message.\n'
              '2. E02 — A long email is cut at 80 characters.',
        ),
      },
    );

    final citer = _ofKind(
      _review(root, ['fr:$_checkName']),
      ReviewPartKind.citer,
    ).single;

    expect(citer.doc.name, _sendName);
    expect(citer.cites, ['$_checkName (fr) E01', '$_checkName (fr) E02']);
  }, skip: skipGit);

  test(
    'a target printed whole draws no citers for its unchanged text',
    () async {
      final root = await _repo(
        drafts: {'prds/d01_context.md': '# Context\n\n## Features\nChanged.\n'},
      );

      final review = _review(root, ['feature:login']);

      final whole = _ofKind(review, ReviewPartKind.wholeTarget).single;
      expect(whole.doc.name, 'login');
      expect(whole.sectionKey, isNull);
      expect(
        whole.text,
        contains('Users sign in with an email and a password.'),
      );
      expect(_ofKind(review, ReviewPartKind.citer), isEmpty);
    },
    skip: skipGit,
  );

  test("a draft with only a confirmed change gives no changed unit but its feature's summary sections", () async {
    final root = await _repo(
      approved: {
        'prds/features/f02_signup/FEATURE.md': _feature,
        _story: _storyText,
        _checkEmail: _fr(),
      },
      drafts: {
        _checkEmail: _fr(
          mark: 'draft: true',
          extraFields: 'confirmed:\n  - S1 56480b5ff00e\n',
        ),
      },
    );

    final review = _review(root, ['fr:$_checkName']);

    expect(_ofKind(review, ReviewPartKind.changedUnit), isEmpty);
    expect(
      [
        for (final part in _ofKind(review, ReviewPartKind.summarySection))
          '${part.doc.name}#${part.sectionKey}',
      ],
      [
        'signup#benefit_hypothesis',
        'signup#flow',
        'signup#out_of_scope',
        'signup#components',
      ],
    );
    expect(review.refsDocs, ['fr:$_checkName']);
  }, skip: skipGit);

  test(
    'a feature target prints only its own units, not other drafts under it',
    () async {
      final root = await _repo(
        approved: {
          'prds/features/f02_signup/FEATURE.md': _feature,
          _story: _storyText,
          _checkEmail: _fr(),
        },
        drafts: {
          'prds/features/f02_signup/FEATURE.md': _feature
              .replaceFirst('approved: true', 'draft: true')
              .replaceFirst(
                'create an account',
                'create an account in one step',
              ),
          _checkEmail: _fr(
            mark: 'draft: true',
            statement: 'The system shall check the email twice.',
          ),
        },
      );

      final review = _review(root, ['feature:signup']);

      final changed = _ofKind(review, ReviewPartKind.changedUnit).single;
      expect(changed.doc.name, 'signup');
      expect(changed.sectionKey, 'problem');
      expect(
        review.parts.where((part) => part.doc.name == _checkName),
        isEmpty,
      );
    },
    skip: skipGit,
  );

  test('summary sections of each touched feature and ancestor print once', () async {
    const nested = 'prds/features/f02_signup/f01_verify/FEATURE.md';
    const nestedStory =
        'prds/features/f02_signup/f01_verify/us01_confirm/USER_STORY.md';
    const nestedFr =
        'prds/features/f02_signup/f01_verify/us01_confirm/fr01_match_code.md';
    const nestedFeature =
        '---\napproved: true\n---\n\n# Verify\n\n## Problem\n\nUsers mistype codes.\n\n## Benefit hypothesis\n\nFewer wrong codes get in.\n';
    final root = await _repo(
      approved: {
        'prds/features/f02_signup/FEATURE.md': _feature,
        nested: nestedFeature,
        nestedStory: _storyText,
        nestedFr: _fr(),
      },
      drafts: {
        nestedFr: _fr(
          mark: 'draft: true',
          statement: 'The system shall match the code.',
        ),
      },
    );

    final review = _review(root, [
      'fr:verify/confirm/match_code',
      'feature:verify',
    ]);

    final labels = [
      for (final part in _ofKind(review, ReviewPartKind.summarySection))
        '${part.doc.name}#${part.sectionKey}',
    ];
    expect(labels, [
      'signup#benefit_hypothesis',
      'signup#flow',
      'signup#out_of_scope',
      'signup#components',
      'signup/verify#benefit_hypothesis',
    ]);
    expect(labels.toSet(), hasLength(labels.length));
  }, skip: skipGit);

  test('a summary section that already prints as a citer prints once', () async {
    const arch = 'specs/f02_signup/ARCHITECTURE.md';
    final root = await _repo(
      approved: {
        'prds/features/f02_signup/FEATURE.md': _feature,
        _story: _storyText,
        _checkEmail: _fr(),
        arch:
            '---\napproved: true\n---\n\n# Signup architecture\n\n## Components\n\n'
            '| Component | Responsibility | Tech | Owns |\n|---|---|---|---|\n'
            '| Form | Runs [check email](../../prds/features/f02_signup/us01_register/fr01_check_email.md) | Dart | form |\n',
      },
      drafts: {
        _checkEmail: _fr(
          mark: 'draft: true',
          statement: 'The system shall check the email twice.',
        ),
      },
    );

    final review = _review(root, ['fr:$_checkName']);

    final details = review.parts
        .where(
          (part) => part.doc.docPath == arch && part.sectionKey == 'components',
        )
        .toList();
    expect(details, hasLength(1));
    expect(details.single.kind, ReviewPartKind.citer);
  }, skip: skipGit);

  test("a touched feature's architecture components print as a summary part", () async {
    final root = await _repo(
      approved: {
        'prds/features/f02_signup/FEATURE.md': _feature,
        _story: _storyText,
        _checkEmail: _fr(),
        'specs/f02_signup/ARCHITECTURE.md':
            '---\napproved: true\n---\n\n# Signup architecture\n\n## Components\n\n'
            '| Component | Responsibility | Tech | Owns |\n|---|---|---|---|\n'
            '| Form | Takes the email | Dart | form |\n',
      },
      drafts: {
        _checkEmail: _fr(
          mark: 'draft: true',
          statement: 'The system shall check the email twice.',
        ),
      },
    );

    final review = _review(root, ['fr:$_checkName']);

    expect(
      [
        for (final part in _ofKind(review, ReviewPartKind.summarySection))
          if (part.doc.docTypeId != 'feature')
            '${part.doc.docTypeId}#${part.sectionKey}',
      ],
      ['architecture#components'],
    );
  }, skip: skipGit);

  test("the lowest feature's pattern parts print after the summary sections and an ancestor feature's do not", () async {
    final root = await _nestedPatternRepo(
      signupPattern: 'crud',
      verifyPattern: 'file_upload',
    );

    final review = _review(root, ['fr:verify/confirm/match_code']);

    final patterns = _ofKind(review, ReviewPartKind.pattern).toList();
    expect(_patternLabels(review), ['file_upload signup/verify']);
    expect(patterns.single.text, contains('- **allowed_types** '));
    final kinds = [for (final part in review.parts) part.kind];
    expect(
      kinds.indexOf(ReviewPartKind.pattern),
      greaterThan(kinds.lastIndexOf(ReviewPartKind.summarySection)),
    );
  }, skip: skipGit);

  test('a pattern an ancestor feature also lists prints at the lowest feature holding the target', () async {
    final root = await _nestedPatternRepo(
      signupPattern: 'crud',
      verifyPattern: 'crud',
    );

    final review = _review(root, ['fr:verify/confirm/match_code']);

    expect(_patternLabels(review), ['crud signup/verify']);
  }, skip: skipGit);

  test('the same targets in either order give the same pattern parts', () async {
    const crudFeature = 'approved: true\npatterns:\n  - crud\n';
    final root = await _repo(
      approved: {
        'prds/features/f01_login/FEATURE.md':
            '---\n$crudFeature---\n\n# Login\n\n## Problem\n\nUsers sign in.\n',
        'prds/features/f02_signup/FEATURE.md': _feature.replaceFirst(
          'approved: true\n',
          crudFeature,
        ),
        _story: _storyText,
        _checkEmail: _fr(),
      },
      drafts: {
        _checkEmail: _fr(
          mark: 'draft: true',
          statement: 'The system shall check the email twice.',
        ),
      },
    );

    final loginFirst = _review(root, ['feature:login', 'fr:$_checkName']);
    final signupFirst = _review(root, ['fr:$_checkName', 'feature:login']);

    expect(_patternLabels(loginFirst), ['crud login']);
    expect(_patternLabels(signupFirst), _patternLabels(loginFirst));
  }, skip: skipGit);

  test('a sub-feature holding a target under the feature holding them all prints its pattern parts', () async {
    final root = await _nestedPatternRepo(
      signupPattern: 'crud',
      verifyPattern: 'file_upload',
      draftsCheckEmail: true,
    );

    final review = _review(root, [
      'fr:$_checkName',
      'fr:verify/confirm/match_code',
    ]);

    expect(_patternLabels(review), [
      'crud signup',
      'file_upload signup/verify',
    ]);
  }, skip: skipGit);

  test('refs docs are the smallest doc per top feature and each target outside every feature', () async {
    final root = await _repo(
      approved: {_story: _storyText, _checkEmail: _fr(), _sendCode: _sendFr()},
      drafts: {
        _checkEmail: _fr(
          mark: 'draft: true',
          statement: 'The system shall check the email twice.',
        ),
        _sendCode: _sendFr(
          mark: 'draft: true',
          statement: 'The system shall send a code twice.',
        ),
      },
    );

    final review = _review(root, [
      'fr:$_checkName',
      'fr:$_sendName',
      'feature:login',
      'persona:buyer',
    ]);

    expect(review.refsDocs, [
      'user_story:signup/register',
      'feature:login',
      'persona:buyer',
    ]);
  }, skip: skipGit);

  test(
    'a draft whose approved copy git cannot find prints as a whole target',
    () async {
      final root = await _repo(drafts: {_story: _storyText});

      final review = _review(root, ['user_story:signup/register']);

      final whole = _ofKind(review, ReviewPartKind.wholeTarget).single;
      expect(whole.doc.name, 'signup/register');
      expect(whole.text, contains('Register with an email.'));
      expect(_ofKind(review, ReviewPartKind.changedUnit), isEmpty);
    },
    skip: skipGit,
  );

  test(
    "a target that also cites another target's changed unit prints once",
    () async {
      final root = await _repo(
        approved: {
          _story: _storyText,
          _checkEmail: _fr(),
          _sendCode: _sendFr(
            statement: 'The system shall send a code after [E01](fr01_check_email.md#edge-cases).',
          ),
        },
        drafts: {
          _checkEmail: _fr(
            mark: 'draft: true',
            edgeCases: '1. E01 — A blank email is refused with a message.\n2. E02 — A long email is cut.',
          ),
          _sendCode: _sendFr(
            mark: 'draft: true',
            statement: 'The system shall send a code at once after [E01](fr01_check_email.md#edge-cases).',
          ),
        },
      );

      final review = _review(root, ['fr:$_checkName', 'fr:$_sendName']);

      final sendParts = review.parts
          .where((part) => part.doc.name == _sendName)
          .toList();
      expect(sendParts, hasLength(1));
      expect(sendParts.single.kind, ReviewPartKind.changedUnit);
    },
    skip: skipGit,
  );
}
