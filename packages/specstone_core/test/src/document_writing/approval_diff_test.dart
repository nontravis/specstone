import 'package:specstone_core/src/document_writing/approval_diff.dart';
import 'package:test/test.dart';

const _old =
    '---\nverify_method: test\n---\n\n# FR-01 — T\n\n'
    '## Statement\nA.\n\n## Rationale\nR.\n';
const _new =
    '---\nverify_method: demonstration\n---\n\n# FR-01 — T\n\n'
    '## Statement\nA.\n\n## Rationale\nR2.\n';

ChangedUnit _field(String key, [UnitSide side = .both]) =>
    (kind: .field, name: key, side: side);

ChangedUnit _section(String header, [UnitSide side = .both]) =>
    (kind: .section, name: header, side: side);

/// A changed unit of a [kind] that has no key or header text.
ChangedUnit _bare(UnitKind kind, [UnitSide side = .both]) =>
    (kind: kind, name: '', side: side);

void main() {
  group('Show what changed since the last approval '
      'LineDiff', () {
    test('one diff shows the same hunks as approvalDiff for every context', () {
      final diff = LineDiff(_old, _new);

      for (final context in [null, 0, 1, 3]) {
        expect(
          diff.hunks(context: context),
          approvalDiff(_old, _new, context: context),
          reason: 'context $context',
        );
      }
    });

    test('is empty for texts that differ in no line and not otherwise', () {
      expect(LineDiff(_old, _old).isEmpty, isTrue);
      expect(LineDiff(_old, _old.trimRight()).isEmpty, isTrue);
      expect(LineDiff(_old, _new).isEmpty, isFalse);
      expect(LineDiff('', _new).isEmpty, isFalse);
    });

    test('refuses a negative context', () {
      expect(
        () => LineDiff(_old, _new).hunks(context: -1),
        throwsArgumentError,
      );
    });
  });

  group('approvalDiff', () {
    test('f02/us03/fr02/e08, e10: unit context shows each changed unit whole and no other', () {
      expect(
        approvalDiff(_old, _new),
        '@@ -1,3 +1,3 @@\n ---\n-verify_method: test\n'
        '+verify_method: demonstration\n ---\n'
        '@@ -10,2 +10,2 @@\n ## Rationale\n-R.\n+R2.\n',
      );
    });

    test('context 0 gives zero-context hunks', () {
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

    test('context n gives n lines', () {
      expect(
        approvalDiff(_old, _new, context: 1),
        startsWith('@@ -1,3 +1,3 @@\n ---\n'),
      );
    });

    test('context n merges hunks whose shown lines touch', () {
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
    });

    test('a ## inside a code fence bounds no unit', () {
      const before = '## A\n```\n## x\n```\nx\n## B\ny\n';
      const after = '## A\n```\n## x\n```\nX\n## B\ny\n';
      expect(
        approvalDiff(before, after),
        '@@ -1,5 +1,5 @@\n ## A\n ```\n ## x\n ```\n-x\n+X\n',
      );
    });

    test('a doc with no frontmatter and no section is one unit', () {
      expect(
        approvalDiff('# T\n\nbody\n', '# T\n\nbody2\n'),
        '@@ -1,3 +1,3 @@\n # T\n \n-body\n+body2\n',
      );
    });

    test('a changed head shows the head whole, not its sections', () {
      expect(
        approvalDiff('# T\n\nlead\n\n## S\nx\n', '# T\n\nlead2\n\n## S\nx\n'),
        '@@ -1,4 +1,4 @@\n # T\n \n-lead\n+lead2\n \n',
      );
    });

    test('a deleted section shows whole in the old text', () {
      expect(
        approvalDiff('## A\na\n## B\nb\n', '## A\na\n'),
        '@@ -3,2 +2,0 @@\n-## B\n-b\n',
      );
    });

    test('neighbouring changed units share one hunk', () {
      expect(
        approvalDiff('## A\na\n## B\nb\n', '## A\nA\n## B\nB\n'),
        '@@ -1,4 +1,4 @@\n ## A\n-a\n+A\n ## B\n-b\n+B\n',
      );
    });

    test('a negative context is an argument error', () {
      expect(
        () => approvalDiff('a\n', 'b\n', context: -1),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'must be a whole number from 0',
          ),
        ),
      );
    });

    test('equal texts give no hunk', () {
      expect(approvalDiff(_old, _old), '');
      expect(approvalDiff('', ''), '');
    });

    test('CRLF and LF texts with the same lines are equal', () {
      expect(approvalDiff('a\r\nb\r\n', 'a\nb\n'), '');
    });
  });

  group('changedUnits', () {
    test('changed units name fields, title, lead, and sections', () {
      expect(changedUnits(_old, _new), [
        _field('verify_method'),
        _section('Rationale'),
      ]);
    });

    test('a renamed header is one removed and one new unit', () {
      expect(changedUnits('## A\nx\n', '## B\nx\n'), [
        _section('A', .removed),
        _section('B', .added),
      ]);
    });

    test('a row holds the key or header text as written', () {
      const header = '`specstone approve` | A';

      expect(changedUnits('## $header\nx\n', '## $header\ny\n'), [
        _section(header),
      ]);
    });

    test('a changed title is the title unit', () {
      expect(changedUnits('# T\n', '# U\n'), [_bare(.title)]);
    });

    test('a changed lead is the lead unit', () {
      expect(
        changedUnits('# T\n\nlead\n\n## S\nx\n', '# T\n\nlead2\n\n## S\nx\n'),
        [_bare(.lead)],
      );
    });

    test('a lead that appears or goes is new or removed', () {
      expect(changedUnits('# T\n\n## S\nx\n', '# T\n\nlead\n\n## S\nx\n'), [
        _bare(.lead, .added),
      ]);
      expect(changedUnits('# T\n\nlead\n\n## S\nx\n', '# T\n\n## S\nx\n'), [
        _bare(.lead, .removed),
      ]);
    });

    test('a field that appears or goes is new or removed', () {
      expect(changedUnits('---\na: 1\n---\n', '---\na: 1\nb: 2\n---\n'), [
        _field('b', .added),
      ]);
      expect(changedUnits('---\na: 1\nb: 2\n---\n', '---\na: 1\n---\n'), [
        _field('b', .removed),
      ]);
    });

    test('a change no key owns in the frontmatter names the frontmatter', () {
      // A comment above a key belongs to that key, so the lines no key owns
      // are a stray line above the first key, or a frontmatter with no key.
      expect(
        changedUnits('---\nstray\nk: v\n---\n', '---\nstray2\nk: v\n---\n'),
        [_bare(.frontmatter)],
      );
      expect(changedUnits('---\n# note\n---\n', '---\n# note2\n---\n'), [
        _bare(.frontmatter),
      ]);
    });

    test('the frontmatter row comes before the field rows', () {
      expect(
        changedUnits('---\nstray\nk: v\n---\n', '---\nstray2\nk: w\n---\n'),
        [_bare(.frontmatter), _field('k')],
      );
    });

    test('a doc gaining frontmatter lists its fields as new', () {
      expect(changedUnits('# T\n', '---\na: 1\nb: 2\n---\n# T\n'), [
        _field('a', .added),
        _field('b', .added),
      ]);
    });

    test(
      'rows follow the new text and a removed unit sits after its predecessor',
      () {
        const before = '## A\na\n## B\nb\n## C\nc\n';
        const after = '## A\nA\n## C\nC\n';
        expect(changedUnits(before, after), [
          _section('A'),
          _section('B', .removed),
          _section('C'),
        ]);
      },
    );

    test('a removed first unit comes first', () {
      expect(changedUnits('## A\na\n## B\nb\n', '## B\nb\n'), [
        _section('A', .removed),
      ]);
      expect(changedUnits('## A\na\n## B\nb\n', '## B\nB\n'), [
        _section('A', .removed),
        _section('B'),
      ]);
    });

    test('a ## inside a code fence is no section', () {
      expect(
        changedUnits('## A\n```\n## x\n```\nx\n', '## A\n```\n## x\n```\nX\n'),
        [_section('A')],
      );
    });

    test('a change in spacing between sections names the section above', () {
      expect(changedUnits('## A\na\n## B\nb\n', '## A\na\n\n## B\nb\n'), [
        _section('A'),
      ]);
    });

    test('a final newline alone is no change', () {
      expect(changedUnits('## A\nx\n', '## A\nx'), isEmpty);
      expect(changedUnits('## A\nx', '## A\nx\n'), isEmpty);
      expect(approvalDiff('## A\nx\n', '## A\nx'), '');
    });

    test('equal texts, even in another line ending, change no unit', () {
      expect(changedUnits(_old, _old), isEmpty);
      expect(
        changedUnits('# T\r\n\r\n## A\r\nx\r\n', '# T\n\n## A\nx\n'),
        isEmpty,
      );
    });
  });
}
