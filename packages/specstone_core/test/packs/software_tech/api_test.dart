import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

const _says = <String, List<String>>{
  'source_of_truth': ['OpenAPI', 'ApiDog'],
  'fr_trace': ['FR', 'operation', 'operationId', 'command'],
  'operations': [
    '###',
    '`<operation>` — FR-<NN>',
    'Request example',
    'Response example',
    'success',
    'error',
    'source of truth',
    'Errors',
    'Auth',
    '`none`',
    'Idempotent',
    'mutating',
    'no Why line',
  ],
  'compatibility': ['breaking', 'Rollout'],
};

void main() {
  late MergedDocType api;
  setUpAll(() async {
    api = prdCoreDocType(await resolveSoftwareTech(), 'api');
  });

  test('f03/us07/fr02: the FR trace guide names each FR by <story slug>/<fr '
      'slug>, the confirmed entry text', () {
    final description = sectionOf(api, 'fr_trace').description!;
    expect(
      description,
      allOf(contains('<story slug>/<fr slug>'), contains('`confirmed`')),
    );
  });

  test('f03/us07/fr01, f03/us07/fr01/e06: api sits under '
      'specs/f{nn}_{slug}/ with parent feature, the confirmed field, and four '
      'sections', () {
    expect(api.path, 'specs/f{nn}_{slug}/API.md');
    expect(api.parent, 'feature');
    expectOwnFields(api, const [
      FieldSpec('confirmed', FieldType.string, list: true),
    ]);
    expectSections(api, const [
      SectionSpec('source_of_truth', 'Source-of-truth'),
      SectionSpec('fr_trace', 'FR trace', required: true),
      SectionSpec('operations', 'Operations', required: true),
      SectionSpec('compatibility', 'Compatibility'),
    ]);
  });

  test('f03/us07/fr02, f03/us07/fr02/e01, f03/us07/fr02/e03, '
      'f03/us07/fr02/e04: the api guide', () {
    expectSpecGuide(api, title: '# <Feature name> API');
    expectSectionsSay(api, _says);
  });

  test('f03/us07/fr03: api caps 400 lines, bans no word, and cites its four '
      'sources', () {
    expectSpecLint(api);
  });
}
