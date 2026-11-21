import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/pattern_findings.dart';
import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

void main() {
  late MergedDocType api;
  setUpAll(() async {
    api = prdCoreDocType(await resolveSoftwareTech(), 'api');
  });

  test('api sits under '
      'specs/f{nn}_{slug}/ with parent feature, the confirmed field, and four '
      'sections', () {
    expect(api.path, 'specs/f{nn}_{slug}/API.md');
    expect(api.parent, 'feature');
    expectOwnFields(api, const [
      FieldSpec('confirmed', FieldType.string, list: true),
      FieldSpec('overrides', FieldType.string, list: true),
      FieldSpec('tasks', FieldType.taskRef, list: true),
    ]);
    expectSections(api, const [
      SectionSpec('source_of_truth', 'Source-of-truth'),
      SectionSpec('fr_trace', 'FR trace', required: true),
      SectionSpec('operations', 'Operations', required: true),
      SectionSpec('compatibility', 'Compatibility'),
    ]);
  });
  test('the operations description states one heading shape, with no FR '
      'label', () {
    final description = api.sections
        .singleWhere((s) => s.id == 'operations')
        .description;

    expect(
      description,
      contains(
        'one `###` per operation, headed `` `<operation>` `` alone '
        'with no FR label',
      ),
    );
  });

  test('operations carry no response example lint', () {
    final operations = sectionOf(api, 'operations');

    expect(
      [for (final p in operations.requiredPatterns!) p.id],
      ['errors_line', 'auth_line'],
    );
    expect(
      [for (final p in operations.bannedPatterns!) p.id],
      ['operation_heading', 'why_line'],
    );
    expect(
      operations.description?.split('\n'),
      contains(
        'Write a success and an error Response example, valid against the '
        'source of truth, only in a doc that holds that section.',
      ),
    );
  });

  test('the operations guide asks a code list per operation', () {
    expect(
      sectionOf(api, 'operations').description,
      allOf(
        contains('`**Errors:** <codes>; see <links>`'),
        contains('every code the operation returns as a code span'),
        contains("hand off to no other operation's list"),
        contains('`**Errors:** none`'),
      ),
    );
  });

  group('the operation lines', () {
    const apiPath = 'specs/f01_login/API.md';
    const noWhy = '**Errors:** none\n**Auth:** none\n';

    Map<String, String> apiDoc(String operations) => {
      'docs/$apiPath':
          '---\ndraft: true\n---\n\n# Login API\n\n'
          '## Operations\n\n$operations',
    };

    test('a Why line under an operation is why_line, and a fenced Why line, '
        'a table line, and a blank line give none', () async {
      Future<List<String>> flagged(String body) => bannedLines(
        apiDoc('### `signIn`\n\n$noWhy$body'),
        apiPath,
        'why_line',
      );

      expect(await flagged('**Why:** users wait\n'), ['**Why:** users wait']);
      expect(await flagged('- **Why:** users wait\n'), [
        '- **Why:** users wait',
      ]);
      expect(
        await flagged(
          '\n| Field | Why |\n|---|---|\n```text\n**Why:** users wait\n```\n',
        ),
        isEmpty,
      );
    });

    test('an operation with the dash Errors or Auth form, or none, gets '
        'errors_line or auth_line at its own heading', () async {
      Future<List<String>> missing(String operations) =>
          missingPatterns(apiDoc(operations), apiPath);

      expect(await missing('### `signIn`\n\n$noWhy'), isEmpty);
      const both = ['errors_line @ `signIn`', 'auth_line @ `signIn`'];
      expect(
        await missing('### `signIn`\n\n**Errors** — none\n**Auth** — none\n'),
        unorderedEquals(both),
      );
      expect(
        await missing('### `signIn`\n\nSigns the Agent in.\n'),
        unorderedEquals(both),
      );
    });

    test('the second operation alone lacking a line is the only finding, and '
        'an Errors line of codes and groups passes', () async {
      expect(
        await missingPatterns(
          apiDoc(
            '### `signIn`\n\n'
            '**Errors:** `wrong_password`; see [error:login](ERROR.md)\n'
            '**Auth:** `login:write`\n\n'
            '### `signOut`\n\n'
            '**Errors:** the `session_fault` codes, `no_session`; '
            'see [error:login](ERROR.md)\n\n'
            '### `refresh`\n\n$noWhy',
          ),
          apiPath,
        ),
        ['auth_line @ `signOut`'],
      );
    });

    test('the operations description names the colon Auth form and the group '
        'form of the Errors line', () {
      expect(
        sectionOf(api, 'operations').description,
        allOf(
          contains('Write Auth as `**Auth:** <scope or none>`'),
          contains('Write one Errors line'),
          contains(
            '``**Errors:** the `<group>` codes, `<code>`, …; see <links>``',
          ),
          contains('only when the operation returns every code of the group'),
          contains('Write no Why line'),
        ),
      );
    });

    test('each message names a guide line the description prints', () {
      final operations = sectionOf(api, 'operations');
      final messages = {
        for (final p in [
          ...operations.bannedPatterns!,
          ...operations.requiredPatterns!,
        ])
          p.id: p.message,
      };

      expect(messages['why_line'], endsWith('guide line: Write no Why line'));
      expect(
        messages['errors_line'],
        endsWith('guide line: Write one Errors line'),
      );
      expect(
        messages['auth_line'],
        endsWith('guide line: **Auth:** <scope or none>'),
      );
    });
  });

  test('an API.md or an ERROR.md over 50000 characters gets chars_over_limit, '
      'limit 50000', () async {
    const draft = '---\ndraft: true\n---\n\n';
    for (final (file, title) in [
      ('API.md', '# Login API\n'),
      ('ERROR.md', '# Login errors\n'),
    ]) {
      final docPath = 'docs/specs/f01_login/$file';
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            docPath:
                '$draft$title'
                '${'x' * (50001 - draft.length - title.length - 2)}',
          },
        ),
      );

      final json = report.findings
          .singleWhere((f) => f.kind == FindingKind.charsOverLimit)
          .toJson();
      expect(
        json,
        allOf(containsPair('limit', 50000), containsPair('actual', 50001)),
        reason: file,
      );
    }
  });
}
