import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

const _says = <String, List<String>>{
  'external_systems': ['System', 'Purpose', 'Protocol', 'Owned by'],
  'contract_per_system': [
    '###',
    'Endpoints used',
    'Credentials',
    'never a value',
    'Failure handling',
    'timeout',
    'retries',
    'backoff with jitter',
    'max attempts',
    'circuit breaker',
    'rate limit',
    'Idempotency',
    'key source',
    'duplicate',
    'expiry',
  ],
  'translation': ['anticorruption layer', 'domain'],
  'events': [
    'Event type',
    'Channel',
    'Action',
    'Payload schema',
    'Dedup key',
    'Version rule',
  ],
};

void main() {
  late MergedDocType integration;
  setUpAll(() async {
    integration = prdCoreDocType(await resolveSoftwareTech(), 'integration');
  });

  test('f03/us07/fr01, f03/us07/fr01/e05, f03/us07/fr01/e06: integration '
      'sits under specs/f{nn}_{slug}/ with parent feature, no own field, and '
      'four sections, events optional', () {
    expect(integration.path, 'specs/f{nn}_{slug}/INTEGRATION.md');
    expect(integration.parent, 'feature');
    expectOwnFields(integration, const []);
    expectSections(integration, const [
      SectionSpec('external_systems', 'External systems', required: true),
      SectionSpec('contract_per_system', 'Contract per system', required: true),
      SectionSpec('translation', 'Translation'),
      SectionSpec('events', 'Events'),
    ]);
  });

  test('f03/us07/fr02, f03/us07/fr02/e01, f03/us07/fr02/e03, '
      'f03/us07/fr02/e04, f03/us07/fr02/e07: the integration guide', () {
    expectSpecGuide(
      integration,
      title: '# <Feature name> integrations',
      says: ['only when the feature calls an outside system'],
    );
    expectSectionsSay(integration, _says);
  });

  test('f03/us07/fr03: integration caps 400 lines, bans no word, and cites '
      'its four sources', () {
    expectSpecLint(integration);
  });
}
