import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/pattern_findings.dart';
import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

void main() {
  late MergedDocType integration;
  setUpAll(() async {
    integration = prdCoreDocType(await resolveSoftwareTech(), 'integration');
  });

  test('integration '
      'sits under specs/f{nn}_{slug}/ with parent feature, the overrides and tasks fields, and '
      'four sections, events optional', () {
    expect(integration.path, 'specs/f{nn}_{slug}/INTEGRATION.md');
    expect(integration.parent, 'feature');
    expectOwnFields(integration, const [
      FieldSpec('overrides', FieldType.string, list: true),
      FieldSpec('tasks', FieldType.taskRef, list: true),
    ]);
    expectSections(integration, const [
      SectionSpec('external_systems', 'External systems', required: true),
      SectionSpec('contract_per_system', 'Contract per system', required: true),
      SectionSpec('translation', 'Translation'),
      SectionSpec('events', 'Events'),
    ]);
  });

  group('the system and event lines', () {
    const integrationPath = 'specs/f01_login/INTEGRATION.md';

    Map<String, String> integrationDoc(String section, String body) => {
      'docs/$integrationPath':
          '---\ndraft: true\n---\n\n# Login integrations\n\n'
          '## $section\n\n$body',
    };

    test('a system with no Endpoints used header row, or a header with other '
        'columns, gets endpoints_used at its own heading', () async {
      const header =
          '| Direction | Method / Event | Purpose |\n|---|---|---|\n';
      Future<List<String>> missing(String systems) => missingPatterns(
        integrationDoc('Contract per system', systems),
        integrationPath,
      );

      expect(
        await missing('### Mailer\n\n$header| out | send | mail |\n'),
        isEmpty,
      );
      expect(await missing('### Mailer\n\nNo table here.\n'), [
        'endpoints_used @ Mailer',
      ]);
      expect(
        await missing(
          '### Mailer\n\n| Direction | Method / Event | Purpose | Notes |\n'
          '|---|---|---|---|\n',
        ),
        ['endpoints_used @ Mailer'],
      );
      expect(
        await missing(
          '### Mailer\n\n$header### Billing\n\nPlain text.\n\n'
          '### Search\n\n$header',
        ),
        ['endpoints_used @ Billing'],
      );
    });

    test('an Action cell other than send or receive is action_value, and the '
        'header, the separator, a blank line, and a fenced row pass', () async {
      const table =
          '| Event type | Channel | Action | Payload schema | Dedup key | '
          'Version rule |\n|---|---|---|---|---|---|\n';
      const sends = '| mail.sent | mail | send | schema | id | v1 |';
      const quoted = '| mail.read | mail | `receive` | schema | id | v1 |';
      const publishes = '| mail.bounced | mail | publish | schema | id | v1 |';
      const empty = '| mail.dropped | mail |  | schema | id | v1 |';

      expect(
        await bannedLines(
          integrationDoc(
            'Events',
            '$table$sends\n$quoted\n\n```text\n$publishes\n```\n',
          ),
          integrationPath,
          'action_value',
        ),
        isEmpty,
      );
      expect(
        await bannedLines(
          integrationDoc('Events', '$table$sends\n$publishes\n$empty\n'),
          integrationPath,
          'action_value',
        ),
        [publishes, empty],
      );
    });
  });
}
