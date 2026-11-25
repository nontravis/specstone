import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/guide_limits.dart';
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
      'specs/f{nn}_{slug}/ with parent feature, the confirmed field, and five '
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
      SectionSpec('errors', 'Errors'),
      SectionSpec('compatibility', 'Compatibility'),
    ]);
  });

  test('the api description carries the Library block line', () {
    expect(
      api.description,
      contains(
        'Write a Library block only for a symbol another code base calls; '
        "an internal symbol's signature goes in the plan.",
      ),
    );
  });

  test('errors and the project error model carry the catalog and the '
      'two one-sentence column caps', () async {
    final projectApi = prdCoreDocType(
      await resolveSoftwareTech(),
      'project_api',
    );

    for (final section in [
      sectionOf(api, 'errors'),
      sectionOf(projectApi, 'error_model'),
    ]) {
      expect(section.catalog!.column, 'Code', reason: section.id);
      expect(
        [for (final c in section.maxSentences!) (c.count, c.column)],
        [(1, 'Condition'), (1, 'Client action')],
        reason: section.id,
      );
    }
  });

  test('operations caps each operation at 2 code blocks and the guide line '
      'says so', () {
    final operations = sectionOf(api, 'operations');

    expect(operations.maxCodeBlocks?.count, 2);
    expect(operations.maxCodeBlocks?.perSubsection, isTrue);
    expect(
      sectionLimitsClause(operations),
      'in each subsection, ≤ 2 code blocks',
    );
  });

  test('api lists its sources per style in table order, then the error '
      'sources', () {
    for (final r in api.reference!) {
      expect(r.url, startsWith('https://'), reason: r.title);
      expect(r.locator, isNotEmpty, reason: r.title);
    }
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
            '**Errors:** `wrong_password`; see [api:login](API.md#errors)\n'
            '**Auth:** `login:write`\n\n'
            '### `signOut`\n\n'
            '**Errors:** the `session_fault` codes, `no_session`; '
            'see [api:login](API.md#errors)\n\n'
            '### `refresh`\n\n$noWhy',
          ),
          apiPath,
        ),
        ['auth_line @ `signOut`'],
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

  test(
    'an API.md over 50000 characters gets chars_over_limit, limit 50000',
    () async {
      const draftMark = 'draft: true\n';
      const draft = '---\n$draftMark---\n\n';
      // The count leaves the draft mark out, so the file holds its length more.
      const counted = 50001 + draftMark.length - draft.length;
      const title = '# Login API\n';
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            'docs/specs/f01_login/API.md':
                '$draft$title'
                '${'x' * (counted - title.length - 2)}',
          },
        ),
      );

      final json = report.findings
          .singleWhere((f) => f.kind == FindingKind.charsOverLimit)
          .toJson();
      expect(
        json,
        allOf(containsPair('limit', 50000), containsPair('actual', 50001)),
      );
    },
  );
}
