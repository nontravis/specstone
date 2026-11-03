import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/document_writing/approval_view.dart';
import 'package:test/test.dart';

const _old =
    '---\nverify_method: test\n---\n\n# FR-01 — T\n\n'
    '## Statement\nA.\n\n## Rationale\nR.\n';
const _neu =
    '---\nverify_method: demonstration\n---\n\n# FR-01 — T\n\n'
    '## Statement\nA.\n\n## Rationale\nR2.\n';
const _neuDraft =
    '---\nverify_method: demonstration\ndraft: true\n---\n\n# FR-01 — T\n\n'
    '## Statement\nA.\n\n## Rationale\nR2.\n';
const _path = 'docs/fr01_t.md';
const _commit = '4b1c2d3e5f60718293a4b5c6d7e8f9012345abcd';

ApprovedCopy _copy(String text, {String path = _path}) =>
    ApprovedCopy(text, commit: _commit, path: path);

DraftView _draft({
  String text = _neuDraft,
  ApprovalLookup? lookup,
  String? title = 'FR-01 — T',
  String? status = 'planned',
  String name = 'fr01_t',
  String projectPath = _path,
}) => DraftView(
  name: name,
  docType: 'fr',
  title: title,
  status: status,
  projectPath: projectPath,
  text: text,
  lookup: lookup ?? _copy(_old),
);

String _render(DraftView draft, {int? context, bool color = false}) =>
    renderApprovalView(
      draft,
      position: 3,
      count: 4,
      context: context,
      color: color,
    );

void main() {
  group('renderApprovalView', () {
    test('f02/us03/fr02: the view prints heading, path, table, and diff', () {
      final hash = baseHashOf(_neuDraft);

      expect(
        _render(_draft()),
        '### Draft 3/4 · FR-01 — T\n'
        '`docs/fr01_t.md`\n'
        '\n'
        '| field   | value |\n'
        '|---------|-------|\n'
        '| doc     | `fr01_t` (fr) |\n'
        '| status  | `planned` |\n'
        '| hash    | `$hash` |\n'
        '| old     | approved copy in commit `4b1c2d3` |\n'
        '| changes | field `verify_method` |\n'
        '|         | `## Rationale` |\n'
        '\n'
        '```diff\n'
        '@@ -1,3 +1,3 @@\n'
        ' ---\n'
        '-verify_method: test\n'
        '+verify_method: demonstration\n'
        ' ---\n'
        '@@ -10,2 +10,2 @@\n'
        ' ## Rationale\n'
        '-R.\n'
        '+R2.\n'
        '```\n',
      );
    });

    test('f02/us03/fr02: the hash is the base of the draft read as LF', () {
      final crlf = _neuDraft.replaceAll('\n', '\r\n');

      expect(
        _render(_draft(text: crlf)),
        contains('| hash    | `${baseHashOf(_neuDraft)}` |\n'),
      );
    });

    test('f02/us03/fr02/e11: draft and approved never show', () {
      final oldApproved = _old.replaceFirst(
        'verify_method: test\n',
        'verify_method: test\napproved: true\n',
      );

      final view = _render(_draft(lookup: _copy(oldApproved)));

      expect(view, isNot(contains('draft: true')));
      expect(view, isNot(contains('approved: true')));
      expect(view, contains('| changes | field `verify_method` |\n'));
    });

    test(
      'f02/us03/fr02/e11: withoutApprovalMarks drops both key blocks only',
      () {
        expect(
          withoutApprovalMarks(
            '---\ndraft: true\nverify_method: test\napproved: true\n---\n# T\n',
          ),
          '---\nverify_method: test\n---\n# T\n',
        );
        expect(withoutApprovalMarks('# T\n'), '# T\n');
      },
    );

    test('f02/us03/fr02/e03, e04: no old copy shows the doc whole', () {
      final lines = _neu.split('\n')..removeLast();
      final body = lines.map((l) => '+$l').join('\n');

      final never = _render(_draft(lookup: const NoApprovedCopy()));

      expect(never, contains('| old     | none: never approved |\n'));
      expect(never, contains('| changes | whole doc |\n'));
      expect(
        never,
        endsWith('```diff\n@@ -0,0 +1,${lines.length} @@\n$body\n```\n'),
      );

      final unknown = _render(_draft(lookup: const UnknownHistory()));

      expect(unknown, contains('| old     | unknown: git cannot answer |\n'));
      expect(unknown, contains('| changes | whole doc |\n'));
      expect(
        unknown,
        endsWith('```diff\n@@ -0,0 +1,${lines.length} @@\n$body\n```\n'),
      );
    });

    test('f02/us03/fr02/e12: an unchanged draft says so', () {
      final oldMarked = _neu.replaceFirst(
        'verify_method: demonstration\n',
        'verify_method: demonstration\napproved: true\n',
      );

      final view = _render(_draft(lookup: _copy(oldMarked)));

      expect(
        view,
        endsWith('| changes | none |\n\nno change since the approved copy\n'),
      );
      expect(view, isNot(contains('```')));
    });

    test('f02/us03/fr02/e08: a CRLF approved copy diffs as LF', () {
      final view = _render(
        _draft(text: _neuDraft, lookup: _copy(_neu.replaceAll('\n', '\r\n'))),
      );

      expect(
        view,
        endsWith('| changes | none |\n\nno change since the approved copy\n'),
      );
    });

    test("f02/us03/fr02/e13: the fence outlasts the doc's own fence", () {
      const oldText = '# T\n\n## Behavior\n```mermaid\nflowchart\n```\n';
      const newText = '# T\n\n## Behavior\n```mermaid\nflowchart X\n```\n';

      final view = _render(_draft(text: newText, lookup: _copy(oldText)));

      expect(view, contains('\n````diff\n'));
      expect(view, endsWith('\n````\n'));
    });

    test('f02/us03/fr02/e13: a longer backtick run lengthens the fence', () {
      const oldText = '# T\n\n## Behavior\n`````x\n';
      const newText = '# T\n\n## Behavior\n`````y\n';

      final view = _render(_draft(text: newText, lookup: _copy(oldText)));

      expect(view, contains('\n``````diff\n'));
      expect(view, endsWith('\n``````\n'));
    });

    test(
      'f02/us03/fr02/e13: a header holding backticks prints in a longer span',
      () {
        const header = '`specstone approve [<name> …] --dry-run` — US-03 FR-05';
        const oldText = '# T\n\n## $header\nA.\n';
        const newText = '# T\n\n## $header\nB.\n';

        final view = _render(_draft(text: newText, lookup: _copy(oldText)));

        expect(view, contains('| changes | ``## $header`` |\n'));
      },
    );

    test('f02/us03/fr02/e13: a span whose text ends in a backtick pads it', () {
      const oldText = '# T\n\n## Run `get`\nA.\n';
      const newText = '# T\n\n## Run `get`\nB.\n';

      final view = _render(_draft(text: newText, lookup: _copy(oldText)));

      expect(view, contains('| changes | `` ## Run `get` `` |\n'));
    });

    test('f02/us03/fr02/e13: a | in a table cell is escaped', () {
      const oldText = '---\n"a|b": 1\n---\n# T\n\n## A | B\nA.\n';
      const newText = '---\n"a|b": 2\n---\n# T\n\n## A | B\nB.\n';

      final view = _render(_draft(text: newText, lookup: _copy(oldText)));

      expect(view, contains('| changes | field `a\\|b` |\n'));
      expect(view, contains('|         | `## A \\| B` |\n'));
    });

    test('f02/us03/fr02/e13, e15: a name or path holding backticks prints in '
        'a longer span', () {
      final view = _render(
        _draft(
          name: 'fr01_`t`',
          projectPath: 'docs/fr01_`t`.md',
          lookup: _copy(_old, path: 'docs/old/fr01_`t`.md'),
        ),
      );
      final lines = view.split('\n');

      expect(lines[1], '``docs/fr01_`t`.md``');
      expect(lines[2], 'renamed from ``docs/old/fr01_`t`.md``');
      expect(lines[6], '| doc     | `` fr01_`t` `` (fr) |');
    });

    test(
      'f02/us03/fr02/e15: a rename prints its old path under the path line',
      () {
        final view = _render(
          _draft(lookup: _copy(_old, path: 'docs/old/fr01_t.md')),
        );
        final lines = view.split('\n');

        expect(lines[1], '`docs/fr01_t.md`');
        expect(lines[2], 'renamed from `docs/old/fr01_t.md`');
        expect(lines[3], '');
        expect(lines[4], '| field   | value |');
        expect(
          lines.where((l) => l.startsWith('|') && l.contains('docs/old')),
          isEmpty,
        );
      },
    );

    test('f02/us03/fr02/e15: no rename line when the path is the same', () {
      expect(_render(_draft()), isNot(contains('renamed from')));
    });

    test('f02/us03/fr02: no status and no title', () {
      final view = _render(_draft(status: null, title: null));
      final lines = view.split('\n');

      expect(lines.first, '### Draft 3/4 · fr01_t');
      expect(view, isNot(contains('| status')));
      expect(lines[5], '| doc     | `fr01_t` (fr) |');
      expect(lines[6], startsWith('| hash    |'));
    });

    test('f02/us03/fr02/e14: context n narrows the diff to n lines', () {
      final view = _render(_draft(), context: 0);

      expect(
        view,
        endsWith(
          '```diff\n@@ -2 +2 @@\n-verify_method: test\n'
          '+verify_method: demonstration\n@@ -11 +11 @@\n-R.\n+R2.\n```\n',
        ),
      );
    });

    test('f02/us03/fr02/e16: colour marks diff lines only', () {
      final plain = _render(_draft());
      final colored = _render(_draft(), color: true);
      final tinted = colored.split('\n').where((l) => l.contains('\x1b'));

      expect(plain, isNot(contains('\x1b')));
      expect(colored, contains('\n\x1b[36m@@ -1,3 +1,3 @@\x1b[0m\n'));
      expect(colored, contains('\n\x1b[31m-verify_method: test\x1b[0m\n'));
      expect(
        colored,
        contains('\n\x1b[32m+verify_method: demonstration\x1b[0m\n'),
      );
      expect(colored, contains('\n ---\n'));
      expect(colored, contains('\n```diff\n'));
      expect(colored, endsWith('\n```\n'));
      expect(tinted, hasLength(6));
      expect(
        tinted,
        everyElement(matches(RegExp(r'^\x1b\[3[126]m[-+@].*\x1b\[0m$'))),
      );
    });
  });
}
