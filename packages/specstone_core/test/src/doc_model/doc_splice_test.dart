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
  test('f02/us01/fr01, PD11, H25: a section added at the end of a doc ending in a blank line follows exactly one blank line', () {
    expect(
      withSectionAdded('# T\n\n## A\na\n\n', headerLine: '## R', body: 'r'),
      '# T\n\n## A\na\n\n## R\nr\n',
    );
    expect(
      withSectionAdded('# T\n\n## A\na\n\n\n', headerLine: '## R', body: 'r'),
      '# T\n\n## A\na\n\n## R\nr\n',
    );
  });
  test('f02/us01/fr01, PD5, H24: trailing blank lines go from the first newline of the whitespace tail', () {
    expect(withoutTrailingBlankLines('a\n \n\t'), 'a');
    expect(withoutTrailingBlankLines('a  \n'), 'a  ');
    expect(withoutTrailingBlankLines('a'), 'a');
    expect(withoutTrailingBlankLines('  \n '), '  ');
    expect(withoutTrailingBlankLines('\n'), '');
    expect(withoutTrailingBlankLines('a\t'), 'a\t');
  });
  test('dw-s03/inv13: review focus 2: a ## line inside a fence is no section, so no splice lands on it', () {
    const fenced = '# T\n\n## A\n```\n## B\n```\n\n## B\nreal\n';
    final parsed = Doc.parse(fenced);
    expect(parsed.sectionLineIndexes, [2, 7]);
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
  test(
    'doc_model/s03/inv6, HD4: withKeyBlock replaces a quoted block by its name',
    () {
      const quoted = '---\n"a": 1\nb: 2\n---\n# T\n';
      expect(
        withKeyBlock(quoted, 'a', 'a: 9\n'),
        '---\na: 9\nb: 2\n---\n# T\n',
      );
      expect(withKeyBlock(quoted, 'a', null), '---\nb: 2\n---\n# T\n');
    },
  );
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

  test('f02/us02/fr02: with fieldOrder an absent key lands at its slot and no block moves', () {
    const text = '---\nb: 1\nd: 2\n---\n';
    const order = ['a', 'b', 'c', 'd'];
    expect(
      withKeyBlock(text, 'c', 'c: 3\n', fieldOrder: order),
      '---\nb: 1\nc: 3\nd: 2\n---\n',
    );
    expect(
      withKeyBlock(text, 'a', 'a: 0\n', fieldOrder: order),
      '---\na: 0\nb: 1\nd: 2\n---\n',
    );
    expect(
      withKeyBlock(text, 'z', 'z: 9\n', fieldOrder: order),
      '---\nb: 1\nd: 2\nz: 9\n---\n',
    );
  });
  test('f02/us02/fr02: with fieldOrder a key lands after the keyless block when no earlier key is held', () {
    expect(
      withKeyBlock(
        '---\nstray line\nd: 2\n---\n',
        'a',
        'a: 0\n',
        fieldOrder: ['a', 'd'],
      ),
      '---\nstray line\na: 0\nd: 2\n---\n',
    );
  });
  test(
    'f02/us02/fr02: with fieldOrder an existing key is replaced in place',
    () {
      expect(
        withKeyBlock(
          '---\nb: 1\nd: 2\n---\n',
          'b',
          'b: 7\n',
          fieldOrder: ['d', 'b'],
        ),
        '---\nb: 7\nd: 2\n---\n',
      );
    },
  );
}
