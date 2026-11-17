import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';

void main() {
  late MergedDocType glossary;
  setUpAll(() async {
    glossary = prdCoreDocType(await resolvePrdCore(), 'glossary');
  });

  test('glossary loads at its path with no parent, no own field, and the '
      'one optional terms section', () {
    expect(glossary.path, 'prds/GLOSSARY.md');
    expect(glossary.parent, isNull);
    expectOwnFields(glossary, const []);
    expectSections(glossary, const [SectionSpec('terms', 'Terms')]);
  });

  test('glossary joins the query, implement, and design bundles and sits '
      'in the refs file', () {
    expect(glossary.bundle, ['query', 'implement', 'design']);
    expect(glossary.bundleRefs, isTrue);
  });

  test('the terms section is a skeleton and a query section with no '
      'summary', () {
    final terms = sectionOf(glossary, 'terms');
    expect(terms.skeleton, isTrue);
    expect(terms.query, isTrue);
    expect(terms.summary, isNull);
  });
}
