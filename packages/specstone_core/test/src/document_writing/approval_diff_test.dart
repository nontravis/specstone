import 'package:specstone_core/src/document_writing/approval_diff.dart';
import 'package:test/test.dart';

const _old =
    '---\nverify_method: test\n---\n\n# FR-01 — T\n\n'
    '## Statement\nA.\n\n## Rationale\nR.\n';
const _new =
    '---\nverify_method: demonstration\n---\n\n# FR-01 — T\n\n'
    '## Statement\nA.\n\n## Rationale\nR2.\n';

void main() {
  group('approvalDiff', () {
    test('f02/us03/fr02/e08, e10: unit context shows each changed unit whole and no other', () {
      expect(
        approvalDiff(_old, _new),
        '@@ -1,3 +1,3 @@\n ---\n-verify_method: test\n'
        '+verify_method: demonstration\n ---\n'
        '@@ -10,2 +10,2 @@\n ## Rationale\n-R.\n+R2.\n',
      );
    });

    test('f02/us03/fr02/e14: context 0 gives zero-context hunks', () {
      expect(
        approvalDiff(_old, _new, context: 0),
        '@@ -2 +2 @@\n-verify_method: test\n+verify_method: demonstration\n'
        '@@ -11 +11 @@\n-R.\n+R2.\n',
      );
    });

    test('f02/us03/fr02/e14, dw-s03/inv11: context 0 names the lines that differ and carries no context', () {
      expect(
        approvalDiff('a\nb\nc\n', 'a\nB\nc\n', context: 0),
        '@@ -2 +2 @@\n-b\n+B\n',
      );
      expect(
        approvalDiff('a\nc\n', 'a\nb\nc\n', context: 0),
        '@@ -1,0 +2 @@\n+b\n',
      );
      expect(
        approvalDiff('a\nb\nc\n', 'a\nc\n', context: 0),
        '@@ -2 +1,0 @@\n-b\n',
      );
      expect(approvalDiff('a\n', 'a\n', context: 0), '');
    });

    test('f02/us03/fr02/e14, dw-s03/inv11: context 0 joins separate changes and reads CRLF as LF', () {
      expect(
        approvalDiff('a\nb\nc\nd\ne\n', 'A\nb\nc\nd\nE\nF\n', context: 0),
        '@@ -1 +1 @@\n-a\n+A\n@@ -5 +5,2 @@\n-e\n+E\n+F\n',
      );
      expect(approvalDiff('a\r\nb\r\n', 'a\nb\n', context: 0), '');
      expect(approvalDiff('', 'a\n', context: 0), '@@ -0,0 +1 @@\n+a\n');
    });

    test('f02/us03/fr02/e14: context n gives n lines', () {
      expect(
        approvalDiff(_old, _new, context: 1),
        startsWith('@@ -1,3 +1,3 @@\n ---\n'),
      );
    });

    test(
      'f02/us03/fr02/e14: context n merges hunks whose shown lines touch',
      () {
        const before = 'a\nb\nc\nd\ne\nf\n';
        const after = 'A\nb\nc\nd\ne\nF\n';
        expect(
          approvalDiff(before, after, context: 1),
          '@@ -1,2 +1,2 @@\n-a\n+A\n b\n@@ -5,2 +5,2 @@\n e\n-f\n+F\n',
        );
        expect(
          approvalDiff(before, after, context: 2),
          '@@ -1,6 +1,6 @@\n-a\n+A\n b\n c\n d\n e\n-f\n+F\n',
        );
      },
    );

    test('f02/us03/fr02/e09: a ## inside a code fence bounds no unit', () {
      const before = '## A\n```\n## x\n```\nx\n## B\ny\n';
      const after = '## A\n```\n## x\n```\nX\n## B\ny\n';
      expect(
        approvalDiff(before, after),
        '@@ -1,5 +1,5 @@\n ## A\n ```\n ## x\n ```\n-x\n+X\n',
      );
    });

    test(
      'f02/us03/fr02/e08: a doc with no frontmatter and no section is one unit',
      () {
        expect(
          approvalDiff('# T\n\nbody\n', '# T\n\nbody2\n'),
          '@@ -1,3 +1,3 @@\n # T\n \n-body\n+body2\n',
        );
      },
    );

    test('f02/us03/fr02/e08: a changed head shows the head whole, not its sections', () {
      expect(
        approvalDiff('# T\n\nlead\n\n## S\nx\n', '# T\n\nlead2\n\n## S\nx\n'),
        '@@ -1,4 +1,4 @@\n # T\n \n-lead\n+lead2\n \n',
      );
    });

    test(
      'f02/us03/fr02/e08: a deleted section shows whole in the old text',
      () {
        expect(
          approvalDiff('## A\na\n## B\nb\n', '## A\na\n'),
          '@@ -3,2 +2,0 @@\n-## B\n-b\n',
        );
      },
    );

    test('f02/us03/fr02/e08: neighbouring changed units share one hunk', () {
      expect(
        approvalDiff('## A\na\n## B\nb\n', '## A\nA\n## B\nB\n'),
        '@@ -1,4 +1,4 @@\n ## A\n-a\n+A\n ## B\n-b\n+B\n',
      );
    });

    test('f02/us03/fr02/e08: equal texts give no hunk', () {
      expect(approvalDiff(_old, _old), '');
      expect(approvalDiff('', ''), '');
    });

    test(
      'f02/us03/fr02/e08: CRLF and LF texts with the same lines are equal',
      () {
        expect(approvalDiff('a\r\nb\r\n', 'a\nb\n'), '');
      },
    );
  });

  group('changedUnits', () {
    test(
      'f02/us03/fr02/e08: changed units name fields, title, lead, and sections',
      () {
        expect(changedUnits(_old, _new), [
          'field `verify_method`',
          '`## Rationale`',
        ]);
      },
    );

    test(
      'f02/us03/fr02/e08: a renamed header is one removed and one new unit',
      () {
        expect(changedUnits('## A\nx\n', '## B\nx\n'), [
          '`## A` (removed)',
          '`## B` (new)',
        ]);
      },
    );

    test('f02/us03/fr02/e08: a changed title is the title unit', () {
      expect(changedUnits('# T\n', '# U\n'), ['title']);
    });

    test('f02/us03/fr02/e08: a changed lead is the lead unit', () {
      expect(
        changedUnits('# T\n\nlead\n\n## S\nx\n', '# T\n\nlead2\n\n## S\nx\n'),
        ['lead'],
      );
    });

    test(
      'f02/us03/fr02/e08: a lead that appears or goes is new or removed',
      () {
        expect(changedUnits('# T\n\n## S\nx\n', '# T\n\nlead\n\n## S\nx\n'), [
          'lead (new)',
        ]);
        expect(changedUnits('# T\n\nlead\n\n## S\nx\n', '# T\n\n## S\nx\n'), [
          'lead (removed)',
        ]);
      },
    );

    test(
      'f02/us03/fr02/e08: a field that appears or goes is new or removed',
      () {
        expect(changedUnits('---\na: 1\n---\n', '---\na: 1\nb: 2\n---\n'), [
          'field `b` (new)',
        ]);
        expect(changedUnits('---\na: 1\nb: 2\n---\n', '---\na: 1\n---\n'), [
          'field `b` (removed)',
        ]);
      },
    );

    test(
      'f02/us03/fr02/e08: a doc gaining frontmatter lists its fields as new',
      () {
        expect(changedUnits('# T\n', '---\na: 1\nb: 2\n---\n# T\n'), [
          'field `a` (new)',
          'field `b` (new)',
        ]);
      },
    );

    test('f02/us03/fr02/e08: rows follow the new text and a removed unit sits after its predecessor', () {
      const before = '## A\na\n## B\nb\n## C\nc\n';
      const after = '## A\nA\n## C\nC\n';
      expect(changedUnits(before, after), [
        '`## A`',
        '`## B` (removed)',
        '`## C`',
      ]);
    });

    test('f02/us03/fr02/e08: a removed first unit comes first', () {
      expect(changedUnits('## A\na\n## B\nb\n', '## B\nb\n'), [
        '`## A` (removed)',
      ]);
      expect(changedUnits('## A\na\n## B\nb\n', '## B\nB\n'), [
        '`## A` (removed)',
        '`## B`',
      ]);
    });

    test('f02/us03/fr02/e09: a ## inside a code fence is no section', () {
      expect(
        changedUnits('## A\n```\n## x\n```\nx\n', '## A\n```\n## x\n```\nX\n'),
        ['`## A`'],
      );
    });

    test('f02/us03/fr02/e08: a change in spacing between sections names the section above', () {
      expect(changedUnits('## A\na\n## B\nb\n', '## A\na\n\n## B\nb\n'), [
        '`## A`',
      ]);
    });

    test('f02/us03/fr02/e08: equal texts, even in another line ending, change no unit', () {
      expect(changedUnits(_old, _old), isEmpty);
      expect(
        changedUnits('# T\r\n\r\n## A\r\nx\r\n', '# T\n\n## A\nx\n'),
        isEmpty,
      );
    });
  });
}
