import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/prd_core.dart';

const glossaryDoc = 'prds/GLOSSARY.md';

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

  test('the description states no number a lint key holds', () {
    final terms = sectionOf(glossary, 'terms');
    expect(glossary.description, isNot(contains('one line each')));
    expect(glossary.description, isNot(contains('300 characters')));
    expect(terms.description, isNot(contains('one line')));
    expect(terms.template, isNot(contains('one-line')));
  });

  test('terms carries its item line cap', () {
    expect(sectionOf(glossary, 'terms').maxItemLines, 1);
  });

  test('a term of two lines gets item_lines_over_limit', () async {
    Future<Directory> projectWith(String terms) => writeCheckProject(
      extra: {'docs/$glossaryDoc': '# Domain glossary\n\n## Terms\n\n$terms'},
    );

    final oneLine = await projectWith('- **Agent** — the coding agent.\n');
    expect(
      spots(await checkOf(oneLine), FindingKind.itemLinesOverLimit),
      isEmpty,
    );
    final twoLines = await projectWith(
      '- **Agent** — the coding agent\n  that writes the docs.\n',
    );
    final line = lineOfFirst(twoLines, glossaryDoc, '**Agent**');
    expect(spots(await checkOf(twoLines), FindingKind.itemLinesOverLimit), [
      '$glossaryDoc:$line: item_lines_over_limit',
    ]);
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
