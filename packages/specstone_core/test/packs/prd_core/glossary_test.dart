import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/pattern_entry.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';

const _termTemplate =
    '- **<Term>** — <one-line definition tying to a concrete entity>';

const _termsDescription =
    'Define each domain term in one line that ties it to a concrete entity.';

const _capRule =
    'Keep each entry to 300 characters or fewer; its mechanics go to the '
    'spec doc that owns them, cited by a link.';

const _sentenceRule =
    'Each sentence holds 25 words or fewer (Korean 17), or 100 characters '
    'in a script with no spaces (Japanese 60, Chinese 45).';

const _nestRule =
    'Keep one rule in each item, and put several conditions in a nested '
    'list. A one-sentence paragraph with no ID moves its detail to the '
    'section of the same doc that owns it, never into a sub-list.';

const _exampleRule =
    'Give a non-obvious rule one example inside its item, as a `such as` '
    'clause or one "For example," sentence, within the sentence\'s cap.';

const _orderRule =
    'State the condition first, then the rule, one clause chain per '
    'sentence; split a sentence whose clauses nest.';

const _rules = <String>[
  'A project has exactly one glossary doc.',
  'Write one bullet per term, in the section template form.',
  _capRule,
  'State the present truth; history lives in git.',
  _sentenceRule,
  _nestRule,
  "Put a cite or an ownership note at the item's end.",
  _exampleRule,
  _orderRule,
];

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

  test('the terms section is a skeleton and a query section with the '
      'term template and no summary', () {
    final terms = sectionOf(glossary, 'terms');
    expect(terms.skeleton, isTrue);
    expect(terms.query, isTrue);
    expect(terms.summary, isNull);
    expect(terms.template, _termTemplate);
    expect(terms.description, _termsDescription);
  });

  test('glossary is titled # Domain glossary, caps items at 300 characters, '
      'lines at 400, and the doc at 20000 characters, and carries the '
      'doc_citation and history entries with no word list or source', () {
    expectGuideShape(glossary, title: '# Domain glossary');
    expect(glossary.lint.maxItemChars, 300);
    expect(glossary.lint.maxLines, 400);
    expect(glossary.lint.maxChars, 20000);
    expectNoNasaLint(glossary);
    expectSources(glossary, []);
    expect(
      [for (final pattern in glossary.lint.bannedPatterns!) pattern.id],
      ['doc_citation', 'history'],
    );
    expect(
      [for (final pattern in glossary.lint.bannedPatterns!) pattern.scope],
      [PatternScope.all, PatternScope.text],
    );
    expect(glossary.lint.allowedWords, isNull);
    expect(glossary.lint.requiredFieldGroups, isNull);
    expect(glossary.lint.titleNoNumber, isNull);
  });

  test('the description states one rule per item in place of the ID rule, '
      'the glossary rules, the cite rule, and the readability bar', () {
    expectItemShape(
      glossary,
      'Write one rule per item, since the `terms` section holds no IDs, '
      'and leave mechanics to the spec docs.\n'
      'Cite a rule another doc owns by a link to the item that holds it, '
      'never restate it.',
    );
    final description = glossary.description!;
    expect(description, isNot(contains('one rule per ID')));
    for (final rule in _rules) {
      expect(description, contains(rule));
    }
  });
}
