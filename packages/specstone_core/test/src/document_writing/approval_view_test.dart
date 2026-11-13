import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/document_writing/approval_view.dart';
import 'package:specstone_core/src/document_writing/sentence_changes.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/fixture_doc_types.dart';

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
const SentenceChanges _noSentences = (dropped: <String>[], added: <String>[]);
const _noChangeEnd =
    '| dropped | 0 sentences dropped |\n'
    '| new     | 0 sentences new |\n\n'
    'no change since the approved copy\n';

ApprovedCopy _copy(String text, {String path = _path}) =>
    ApprovedCopy(text, commit: _commit, path: path);

DraftView _draft({
  String text = _neuDraft,
  ApprovalLookup? lookup,
  String? title = 'FR-01 — T',
  String? status = 'planned',
  Map<String, String?> statusByTarget = const {},
  String name = 'fr01_t',
  String projectPath = _path,
  String? docPath,
  MergedDocType? mergedType,
  SentenceChanges sentences = _noSentences,
}) => DraftView(
  name: name,
  docType: 'fr',
  mergedType: mergedType,
  title: title,
  status: status,
  statusByTarget: statusByTarget,
  docPath: docPath ?? projectPath,
  projectPath: projectPath,
  text: text,
  lookup: lookup ?? _copy(_old),
  sentences: sentences,
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
  group('document_writing/approve_drafts/show_changes_since_approval E17', () {
    const body = '## Statement\n';
    String fr(String statement) =>
        '---\nverify_method: test\n---\n\n# FR-01 — T\n\n$body$statement';
    const padded = '| Name   | Role |\n|--------|------|\n| Signup | Form |\n';
    const compact = '| Name | Role |\n|---|---|\n| Signup | Form |\n';
    late MergedDocType frType;

    setUp(() async {
      frType = (await fixtureDocTypes()).lookup('functional_requirement')!;
    });

    test('a layout-only change shows the no-change line and the none row', () {
      final view = _render(
        _draft(
          text: fr('\n$padded'),
          lookup: _copy(fr('\n$compact')),
          mergedType: frType,
        ),
      );
      expect(view, endsWith('| changes | none |\n$_noChangeEnd'));
    });

    test('a hard break added or removed shows as a change', () {
      final added = _render(
        _draft(
          text: fr('One  \nTwo\n'),
          lookup: _copy(fr('One\nTwo\n')),
          mergedType: frType,
        ),
      );
      final removed = _render(
        _draft(
          text: fr('One\nTwo\n'),
          lookup: _copy(fr('One  \nTwo\n')),
          mergedType: frType,
        ),
      );
      for (final view in [added, removed]) {
        expect(view, contains('| changes | `## Statement` |'));
        expect(view, contains('```diff\n'));
      }
    });

    test('a copy the formatter refuses compares as written', () {
      const refused = '## Bogus\nB.\n\n$body';
      final view = _render(
        _draft(
          text: fr('\n$padded${refused}X.\n'),
          lookup: _copy(fr('\n$compact${refused}X.\n')),
          mergedType: frType,
        ),
      );
      expect(view, isNot(contains('no change since the approved copy')));
      expect(view, contains('| changes |'));
    });

    test(
      'a refused draft against a laid-out copy compares each as laid out',
      () {
        final view = _render(
          _draft(
            text: fr('\n$padded\n## Bogus\nB.\n'),
            lookup: _copy(fr('\n$compact')),
            mergedType: frType,
          ),
        );
        expect(view, isNot(contains('no change since the approved copy')));
        expect(view, contains('+## Bogus'));
        // The refused draft keeps its padding; the laid-out copy has none.
        expect(view, contains('+| Name   | Role |'));
        expect(view, contains('-| Name | Role |'));
      },
    );
  });

  group('DraftView comparison', () {
    test('document_writing/approve_drafts/show_changes_since_approval: the '
        'view and the JSON read one comparison, found once', () {
      final draft = _draft(lookup: _copy(_old));
      final first = draft.comparison;

      final view = _render(draft, context: 1);
      final json = draftViewJson(draft);

      expect(identical(draft.comparison, first), isTrue);
      expect(first.hasDiff, isTrue);
      expect(first.units, isNotEmpty);
      expect(view, contains('| changes | field `verify_method` |'));
      expect(json['changes'], 'field verify_method, rationale');
    });
  });

  group('draftViewJson', () {
    String feature(String flow, {String extra = ''}) =>
        '---\nvision:\n  - V\n---\n\n# F\n\n## Feature name\nN.\n\n'
        '## Feature goal\n- **why:** W.\n\n## Feature flow\n$flow\n$extra';
    late MergedDocType featureType;

    setUp(() async {
      featureType = (await fixtureDocTypes()).lookup('feature')!;
    });

    test('a section the template names by an id other than its header key '
        'prints as that id', () {
      final json = draftViewJson(
        _draft(
          text: feature('New flow.'),
          lookup: _copy(feature('Old flow.')),
          mergedType: featureType,
        ),
      );

      expect(json['changes'], 'flow');
    });

    test('a section the template does not name prints as the key its header '
        'derives', () {
      final json = draftViewJson(
        _draft(
          text: feature('Flow.', extra: '\n## Open Notes\nNew.\n'),
          lookup: _copy(feature('Flow.', extra: '\n## Open Notes\nOld.\n')),
          mergedType: featureType,
        ),
      );

      expect(json['changes'], 'open_notes');
    });

    test('renamedFrom is relative to the docs root, as docPath is, and a '
        'path outside the docs root stays as git reported it', () {
      Map<String, Object> jsonFor(String copyPath) => draftViewJson(
        _draft(
          projectPath: 'docs/prds/b.md',
          docPath: 'prds/b.md',
          lookup: _copy(_old, path: copyPath),
        ),
      );

      expect(
        jsonFor('docs/prds/a.md'),
        containsPair('renamedFrom', 'prds/a.md'),
      );
      expect(jsonFor('top/a.md'), containsPair('renamedFrom', 'top/a.md'));
      expect(jsonFor('docs/prds/b.md'), isNot(contains('renamedFrom')));
    });
  });

  group('the status row under two or more code targets', () {
    test('each target shows its status in config order, one code span', () {
      final view = _render(
        _draft(
          status: null,
          statusByTarget: const {'app': 'implemented', 'web': 'planned'},
        ),
      );
      expect(view, contains('| status  | `app implemented · web planned` |'));
      final json = draftViewJson(
        _draft(
          status: null,
          statusByTarget: const {'app': 'implemented', 'web': 'planned'},
        ),
      );
      expect(
        json['statusByTarget'],
        isA<Map<String, Object?>>().having((m) => m.keys.toList(), 'keys', [
          'app',
          'web',
        ]),
      );
      expect(json.containsKey('status'), isFalse);
    });

    test('a target with no status is dropped, and none left shows no row', () {
      final partlyNull = _render(
        _draft(
          status: null,
          statusByTarget: const {'app': 'implemented', 'web': null},
        ),
      );
      expect(partlyNull, contains('| status  | `app implemented` |'));

      final allNull = _render(
        _draft(status: null, statusByTarget: const {'app': null, 'web': null}),
      );
      expect(allNull, isNot(contains('| status')));
      final json = draftViewJson(
        _draft(status: null, statusByTarget: const {'app': null, 'web': null}),
      );
      expect(json.containsKey('status'), isFalse);
      expect(json.containsKey('statusByTarget'), isFalse);
    });
  });

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
        '| dropped | 0 sentences dropped |\n'
        '| new     | 0 sentences new |\n'
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

    test(
      'f02/us03/fr02/e08: a renamed header prints its removed and new rows',
      () {
        final renamed = _render(
          _draft(
            text: '---\nk: v\ndraft: true\n---\n\n## B\nx\n',
            lookup: _copy('---\nk: v\n---\n\n## A\nx\n'),
          ),
        );

        expect(
          renamed,
          contains(
            '| changes | `## A` (removed) |\n|         | `## B` (new) |\n',
          ),
        );
      },
    );

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

      expect(view, endsWith('| changes | none |\n$_noChangeEnd'));
      expect(view, isNot(contains('```')));
    });

    test('f02/us03/fr02/e08: a CRLF approved copy diffs as LF', () {
      final view = _render(
        _draft(text: _neuDraft, lookup: _copy(_neu.replaceAll('\n', '\r\n'))),
      );

      expect(view, endsWith('| changes | none |\n$_noChangeEnd'));
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

  group('document_writing/approve_drafts/show_changes_since_approval E23', () {
    test('the dropped and new rows follow the changes rows, and each list '
        'follows the diff', () {
      final view = _render(
        _draft(
          sentences: (dropped: ['Gone one.', 'Gone two.'], added: ['Fresh.']),
        ),
      );

      expect(
        view,
        contains(
          '| changes | field `verify_method` |\n'
          '|         | `## Rationale` |\n'
          '| dropped | 2 sentences dropped |\n'
          '| new     | 1 sentence new |\n\n```diff\n',
        ),
      );
      expect(
        view,
        endsWith(
          '\n```\n\nDropped sentences:\n- Gone one.\n- Gone two.\n\n'
          'New sentences:\n- Fresh.\n',
        ),
      );
    });

    test('a list is printed only when its count is above 0', () {
      final onlyDropped = _render(
        _draft(sentences: (dropped: ['Gone.'], added: <String>[])),
      );
      final onlyNew = _render(
        _draft(sentences: (dropped: <String>[], added: ['Fresh.'])),
      );

      expect(onlyDropped, contains('| dropped | 1 sentence dropped |\n'));
      expect(onlyDropped, contains('| new     | 0 sentences new |\n'));
      expect(onlyDropped, endsWith('\n```\n\nDropped sentences:\n- Gone.\n'));
      expect(onlyDropped, isNot(contains('New sentences:')));
      expect(onlyNew, contains('| dropped | 0 sentences dropped |\n'));
      expect(onlyNew, endsWith('\n```\n\nNew sentences:\n- Fresh.\n'));
      expect(onlyNew, isNot(contains('Dropped sentences:')));
    });

    test('a list follows the no-change line when the layout alone differs', () {
      final view = _render(
        _draft(
          lookup: _copy(_neu),
          sentences: (dropped: ['Gone.'], added: <String>[]),
        ),
      );

      expect(
        view,
        endsWith(
          '| dropped | 1 sentence dropped |\n'
          '| new     | 0 sentences new |\n\n'
          'no change since the approved copy\n\nDropped sentences:\n- Gone.\n',
        ),
      );
    });

    test('a count of 0 prints the rows and no list', () {
      final view = _render(_draft());

      expect(view, contains('| dropped | 0 sentences dropped |\n'));
      expect(view, contains('| new     | 0 sentences new |\n'));
      expect(view, isNot(contains('sentences:')));
    });

    test('colour touches no sentence line', () {
      final view = _render(
        _draft(sentences: (dropped: ['Gone.'], added: ['Fresh.'])),
        color: true,
      );

      expect(
        view,
        endsWith(
          '\n```\n\nDropped sentences:\n- Gone.\n\nNew sentences:\n- Fresh.\n',
        ),
      );
    });
  });
}
