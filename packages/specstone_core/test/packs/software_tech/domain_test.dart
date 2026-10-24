import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

const _says = <String, List<String>>{
  'entities': [
    'Entity',
    'Kind',
    'Identity',
    'Owns',
    'Refers to (by id)',
    'Notes',
  ],
  'value_objects': ['immutable'],
  'invariants': [
    'append-only',
    'never reused',
    'aggregate root',
    'immediate',
    'eventual',
    'timeout 10 s',
  ],
  'lifecycle': ['stateDiagram-v2', '4 or more states'],
  'commands_and_events': ['command', 'aggregate', 'event emitted'],
  'corrective_policies': ['eventual'],
  'terms': ['glossary'],
};

void main() {
  late MergedDocType domain;
  setUpAll(() async {
    domain = prdCoreDocType(await resolveSoftwareTech(), 'domain');
  });

  test('f03/us07/fr01, f03/us07/fr01/e06: domain sits under '
      'specs/f{nn}_{slug}/ with parent feature, no own field, and eight '
      'sections', () {
    expect(domain.path, 'specs/f{nn}_{slug}/DOMAIN.md');
    expect(domain.parent, 'feature');
    expectOwnFields(domain, const []);
    expectSections(domain, const [
      SectionSpec('entities', 'Entities', required: true),
      SectionSpec('value_objects', 'Value objects'),
      SectionSpec('invariants', 'Invariants', prefixId: 'INV-', required: true),
      SectionSpec('lifecycle', 'Lifecycle'),
      SectionSpec('data_touch', 'Data touch'),
      SectionSpec('commands_and_events', 'Commands and events'),
      SectionSpec('corrective_policies', 'Corrective policies'),
      SectionSpec('terms', 'Terms'),
    ]);
  });

  test('f03/us07/fr02, f03/us07/fr02/e01, f03/us07/fr02/e03, '
      'f03/us07/fr02/e04, f03/us07/fr02/e06: the domain guide', () {
    expectSpecGuide(domain, title: '# <Feature name> domain');
    expectSectionsSay(domain, _says);
  });

  test('f03/us07/fr03, f03/us07/fr03/e01: domain caps 400 lines, bans no '
      'word, and cites its four sources', () {
    expectSpecLint(domain);
  });
}
