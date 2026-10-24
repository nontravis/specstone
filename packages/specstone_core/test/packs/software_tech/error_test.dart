import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

const _says = <String, List<String>>{
  'error_envelope': ['envelope', 'differs'],
  'error_catalog': [
    'Code',
    'Exit/HTTP',
    'Category',
    'Triggered by',
    'Implemented by',
    'Client guidance',
    'Details',
    'retry_after',
    'never reused',
  ],
  'retry_policy': ['category', 'per-code', 'non-idempotent'],
};

void main() {
  late MergedDocType error;
  setUpAll(() async {
    error = prdCoreDocType(await resolveSoftwareTech(), 'error');
  });

  test('f03/us07/fr01, f03/us07/fr01/e06: error sits under '
      'specs/f{nn}_{slug}/ with parent feature, no own field, and four '
      'sections', () {
    expect(error.path, 'specs/f{nn}_{slug}/ERROR.md');
    expect(error.parent, 'feature');
    expectOwnFields(error, const []);
    expectSections(error, const [
      SectionSpec('error_envelope', 'Error envelope'),
      SectionSpec('error_catalog', 'Error catalog', required: true),
      SectionSpec('retry_policy', 'Retry policy', required: true),
      SectionSpec('fallback', 'Fallback'),
    ]);
  });

  test('f03/us07/fr02, f03/us07/fr02/e01, f03/us07/fr02/e03, '
      'f03/us07/fr02/e04, f03/us07/fr02/e08: the error guide', () {
    expectSpecGuide(
      error,
      title: '# <Feature name> errors',
      says: ['no stack trace or internals'],
    );
    expectSectionsSay(error, _says);
  });

  test('f03/us07/fr03: error caps 400 lines, bans no word, and cites its '
      'four sources', () {
    expectSpecLint(error);
  });
}
