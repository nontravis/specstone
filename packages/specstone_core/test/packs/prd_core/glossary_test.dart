import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/document_writing/new_doc.dart'
    show answerNew;
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/prd_core.dart';
import '../../helpers/write_fixture.dart'
    show readDoc, writeIn, writeWriteProject;

const _glossaryDoc = 'prds/GLOSSARY.md';

Future<List<String>> _glossarySpots(String text) async {
  final report = await checkOf(
    await writeCheckProject(extra: {'docs/$_glossaryDoc': text}),
  );
  return [
    for (final f in report.findings)
      if (f.path == _glossaryDoc) '${f.line}: ${f.kind.wire}',
  ];
}

const glossaryDoc = 'prds/GLOSSARY.md';

const _citeFragment = 'by a link to its item, never restate it';

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

  test('the guide prints the glossary rules, then the shared cite line', () {
    final guide = glossary.renderGuide();
    final cite = guide.indexOf(_citeFragment);
    for (final rule in [
      'Write one bullet per term',
      'A project has exactly one glossary doc',
    ]) {
      expect(guide.indexOf(rule), allOf(isNonNegative, lessThan(cite)));
    }
    expect(glossary.description, isNot(contains(_citeFragment)));
    expect(glossary.sharedLines.map((l) => l.id), contains('cite_by_link'));
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

  test('new glossary with no stdin writes the bare Terms header', () async {
    final root = await writeWriteProject();

    final answer = writeIn(root, (s) => answerNew(s, docTypeId: 'glossary'));

    expect(answer.exitStatus, 0);
    final text = readDoc(root, _glossaryDoc);
    expect(text, endsWith('\n## Terms\n'));
    expect(text, isNot(contains('- **')));
  });

  test('a glossary doc whose terms section holds no entry gives no '
      'finding', () async {
    expect(await _glossarySpots('# Domain glossary\n\n## Terms\n'), isEmpty);
    expect(
      await _glossarySpots(
        '# Domain glossary\n\n## Terms\n\n- **Long** — ${'x' * 301}\n',
      ),
      contains(endsWith('item_over_limit')),
    );
  });

  test('duplicate terms and unordered entries give no finding', () async {
    expect(
      await _glossarySpots(
        '# Domain glossary\n\n## Terms\n\n'
        '- **Zeta** — the last term of the project.\n'
        '- **Alpha** — the first term of the project.\n'
        '- **Alpha** — the same term written twice.\n',
      ),
      isEmpty,
    );
  });
}
