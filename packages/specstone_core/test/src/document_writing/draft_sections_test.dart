// A test name is one literal so the sync matrix reads it whole.

import 'package:specstone_core/src/document_writing/draft_sections.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

const _type = MergedDocType(
  id: 'fr',
  fields: [],
  sections: [
    MergedSection(id: 'rules', header: 'Rules'),
    MergedSection(id: 'rationale', header: 'Rationale'),
  ],
  lint: MergedLint(),
  files: [],
);

String _doc({
  String title = 'T',
  String field = 'one',
  String rules = '1. A.',
  String rationale = 'Why.',
}) =>
    '---\nowner: $field\n---\n\n# $title\n\n## Rules\n\n$rules\n\n'
    '## Rationale\n\n$rationale\n';

void main() {
  test(
    'lists the sections whose text differs from the audited copy in doc order',
    () {
      final delta = draftDeltaOf(
        _doc(rules: '1. B.', rationale: 'Other.'),
        _doc(),
        null,
      );
      expect(delta.changedSections, ['rules', 'rationale']);
      expect(delta.changesOutsideSections, isFalse);

      final one = draftDeltaOf(_doc(rationale: 'Other.'), _doc(), null);
      expect(one.changedSections, ['rationale']);
    },
  );

  test('a layout-only change lists no section', () {
    const tidy = '# T\n\n## Rules\n\n1. A.\n\n## Rationale\n\nWhy.\n';
    const loose = '# T\n\n\n## Rules\n\n1. A.\n\n\n\n## Rationale\n\nWhy.   \n';
    final delta = draftDeltaOf(loose, tidy, _type);
    expect(delta.changedSections, isEmpty);
    expect(delta.changesOutsideSections, isFalse);
  });

  test('an approval mark is no change', () {
    final marked = _doc().replaceFirst('owner: one', 'owner: one\ndraft: x');
    final delta = draftDeltaOf(marked, _doc(), null);
    expect(delta.changedSections, isEmpty);
    expect(delta.changesOutsideSections, isFalse);
  });

  test('a changed title or hashed field is a change outside the sections', () {
    final title = draftDeltaOf(_doc(title: 'U'), _doc(), null);
    expect(title.changesOutsideSections, isTrue);
    expect(title.changedSections, isEmpty);

    final field = draftDeltaOf(_doc(field: 'two'), _doc(), null);
    expect(field.changesOutsideSections, isTrue);
    expect(field.changedSections, isEmpty);
  });

  test('no audited copy lists every section and a change outside them', () {
    final delta = draftDeltaOf(_doc(), null, null);
    expect(delta.changedSections, ['rules', 'rationale']);
    expect(delta.changesOutsideSections, isTrue);
  });

  test('equal text ignores whitespace runs, quote marks, and list numbers', () {
    expect(
      sameByEqualText('1. One   two.\n2. Three.', '7. One two.\n8. Three.'),
      isTrue,
    );
    expect(sameByEqualText('> One   two.\n', 'One two.\n'), isTrue);
    expect(sameByEqualText('1. One.', '1. Two.'), isFalse);
    expect(sameByEqualText('1. One.', '1. One.\n2. Two.'), isFalse);
  });

  test('equal text compares the whole body when a fence holds lines', () {
    const graphA = '1. A.\n\n```mermaid\ngraph LR\n  A --> B\n```\n';
    const graphB = '1. A.\n\n```mermaid\ngraph LR\n  A --> C\n```\n';
    expect(sameByEqualText(graphA, graphB), isFalse);
    expect(sameByEqualText('```\nx\n```', '```\ny\n```'), isFalse);
    expect(sameByEqualText(graphA, graphA.replaceAll('  ', ' ')), isTrue);
  });

  test('equal text compares the whole body when a table header differs', () {
    const left = '| A | B |\n|---|---|\n| 1 | 2 |\n';
    const right = '| C | D |\n|---|---|\n| 1 | 2 |\n';
    expect(sameByEqualText(left, right), isFalse);
  });

  test('a repeated section key is a change outside the sections', () {
    const twice = '# T\n\n## Rules\n\nA.\n\n## Rules\n\nX.\n';
    final current = draftDeltaOf(twice.replaceFirst('X.', 'Y.'), twice, null);
    expect(current.changesOutsideSections, isTrue);
    const once = '# T\n\n## Rules\n\nA.\n\n## Rationale\n\nX.\n';
    expect(draftDeltaOf(twice, once, null).changesOutsideSections, isTrue);
  });
}
