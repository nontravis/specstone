// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';

import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_file.dart';
import 'package:specstone_core/src/index_query/bundle_render.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';

const _feature = 'docs/prds/features/f01_login/FEATURE.md';
const _fr =
    'docs/prds/features/f01_login/us01_email_login/fr01_validate_credentials.md';

/// A feature whose Problem holds a fenced `## ` line, and an FR that cites a
/// section and an item of another feature's docs.
const _layoutDocs = <String, String>{
  _feature:
      '---\nvision:\n  - PV-01\n---\n\n# Login\n\n'
      '## Problem\nUsers sign in.\n\n```markdown\n## Not a section\n```\n\n'
      '## Out-of-scope\n- Social sign-in — not planned\n',
  _fr:
      '---\nverify_method: test\n---\n\n# Validate credentials\n\n## Statement\n'
      'The system shall check the email, as [components](../../../../specs/f02_signup/ARCHITECTURE.md#components) '
      'and [INV-14](../../../../specs/f02_signup/DOMAIN.md#invariants) say, as '
      '[signing up](../../f02_signup/us01_create_account/USER_STORY.md) does.\n',
  'docs/specs/f02_signup/DOMAIN.md':
      '# Sign-up domain\n\n## Invariants\n'
      '- **INV-13** An account has one email.\n'
      '- **INV-14** An account locks after five failures.\n',
};

IndexedDoc _doc(String name) => IndexedDoc(
  docPath: 'prds/$name.md',
  docTypeId: 'fr',
  name: name,
  frontmatter: const {},
  tokens: 1,
);

/// Returns an answer of [count] docs, each of [sections] sections, whose text
/// holds one line per entry line.
ContextAnswer _answerOf(
  int count, {
  int sections = 1,
  String key = 'statement',
}) {
  final entries = <BundleEntry>[
    for (var i = 0; i < count; i++)
      (
        doc: _doc('d$i'),
        listName: 'd$i (fr)',
        summary: false,
        cited: false,
        first: 2 * i + 1,
        last: 2 * i + 1,
        sections: [
          for (var s = 0; s < sections; s++) (key: '$key$s', first: 2 * i + 1),
        ],
      ),
  ];
  return ContextAnswer(
    text: '${List.filled(2 * count, 'x').join('\n')}\n',
    json: const {},
    entries: entries,
    tokens: 7,
  );
}

void main() {
  group('f01/us05/fr07: bundleFileName, the Name rule', () {
    test('e01: a target and its mode', () {
      expect(
        bundleFileName(
          target: 'index_query/get_task_bundle',
          mode: BundleMode.design,
          summary: false,
          noProject: false,
        ),
        'index_query-get_task_bundle.design.txt',
      );
    });
    test('e11: a --code path takes code- and each separator written -', () {
      expect(
        bundleFileName(
          codePath: 'app/lib/login.dart',
          mode: BundleMode.implement,
          summary: false,
          noProject: false,
        ),
        'code-app-lib-login.dart.implement.txt',
      );
      expect(
        bundleFileName(
          codePath: r'app\lib\login.dart',
          mode: BundleMode.query,
          summary: false,
          noProject: false,
        ),
        'code-app-lib-login.dart.query.txt',
      );
    });
    test('e12: --target adds its name before .txt', () {
      expect(
        bundleFileName(
          target: 'feedback/toast/show_toast',
          mode: BundleMode.implement,
          summary: false,
          noProject: false,
          codeTarget: 'jaspr',
        ),
        'feedback-toast-show_toast.implement.jaspr.txt',
      );
    });
    test('e13: --summary and --no-project follow the mode', () {
      expect(
        bundleFileName(
          target: 'login',
          mode: BundleMode.design,
          summary: true,
          noProject: true,
        ),
        'login.design-summary-no-project.txt',
      );
      expect(
        bundleFileName(
          target: 'login',
          mode: BundleMode.implement,
          summary: false,
          noProject: true,
        ),
        'login.implement-no-project.txt',
      );
    });
    test('a <doc type>:<name> target writes its : as -', () {
      expect(
        bundleFileName(
          target: 'architecture:login',
          mode: BundleMode.implement,
          summary: false,
          noProject: false,
        ),
        'architecture-login.implement.txt',
      );
    });
  });

  group('f01/us05/fr07: bundleIndex', () {
    test('s20: the header, then each doc with its range and sections', () {
      final answer = ContextAnswer(
        text: 'a\nb\nc\n\nd\ne\n',
        json: const {},
        entries: [
          (
            doc: _doc('one'),
            listName: 'one (fr)',
            summary: false,
            cited: false,
            first: 1,
            last: 3,
            sections: const [
              (key: 'statement', first: 2),
              (key: 'edge_cases', first: 3),
            ],
          ),
          (
            doc: _doc('two'),
            listName: 'two (fr) · cited statement',
            summary: false,
            cited: true,
            first: 5,
            last: 6,
            sections: const [(key: 'statement', first: 5)],
          ),
        ],
        tokens: 42,
      );
      expect(
        bundleIndex(answer, '/work/shop/.specstone/bundles/x.design.txt'),
        '==> bundle: 1 docs, 42 tokens, 6 lines · /work/shop/.specstone/bundles/x.design.txt <==\n'
        '- one (fr) · 1-3 · statement 2, edge_cases 3\n'
        '- two (fr) · cited statement · 5-6 · statement 5\n',
      );
    });
    test('e05: an index of 200 lines keeps its sections', () {
      final index = bundleIndex(_answerOf(199), '/p');
      expect(const LineSplitter().convert(index), hasLength(200));
      expect(index, contains('- d198 (fr) · 397-397 · statement0 397\n'));
    });
    test('e05: an index past 200 lines lists every doc and no section', () {
      final index = bundleIndex(_answerOf(200), '/p');
      final lines = const LineSplitter().convert(index);
      expect(lines, hasLength(201));
      expect(lines[1], '- d0 (fr) · 1-1');
      expect(lines.last, '- d199 (fr) · 399-399');
      expect(index, isNot(contains('statement')));
    });
    test('e05: an index past 8 KiB lists every doc and no section', () {
      final answer = _answerOf(10, sections: 40, key: 'a_long_section_key_');
      final sectionsText = [
        for (final entry in answer.entries)
          for (final s in entry.sections) '${s.key} ${s.first}, ',
      ].join();
      expect(utf8.encode(sectionsText).length, greaterThan(8192));
      final index = bundleIndex(answer, '/p');
      expect(const LineSplitter().convert(index), hasLength(11));
      expect(index, isNot(contains('a_long_section_key_')));
      expect(index, endsWith('- d9 (fr) · 19-19\n'));
    });
    test('e05: an index of exactly 8,192 bytes keeps its sections', () {
      const shown = '/p';
      const header = '==> bundle: 1 docs, 7 tokens, 2 lines · $shown <==\n';
      const fixed = '- d0 (fr) · 1-1 · ';
      final room = 8192 - utf8.encode('$header$fixed').length - ' 1\n'.length;
      final answer = _answerOf(1, key: 'k' * (room - 1));
      final index = bundleIndex(answer, shown);
      expect(utf8.encode(index).length, 8192);
      expect(index, contains('k' * (room - 1)));
      final over = bundleIndex(_answerOf(1, key: 'k' * room), shown);
      expect(over, isNot(contains('k' * room)));
    });
    test('--json holds out, tokens, lines, and each doc with its sections, past the bound too', () {
      final json = bundleIndexJson(_answerOf(200), '/p/b.txt');
      expect(json.keys.toList(), ['out', 'tokens', 'lines', 'docs']);
      expect(json['out'], '/p/b.txt');
      expect(json['tokens'], 7);
      expect(json['lines'], 400);
      final docs = json['docs']! as List<Object>;
      expect(docs, hasLength(200));
      expect(docs.first, {
        'name': 'd0',
        'docType': 'fr',
        'docPath': 'prds/d0.md',
        'lines': [1, 1],
        'summary': false,
        'cited': false,
        'sections': [
          {'key': 'statement0', 'first': 1},
        ],
      });
    });
  });

  group('f01/us05/fr07, F14: answerContext places each doc and part', () {
    void expectPlaced(ContextAnswer answer) {
      final lines = answer.text.split('\n');
      expect(answer.entries, isNotEmpty);
      for (final entry in answer.entries) {
        expect(
          lines[entry.first - 1],
          startsWith('==> '),
          reason: entry.listName,
        );
        expect(lines[entry.last - 1], isNotEmpty, reason: entry.listName);
        expect(
          lines[entry.last],
          anyOf('', startsWith('==> bundle: ')),
          reason: entry.listName,
        );
        for (final section in entry.sections) {
          expect(
            lines[section.first - 1],
            startsWith('## '),
            reason: '${entry.listName} ${section.key}',
          );
          expect(section.first, inInclusiveRange(entry.first, entry.last));
        }
      }
    }

    test(
      'implement: picked docs and cited parts, a fenced ## line no section',
      () async {
        final index = await indexWith(_layoutDocs);
        final answer = answerContext(
          index,
          pickBundle(
            index,
            'login/email_login',
            BundleMode.implement,
            noProject: false,
          ),
          label: 'login/email_login',
          byCode: false,
        );
        expectPlaced(answer);
        final feature = answer.entries.singleWhere(
          (e) => e.listName == 'login (feature)',
        );
        expect(
          [for (final s in feature.sections) s.key],
          ['problem', 'out_of_scope'],
        );
        final section = answer.entries.singleWhere(
          (e) => e.listName == 'signup (architecture) · cited components',
        );
        expect(section.cited, isTrue);
        expect([for (final s in section.sections) s.key], ['components']);
        final item = answer.entries.singleWhere(
          (e) => e.listName == 'signup (domain) · cited invariants [INV-14]',
        );
        expect(item.sections, isEmpty);
        final summary = answer.entries.singleWhere(
          (e) =>
              e.listName ==
              'signup/create_account (user_story) · summary · cited',
        );
        expect(summary.summary, isTrue);
        expect([for (final s in summary.sections) s.key], ['use_case']);
        expect(answer.entries.where((e) => !e.cited), hasLength(12));
      },
    );
    test(
      'design --summary: summary docs place their summary sections',
      () async {
        final index = await indexWith();
        final answer = answerContext(
          index,
          pickBundle(
            index,
            'login',
            BundleMode.design,
            noProject: false,
            summary: true,
          ),
          label: 'login',
          byCode: false,
        );
        expectPlaced(answer);
        final story = answer.entries.singleWhere(
          (e) => e.listName == 'login/email_login (user_story) · summary',
        );
        expect(story.summary, isTrue);
        expect(story.sections, isNotEmpty);
      },
    );
    test('over budget: no doc text, no entry', () async {
      final index = await indexWith();
      final answer = answerContext(
        index,
        pickBundle(
          index,
          'login/email_login',
          BundleMode.implement,
          noProject: false,
        ),
        label: 'login/email_login',
        byCode: false,
        budget: 1,
      );
      expect(answer.exitStatus, 1);
      expect(answer.entries, isEmpty);
    });
  });
}
