// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/cold_node.dart';
import '../../helpers/temp_tree.dart';

const _stale =
    "the doc changed since the Owner approved it; it waits for the Owner's specstone approve";
const _unapproved =
    "the doc carries no approval; it waits for the Owner's specstone approve";

List<Finding> _stales(CheckReport report) => [
  for (final f in report.findings)
    if (f.kind == FindingKind.approvalStale) f,
];

/// Returns an LF fixture FR whose approval hash matches [shape], found by
/// trying a counter in its Rationale, and that hash.
(String, String) _frHashing(RegExp shape) {
  final files = checkProjectFiles();
  final docType = fixtureDocTypeOf(loginFr);
  final plain = files['docs/$loginFr']!;
  for (var i = 0; i < 200000; i++) {
    final text = plain.replaceFirst(
      'must not sign in.',
      'must not sign in $i.',
    );
    final hash = approvalHashOf(text, docType);
    if (shape.hasMatch(hash)) return (text, hash);
  }
  throw StateError('no text hashes to $shape');
}

void main() {
  useColdHostNode();

  test(
    'a project whose docs carry their approval hash raises no approval_stale',
    () async {
      expect(_stales(await checkOf(await writeCheckProject())), isEmpty);
    },
  );

  test('an approved story edited in an editor is one approval_stale on its approved: line, and none once the Owner approves', () async {
    final edited = await checkOf(
      await writeCheckProject(
        extra: editedAfterApproval(loginStory, [('Sign in', 'Sign in again')]),
      ),
    );
    expect(spots(edited, FindingKind.approvalStale), [
      '$loginStory:2: approval_stale',
    ]);
    final finding = _stales(edited).single;
    expect(finding.message, _stale);
    expect(finding.name, 'login/email_login');
    expect(finding.keys, {'recorded': isA<String>()});

    final approved = await checkOf(
      await writeCheckProject(
        extra: doc(loginStory, 'Sign in', 'Sign in again'),
      ),
    );
    expect(_stales(approved), isEmpty);
  });

  test('a change of layout alone raises no approval_stale', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: editedAfterApproval(loginFeature, [
          ('## Problem\n\n', '## Problem\n\n\n\n'),
        ]),
      ),
    );
    expect(_stales(report), isEmpty);
  });

  test("a write of a record entry's code paths or of covers raises no approval_stale", () async {
    const recordPath = '.specstone/records/f01_login/IMPLEMENTATION.md';
    final base = {
      ...checkProjectFiles(),
      recordPath:
          "---\nstatuses:\n  - 'email_login/check_password:implemented'\n"
          "implements:\n  - 'email_login/check_password:app/lib/login.dart:checkPassword'\n"
          'covers:\n  - app/lib/\n'
          '---\n\n# Record\n',
    };
    final approved = withApprovalHashes(base);
    final record = approved[recordPath]!;
    expect(record, contains('approved:'));
    final report = await checkOf(
      await writeTree({
        ...approved,
        recordPath: record
            .replaceFirst(
              'app/lib/login.dart:checkPassword',
              'app/lib/login.dart:SignInPage',
            )
            .replaceFirst('  - app/lib/\n', '  - app/lib/login.dart\n'),
      }),
    );
    expect(_stales(report), isEmpty);
  });

  test('a change of a task_ref list raises no approval_stale', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: {
          '.specstone/templates/feature.yaml':
              'fields:\n  - id: tasks\n    type: task_ref\n    list: true\n',
          ...editedAfterApproval(loginFeature, [
            ('  - PG-01\n---', '  - PG-01\ntasks:\n  - T-1\n---'),
          ]),
        },
      ),
    );
    expect(_stales(report), isEmpty);
  });

  group('a record status edited by hand after approval', () {
    const from = 'email_login/check_password:implemented';
    const to = 'email_login/check_password:planned';

    test('raises no approval_stale', () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: editedAfterApproval(loginRecord, [(from, to)]),
        ),
      );
      expect(_stales(report), isEmpty);
    });
  });

  test('a draft beside an approved: hash its content does not match raises no approval_stale', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: editedAfterApproval(loginStory, [
          ('goals:\n', 'draft: true\ngoals:\n'),
          ('Sign in', 'Sign in again'),
        ]),
      ),
    );
    expect(_stales(report), isEmpty);
  });

  test('a doc with no approved: key is one approval_stale on line 1, and none as a draft', () async {
    final plain = checkProjectFiles()['docs/$loginFr']!;
    final report = await checkOf(
      await writeCheckProject(
        extra: {'docs/$loginFr': plain},
        unstamped: {'docs/$loginFr'},
      ),
    );
    expect(spots(report, FindingKind.approvalStale), [
      '$loginFr:1: approval_stale',
    ]);
    final finding = _stales(report).single;
    expect(finding.message, _unapproved);
    expect(finding.keys, isEmpty);
    expect(finding.name, 'login/email_login/check_password');

    final draft = await checkOf(
      await writeCheckProject(
        extra: {
          'docs/$loginFr': plain.replaceFirst(
            'traced_from:\n',
            'draft: true\ntraced_from:\n',
          ),
        },
      ),
    );
    expect(_stales(draft), isEmpty);
  });

  test('approved: true is one approval_stale on its line with value true, and no other finding', () async {
    final marked = fr('traced_from:\n', 'approved: true\ntraced_from:\n');
    final report = await checkOf(await writeCheckProject(extra: marked));
    expect(spots(report), ['$loginFr:2: approval_stale']);
    expect(report.findings.single.keys, {'recorded': 'true'});
    expect(report.findings.single.message, _stale);
  });

  test('an untyped doc raises no approval_stale', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: {'docs/prds/notes.md': '# Notes\n\nA scratch note.\n'},
      ),
    );
    expect(spots(report, FindingKind.untypedDoc), [
      'prds/notes.md:1: untyped_doc',
    ]);
    expect(_stales(report), isEmpty);
  });

  test('an approved: value YAML reads as a number is one approval_stale, even when its digits match; the quoted digits match', () async {
    final (digitsText, digits) = _frHashing(RegExp(r'^\d{12}$'));
    final bare = await checkOf(
      await writeCheckProject(
        extra: {
          'docs/$loginFr': digitsText.replaceFirst(
            'traced_from:\n',
            'approved: $digits\ntraced_from:\n',
          ),
        },
      ),
    );
    expect(spots(bare, FindingKind.approvalStale), [
      '$loginFr:2: approval_stale',
    ]);
    expect(_stales(bare).single.keys, {'recorded': digits});

    final (exponentText, exponent) = _frHashing(RegExp(r'^\d+e\d+$'));
    String withValue(String value) => exponentText.replaceFirst(
      'traced_from:\n',
      'approved: $value\ntraced_from:\n',
    );
    final unquoted = await checkOf(
      await writeCheckProject(extra: {'docs/$loginFr': withValue(exponent)}),
    );
    expect(spots(unquoted, FindingKind.approvalStale), [
      '$loginFr:2: approval_stale',
    ]);
    expect(_stales(unquoted).single.keys, {'recorded': exponent});

    final quoted = await checkOf(
      await writeCheckProject(
        extra: {'docs/$loginFr': withValue('"$exponent"')},
      ),
    );
    expect(_stales(quoted), isEmpty);

    final quotedDigits = await checkOf(
      await writeCheckProject(
        extra: {
          'docs/$loginFr': digitsText.replaceFirst(
            'traced_from:\n',
            'approved: "$digits"\ntraced_from:\n',
          ),
        },
        unstamped: {'docs/$loginFr'},
      ),
    );
    expect(_stales(quotedDigits), isEmpty);
  });

  test(
    'a refresh of a generated block after approval raises no approval_stale',
    () async {
      const journey = 'prds/journeys/sign_in/JOURNEY.md';
      const journeyKey = 'docs/$journey';
      String text(String flow) =>
          '# Sign in\n\n## Goal\n\nGet in.\n\n## Flow\n\n'
          '<!-- specstone:generated journey_flow (do not edit) -->\n'
          '```mermaid\nflowchart TD\n  $flow\n```\n'
          '<!-- specstone:generated end -->\n\n## Steps\n';
      final approved = withApprovalHashes({
        ...checkProjectFiles(),
        journeyKey: text('stale'),
      });
      expect(approved[journeyKey], contains('approved:'));
      final report = await checkOf(
        await writeTree({
          ...approved,
          journeyKey: approved[journeyKey]!.replaceFirst(
            'stale',
            'start --> done',
          ),
        }),
        docPath: journey,
      );
      expect(_stales(report), isEmpty);
    },
  );

  test('a literal overflowing exponent reads as written', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: fr('traced_from:\n', 'approved: 123e45678901\ntraced_from:\n'),
      ),
    );
    expect(spots(report, FindingKind.approvalStale), [
      '$loginFr:2: approval_stale',
    ]);
    expect(_stales(report).single.keys, {'recorded': '123e45678901'});
  });

  test('an approved: key with no value reports its own line with the no-approval message and no value', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: fr('traced_from:\n', 'approved:\ntraced_from:\n'),
        unstamped: {'docs/$loginFr'},
      ),
    );
    expect(spots(report, FindingKind.approvalStale), [
      '$loginFr:2: approval_stale',
    ]);
    final finding = _stales(report).single;
    expect(finding.message, _unapproved);
    expect(finding.keys, isEmpty);
  });

  test('an approved: list of any shape is one approval_stale with value as written, and check does not throw', () async {
    for (final (written, value) in [
      ('approved: []', '[]'),
      ('approved: [a, b]', '[a, b]'),
      ('approved:\n  - a\n  - b', '- a\n  - b'),
    ]) {
      final report = await checkOf(
        await writeCheckProject(
          extra: fr('traced_from:', '$written\ntraced_from:'),
        ),
      );
      expect(spots(report, FindingKind.approvalStale), [
        '$loginFr:2: approval_stale',
      ], reason: written);
      expect(_stales(report).single.keys, {'recorded': value}, reason: written);
    }
  });
}
