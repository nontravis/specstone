import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:test/test.dart';

void main() {
  test('dw-s03/inv1: a base is the first 12 hex characters of the SHA-256 of the UTF-8 text', () {
    expect(baseHashOf(''), 'e3b0c44298fc');
    expect(emptyBaseHash, baseHashOf(''));
    expect(baseHashOf('abc'), 'ba7816bf8f01');
    expect(baseHashOf('ค้นหา\n'), 'caa1446653a9');
  });

  const doc = '---\na: 1\nb: 2\n---\n\n# T\n\n## A\nold\n\n## B\nb\n';
  test('dw-s03/inv13: a body is replaced, its header and spacing kept, a final newline added', () {
    expect(
      withSectionBody(doc, 0, 'new'),
      '---\na: 1\nb: 2\n---\n\n# T\n\n## A\nnew\n\n## B\nb\n',
    );
    expect(
      withSectionBody(doc, 1, 'x'),
      '---\na: 1\nb: 2\n---\n\n# T\n\n## A\nold\n\n## B\nx\n',
    );
  });
  test('dw-s03/inv13: a section is removed through the line before the next header', () {
    expect(withoutSection(doc, 0), '---\na: 1\nb: 2\n---\n\n# T\n\n## B\nb\n');
    expect(
      withoutSection(doc, 1),
      '---\na: 1\nb: 2\n---\n\n# T\n\n## A\nold\n\n',
    );
  });
  test(
    'dw-s03/inv13: a section is added before a later one, or at the end',
    () {
      expect(
        withSectionAdded(doc, headerLine: '## R', body: 'r', before: 1),
        '---\na: 1\nb: 2\n---\n\n# T\n\n## A\nold\n\n## R\nr\n\n## B\nb\n',
      );
      expect(
        withSectionAdded('# T\n\n## A\na', headerLine: '## R', body: 'r\n'),
        '# T\n\n## A\na\n\n## R\nr\n',
      );
    },
  );
  test('dw-s03/inv13: review focus 2: a ## line inside a fence is no section, so no splice lands on it', () {
    const fenced = '# T\n\n## A\n```\n## B\n```\n\n## B\nreal\n';
    final parsed = Doc.parse(fenced);
    expect(sectionLineIndexes(parsed), [2, 7]);
    expect(
      withSectionBody(fenced, 1, 'x\n'),
      '# T\n\n## A\n```\n## B\n```\n\n## B\nx\n',
    );
    expect(
      withSectionAdded(fenced, headerLine: '## R', body: 'r\n', before: 1),
      '# T\n\n## A\n```\n## B\n```\n\n## R\nr\n\n## B\nreal\n',
    );
  });
  test('dw-s03/inv14: a key block is replaced, added after the last one, or removed', () {
    expect(
      withKeyBlock(doc, 'a', 'a: 9\n'),
      '---\na: 9\nb: 2\n---\n\n# T\n\n## A\nold\n\n## B\nb\n',
    );
    expect(
      withKeyBlock(doc, 'c', 'c:\n  - x\n'),
      '---\na: 1\nb: 2\nc:\n  - x\n---\n\n# T\n\n## A\nold\n\n## B\nb\n',
    );
    expect(
      withKeyBlock(doc, 'a', null),
      '---\nb: 2\n---\n\n# T\n\n## A\nold\n\n## B\nb\n',
    );
    expect(
      withKeyBlock('# T\n', 'draft', 'draft: true\n'),
      '---\ndraft: true\n---\n# T\n',
    );
  });
  test('dw-s03/inv14: removing the only key block keeps the delimiters with nothing between', () {
    expect(
      withKeyBlock('---\ndraft: true\n---\n# T\n', 'draft', null),
      '---\n---\n# T\n',
    );
  });
  test('dw-s03/inv14: a block is added to frontmatter that holds no key', () {
    expect(
      withKeyBlock('---\n---\n# T\n', 'approved', 'approved: true\n'),
      '---\napproved: true\n---\n# T\n',
    );
  });
  test('dw-s03/inv14: the title text is replaced, or a title line added after the frontmatter', () {
    expect(
      withTitle(doc, 'New'),
      '---\na: 1\nb: 2\n---\n\n# New\n\n## A\nold\n\n## B\nb\n',
    );
    expect(
      withTitle('---\na: 1\n---\n\n## A\nx\n', 'New'),
      '---\na: 1\n---\n# New\n\n## A\nx\n',
    );
  });
}
