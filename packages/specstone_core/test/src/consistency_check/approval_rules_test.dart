// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:typed_data';

import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/temp_tree.dart';

const _name = 'consistency_check/find_template_breaks/report_stale_approvals';
const _stale =
    "the doc changed since the Owner approved it; it waits for the Owner's specstone approve";
const _unapproved =
    "the doc carries no approval; it waits for the Owner's specstone approve";

/// The packs' versions below both pins, which the shipped packs refuse unless
/// they carry them.
const _belowPins = 'packs:\n  prd-core: 1.6.0\n  software-tech: 1.3.0\n';

List<Finding> _stales(CheckReport report) => [
  for (final f in report.findings)
    if (f.kind == FindingKind.approvalStale) f,
];

/// Checks the fixture project pinned below both approval pins.
Future<CheckReport> _checkBelowPins(Map<String, String> extra) async {
  final root = await writeTree({
    ...checkProjectFiles(),
    '.specstone/config.yaml': _belowPins,
    ...extra,
  });
  final files = {...shippedPackFiles};
  for (final MapEntry(:key, :value) in {
    'prd-core': '1.6.0',
    'software-tech': '1.3.0',
  }.entries) {
    final manifest = utf8.decode(files['$key/pack.yaml']!);
    files['$key/pack.yaml'] = Uint8List.fromList(
      utf8.encode(
        manifest.replaceFirst(
          RegExp(r'^version: .*$', multiLine: true),
          'version: $value',
        ),
      ),
    );
  }
  final session = ReadSession.open(
    templates: TemplateResolver(shippedFiles: files),
    workingDirectory: root,
    homeDirectory: null,
  );
  try {
    return runCheck(session);
  } finally {
    session.close();
  }
}

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
  test(
    '$_name: a project whose docs carry their approval hash raises no approval_stale',
    () async {
      expect(_stales(checkOf(await writeCheckProject())), isEmpty);
    },
  );

  test(
    '$_name E01: an approved story edited in an editor is one approval_stale on its approved: line, and none once the Owner approves',
    () async {
      final edited = checkOf(
        await writeCheckProject(
          extra: editedAfterApproval(loginStory, [
            ('Sign in', 'Sign in again'),
          ]),
        ),
      );
      expect(spots(edited, FindingKind.approvalStale), [
        '$loginStory:3: approval_stale',
      ]);
      final finding = _stales(edited).single;
      expect(finding.message, _stale);
      expect(finding.name, 'login/email_login');
      expect(finding.keys, {'value': isA<String>()});

      final approved = checkOf(
        await writeCheckProject(
          extra: doc(loginStory, 'Sign in', 'Sign in again'),
        ),
      );
      expect(_stales(approved), isEmpty);
    },
  );

  test(
    '$_name E02: a change of layout alone raises no approval_stale',
    () async {
      final report = checkOf(
        await writeCheckProject(
          extra: editedAfterApproval(loginFeature, [
            ('## Problem\n\n', '## Problem\n\n\n\n'),
          ]),
        ),
      );
      expect(_stales(report), isEmpty);
    },
  );

  test('$_name E03: a write of implements raises no approval_stale', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: editedAfterApproval(loginStory, [
          ('app/lib/login.dart:SignInPage', 'app/lib/login.dart:checkPassword'),
        ]),
      ),
    );
    expect(_stales(report), isEmpty);
  });

  test(
    '$_name E04: a draft beside an approved: hash its content does not match raises no approval_stale',
    () async {
      final report = checkOf(
        await writeCheckProject(
          extra: editedAfterApproval(loginStory, [
            ('status: implemented\n', 'status: implemented\ndraft: true\n'),
            ('Sign in', 'Sign in again'),
          ]),
        ),
      );
      expect(_stales(report), isEmpty);
    },
  );

  test(
    '$_name E05: a doc with no approved: key is one approval_stale on line 1 once the pins reach the stamps, and none below them or as a draft',
    () async {
      final plain = checkProjectFiles()['docs/$loginFr']!;
      final report = checkOf(
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

      expect(_stales(await _checkBelowPins({'docs/$loginFr': plain})), isEmpty);

      final draft = checkOf(
        await writeCheckProject(
          extra: {
            'docs/$loginFr': plain.replaceFirst(
              'status: implemented\n',
              'status: implemented\ndraft: true\n',
            ),
          },
        ),
      );
      expect(_stales(draft), isEmpty);
    },
  );

  test(
    '$_name E06: approved: true is one approval_stale on its line with value true once the pins reach the stamps, and no other finding; below them it counts as approved',
    () async {
      final marked = fr(
        'status: implemented\n',
        'status: implemented\napproved: true\n',
      );
      final report = checkOf(await writeCheckProject(extra: marked));
      expect(spots(report), ['$loginFr:3: approval_stale']);
      expect(report.findings.single.keys, {'value': 'true'});
      expect(report.findings.single.message, _stale);

      expect(spots(await _checkBelowPins(marked)), isEmpty);
    },
  );

  test(
    '$_name E07: a doc stamped with the hash of its rewritten content raises no approval_stale',
    () async {
      final text = checkProjectFiles()['docs/$loginFr']!.replaceFirst(
        'refuse a wrong password',
        'turn away a wrong password',
      );
      final docType = fixtureDocTypeOf(loginFr);
      final report = checkOf(
        await writeCheckProject(
          extra: {'docs/$loginFr': withApprovalHash(text, docType)},
        ),
      );
      expect(_stales(report), isEmpty);
    },
  );

  test('$_name E08: an untyped doc raises no approval_stale', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {'docs/prds/notes.md': '# Notes\n\nA scratch note.\n'},
      ),
    );
    expect(spots(report, FindingKind.untypedDoc), [
      'prds/notes.md:1: untyped_doc',
    ]);
    expect(_stales(report), isEmpty);
  });

  test(
    '$_name E09: an approved: value YAML reads as a number is one approval_stale, even when its digits match; the quoted digits match',
    () async {
      final (digitsText, digits) = _frHashing(RegExp(r'^\d{12}$'));
      final bare = checkOf(
        await writeCheckProject(
          extra: {
            'docs/$loginFr': digitsText.replaceFirst(
              'status: implemented\n',
              'status: implemented\napproved: $digits\n',
            ),
          },
        ),
      );
      expect(spots(bare, FindingKind.approvalStale), [
        '$loginFr:3: approval_stale',
      ]);
      expect(_stales(bare).single.keys, {'value': digits});

      final (exponentText, exponent) = _frHashing(RegExp(r'^\d+e\d+$'));
      String withValue(String value) => exponentText.replaceFirst(
        'status: implemented\n',
        'status: implemented\napproved: $value\n',
      );
      final unquoted = checkOf(
        await writeCheckProject(extra: {'docs/$loginFr': withValue(exponent)}),
      );
      expect(spots(unquoted, FindingKind.approvalStale), [
        '$loginFr:3: approval_stale',
      ]);
      expect(_stales(unquoted).single.keys, {'value': exponent});

      final quoted = checkOf(
        await writeCheckProject(
          extra: {'docs/$loginFr': withValue('"$exponent"')},
        ),
      );
      expect(_stales(quoted), isEmpty);
    },
  );

  test('$_name E09: a literal overflowing exponent reads as written', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: fr(
          'status: implemented\n',
          'status: implemented\napproved: 123e45678901\n',
        ),
      ),
    );
    expect(spots(report, FindingKind.approvalStale), [
      '$loginFr:3: approval_stale',
    ]);
    expect(_stales(report).single.keys, {'value': '123e45678901'});
  });

  test(
    '$_name: an approved: key with no value reports its own line with the no-approval message and no value',
    () async {
      final report = checkOf(
        await writeCheckProject(
          extra: fr(
            'status: implemented\n',
            'status: implemented\napproved:\n',
          ),
          unstamped: {'docs/$loginFr'},
        ),
      );
      expect(spots(report, FindingKind.approvalStale), [
        '$loginFr:3: approval_stale',
      ]);
      final finding = _stales(report).single;
      expect(finding.message, _unapproved);
      expect(finding.keys, isEmpty);
    },
  );

  test(
    '$_name: a tree pinned below both pins raises nothing for approved: true docs or docs with no approved: key',
    () async {
      final report = await _checkBelowPins({
        'docs/$loginFr': checkProjectFiles()['docs/$loginFr']!.replaceFirst(
          'status: implemented\n',
          'status: implemented\napproved: true\n',
        ),
        'docs/$loginStory': checkProjectFiles()['docs/$loginStory']!,
      });
      expect(_stales(report), isEmpty);
    },
  );
}
