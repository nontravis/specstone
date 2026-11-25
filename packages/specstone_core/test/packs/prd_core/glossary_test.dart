import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/document_writing/new_doc.dart'
    show answerNew;
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/pattern_findings.dart';
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

const _citeFragment =
    'Link to the item of a rule another doc owns; never restate it';

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

  test('the glossary doc type holds its fixed title and its description '
      'states none', () {
    expect(glossary.title, 'Domain glossary');
    expect(glossary.description, isNot(contains('Title it')));
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

  group('the term form and the title', () {
    Future<List<String>> flagged(List<String> lines) => bannedLines(
      {
        'docs/$_glossaryDoc':
            '# Domain glossary\n\n## Terms\n\n${lines.join('\n')}\n',
      },
      _glossaryDoc,
      'term_bullet_form',
    );

    test('a bullet in the template form gives no finding', () async {
      expect(
        await flagged([
          '- **Agent** — the coding agent that writes the docs.',
          '- **C++ code** — the `src/` files.',
          '- **Doc type** — a kind of doc: a path, sections, and lint.',
        ]),
        isEmpty,
      );
    });

    test('a bullet with a hyphen for the em dash, with no bold term, with a '
        'star marker, or with no definition gives term_bullet_form', () async {
      const loose = [
        '- **Agent** - the coding agent.',
        '- Agent — the coding agent.',
        '* **Agent** — the coding agent.',
        '- **Agent**— the coding agent.',
        '- **Agent** — ',
        '- **Agent**',
      ];

      expect(await flagged(loose), loose);
    });

    test('a wrapped line, a blank line, a table line, and a fenced line give '
        'no finding', () async {
      expect(
        await flagged([
          '- **Agent** — the coding agent',
          '  that writes the docs.',
          '',
          '| Term | Meaning |',
          '```text',
          '- Agent - plain',
          '```',
        ]),
        isEmpty,
      );
    });

    test('a title holding a digit is title_numbered', () async {
      Future<List<String>> spots(String title) =>
          _glossarySpots('$title\n\n## Terms\n');

      expect(await spots('# Domain glossary 2'), [
        endsWith(': title_fixed_mismatch'),
        endsWith(': title_numbered'),
      ]);
      expect(await spots('# Domain glossary'), isEmpty);
      expect(glossary.lint.titleNoNumber, isTrue);
    });
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
