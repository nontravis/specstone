// The expected texts are plan literals kept as written.

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/pattern_entry.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/prd_core.dart';

const _persona = 'prds/personas/reviewer/PERSONA.md';
const _reference = 'prds/references/court/REFERENCE.md';

Future<List<Finding>> _found(
  Map<String, String> edits,
  FindingKind kind,
) async {
  final report = checkOf(await writeCheckProject(extra: edits));
  return [
    for (final f in report.findings)
      if (f.kind == kind) f,
  ];
}

Future<List<Finding>> _banned(Map<String, String> edits) =>
    _found(edits, FindingKind.patternBanned);

Map<String, String> _storyLine(String line) => doc(
  loginStory,
  '- **so that** I reach my work',
  '- **so that** I reach my work\n$line',
);

List<Object?> _patterns(List<Finding> found) => [
  for (final f in found) f.toJson()['pattern'],
];

void main() {
  test(
    'f03/us06/fr03: a code span with a call in a story is code_identifier',
    () async {
      final found = await _banned(_storyLine('Calls `runCheck()`'));
      expect(_patterns(found), ['code_identifier']);
    },
  );

  test(
    'f03/us06/fr03: an enum value in a story is one error_code finding',
    () async {
      final found = await _banned(_storyLine('Shows `TEMPLATE_NOT_FOUND`'));
      expect(_patterns(found), ['error_code']);
    },
  );

  test('f03/us06/fr03: a link to a USER_STORY file is no error_code, a final '
      'enum value is', () async {
    final link = await _banned(
      _storyLine('See [reset](../us02_reset_password/USER_STORY.md)'),
    );
    expect(_patterns(link), isNot(contains('error_code')));
    final enumValue = await _banned(
      _storyLine('The step fails with TEMPLATE_NOT_FOUND.'),
    );
    expect(_patterns(enumValue), contains('error_code'));
  });

  test(
    'f03/us06/fr03: a story citing ids and a slug in backticks gives none',
    () async {
      final found = await _banned(
        _storyLine('Follows `us01/fr02` and `f04_consistency_check`'),
      );
      expect(found, isEmpty);
    },
  );

  test(
    'f03/us06/fr03: a plan citation in an FR rationale is doc_citation',
    () async {
      final found = await _banned(
        fr(
          'A wrong password must not sign in.',
          'A wrong password must not sign in, per F4-R7.',
        ),
      );
      expect(_patterns(found), ['doc_citation']);
    },
  );

  test('f03/us06/fr03: a project goal By milestone and a court ruling give '
      'no doc_citation', () async {
    final found = await _banned({
      ...doc(
        projectDoc,
        'Halve the password resets.',
        'Halve the password resets.\n**By:** milestone',
      ),
      'docs/$_reference': '# Court\n\n## Summary\nThe court ruling stands.\n',
    });
    expect(_patterns(found), isNot(contains('doc_citation')));
  });

  test(
    'f03/us06/fr03: a persona line Formerly a reviewer is history',
    () async {
      final found = await _banned({
        'docs/$_persona': '# Reviewer\n\n## Snapshot\nFormerly a reviewer.\n',
      });
      expect(_patterns(found), ['history']);
    },
  );

  test(
    'f03/us06/fr03: a story with only happy scenarios is error_case',
    () async {
      final report = checkOf(
        await writeCheckProject(
          extra: doc(loginStory, '\n\n$loginScenario2', ''),
        ),
      );
      final found = [
        for (final f in report.findings)
          if (f.kind == FindingKind.patternMissing) f,
      ];
      expect(_patterns(found), ['error_case']);
    },
  );

  test('f03/us06/fr03: a feature with neither vision nor goals is '
      'field_group_missing', () async {
    final found = await _found(
      doc(
        loginFeature,
        '---\nvision:\n  - PV-01\ngoals:\n  - PG-01\n---\n\n',
        '',
      ),
      FindingKind.fieldGroupMissing,
    );
    expect(found, hasLength(1));
  });

  test('f03/us06/fr03: a project layer removing code_identifier silences '
      'it', () async {
    final found = await _banned({
      ..._storyLine('Calls `runCheck()`'),
      '.specstone/templates/user_story.yaml':
          'lint:\n  banned_patterns:\n    remove: [code_identifier]\n',
    });
    expect(found, isEmpty);
  });

  test('f03/us06/fr03: every prd-core type but reference carries the same '
      'doc_citation and history, and reference carries neither', () async {
    final set = await resolvePrdCore();
    String? citation;
    String? history;
    for (final type in set.docTypes) {
      final byId = {
        for (final p in type.lint.bannedPatterns ?? const <PatternEntry>[])
          p.id: p.pattern,
      };
      if (type.id == 'reference') {
        expect(byId.keys, isNot(contains('doc_citation')));
        expect(byId.keys, isNot(contains('history')));
        continue;
      }
      expect(byId['doc_citation'], isNotNull, reason: type.id);
      expect(byId['history'], isNotNull, reason: type.id);
      citation ??= byId['doc_citation'];
      history ??= byId['history'];
      expect(byId['doc_citation'], citation, reason: type.id);
      expect(byId['history'], history, reason: type.id);
    }
    expect(set.docTypes.where((t) => t.id != 'reference'), hasLength(10));
  });
}
