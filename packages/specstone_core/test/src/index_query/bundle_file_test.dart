// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_file.dart';
import 'package:specstone_core/src/index_query/bundle_render.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
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
        summary: false,
        kind: BundleEntryKind.doc,
        sectionKey: null,
        itemId: null,
        featurePattern: null,
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
  group('bundleFileName, the Name rule', () {
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

  group('bundleIndex', () {
    test('s20: the header, then each doc and part as <name> (<doc type>) · <first>-<last>, marks after the range', () {
      final answer = ContextAnswer(
        text: 'a\nb\nc\n\nd\ne\n\nf\n\ng\n\nh\n\ni\n',
        json: const {},
        entries: [
          (
            doc: _doc('one'),
            summary: false,
            kind: BundleEntryKind.doc,
            sectionKey: null,
            itemId: null,
            featurePattern: null,
            first: 1,
            last: 3,
            sections: const [
              (key: 'statement', first: 2),
              (key: 'edge_cases', first: 3),
            ],
          ),
          (
            doc: _doc('two'),
            summary: false,
            kind: BundleEntryKind.cited,
            sectionKey: 'statement',
            itemId: null,
            featurePattern: null,
            first: 5,
            last: 6,
            sections: const [(key: 'statement', first: 5)],
          ),
          (
            doc: _doc('three'),
            summary: false,
            kind: BundleEntryKind.cited,
            sectionKey: 'edge_cases',
            itemId: 'E01',
            featurePattern: null,
            first: 8,
            last: 8,
            sections: const [],
          ),
          (
            doc: _doc('four'),
            summary: true,
            kind: BundleEntryKind.doc,
            sectionKey: null,
            itemId: null,
            featurePattern: null,
            first: 10,
            last: 10,
            sections: const [(key: 'use_case', first: 10)],
          ),
          (
            doc: _doc('five'),
            summary: true,
            kind: BundleEntryKind.cited,
            sectionKey: null,
            itemId: null,
            featurePattern: null,
            first: 12,
            last: 12,
            sections: const [],
          ),
          (
            doc: const IndexedDoc(
              docPath: 'prds/notes.txt',
              name: 'prds/notes.txt',
              frontmatter: {},
              tokens: 0,
            ),
            summary: false,
            kind: BundleEntryKind.cited,
            sectionKey: null,
            itemId: null,
            featurePattern: null,
            first: 14,
            last: 14,
            sections: const [],
          ),
        ],
        tokens: 42,
      );
      expect(
        bundleIndex(answer, '/work/shop/.specstone/bundles/x.design.txt'),
        '==> bundle: 2 docs, 42 tokens, 14 lines · /work/shop/.specstone/bundles/x.design.txt <==\n'
        '- one (fr) · 1-3 · statement 2, edge_cases 3\n'
        '- two (fr) · 5-6 · cited statement · statement 5\n'
        '- three (fr) · 8-8 · cited edge_cases [E01]\n'
        '- four (fr) · 10-10 · summary · use_case 10\n'
        '- five (fr) · 12-12 · summary · cited\n'
        '- prds/notes.txt · 14-14 · cited\n',
      );
    });
    test('e10: a code target prints its line before the header, and --json holds codeTarget', () {
      final base = _answerOf(1);
      final answer = ContextAnswer(
        text: base.text,
        json: base.json,
        entries: base.entries,
        tokens: base.tokens,
        codeTarget: 'jaspr',
      );
      final index = bundleIndex(answer, '/p');
      expect(index, startsWith('==> code target: jaspr <==\n==> bundle: '));
      expect(bundleIndexJson(answer, '/p')['codeTarget'], 'jaspr');
      expect(bundleIndex(base, '/p'), startsWith('==> bundle: '));
      expect(bundleIndexJson(base, '/p').containsKey('codeTarget'), isFalse);
    });

    ContextAnswer withTarget(ContextAnswer base) => ContextAnswer(
      text: base.text,
      json: base.json,
      entries: base.entries,
      tokens: base.tokens,
      codeTarget: 'jaspr',
    );

    test('e05: a code target line, the header, and 198 entries make 200 lines and keep their sections', () {
      final index = bundleIndex(withTarget(_answerOf(198)), '/p');
      expect(const LineSplitter().convert(index), hasLength(200));
      expect(index, contains('- d197 (fr) · 395-395 · statement0 395\n'));
    });
    test('e05: a code target line, the header, and 199 entries pass 200 lines and drop the sections', () {
      final index = bundleIndex(withTarget(_answerOf(199)), '/p');
      expect(const LineSplitter().convert(index), hasLength(201));
      expect(index, contains('- d198 (fr) · 397-397\n'));
      expect(index, isNot(contains('statement0')));
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

  group('bundleIndex and its --json hold each feature pattern part', () {
    BundleEntry docEntry(String name, int first, int last) => (
      doc: _doc(name),
      summary: false,
      kind: BundleEntryKind.doc,
      sectionKey: null,
      itemId: null,
      featurePattern: null,
      first: first,
      last: last,
      sections: [(key: 'statement', first: first)],
    );
    BundleEntry partEntry(String id, int first, int last) => (
      doc: const IndexedDoc(
        docPath: 'prds/features/f01_login/FEATURE.md',
        docTypeId: 'feature',
        name: 'login',
        frontmatter: {},
        tokens: 1,
      ),
      summary: false,
      kind: BundleEntryKind.pattern,
      sectionKey: null,
      itemId: null,
      featurePattern: id,
      first: first,
      last: last,
      sections: const [],
    );
    ContextAnswer answerOf(String mode) => ContextAnswer(
      text: 'a\nb\n\nc\nd\n\ne\nf\n',
      json: {'for': mode},
      entries: [
        docEntry('login', 1, 2),
        partEntry('auth', 4, 5),
        docEntry('story', 7, 8),
      ],
      tokens: 9,
    );

    test('a part gets `- <id> (feature pattern) · <first>-<last>` with no section, where it prints', () {
      expect(
        bundleIndex(answerOf('design'), '/p/b.txt'),
        '==> bundle: 2 docs, 9 tokens, 8 lines · /p/b.txt <==\n'
        '- login (fr) · 1-2 · statement 1\n'
        '- auth (feature pattern) · 4-5\n'
        '- story (fr) · 7-8 · statement 7\n',
      );
    });
    test(
      'a part stays one line without sections when the index drops them',
      () {
        final base = answerOf('design');
        final padding = _answerOf(200);
        final answer = ContextAnswer(
          text: base.text,
          json: base.json,
          entries: [...base.entries, ...padding.entries],
          tokens: base.tokens,
        );
        final index = bundleIndex(answer, '/p');
        expect(index, contains('- auth (feature pattern) · 4-5\n'));
        expect(index, isNot(contains('statement')));
      },
    );
    test('in a design reply --json lists docs without parts, then featurePatterns as {id, doc, lines}', () {
      final json = bundleIndexJson(answerOf('design'), '/p/b.txt');
      expect(json.keys.toList(), [
        'out',
        'tokens',
        'lines',
        'docs',
        'featurePatterns',
      ]);
      expect(
        [for (final doc in json['docs']! as List) (doc as Map)['name']],
        ['login', 'story'],
      );
      expect(json['featurePatterns'], [
        {
          'id': 'auth',
          'doc': 'feature:login',
          'lines': [4, 5],
        },
      ]);
    });
    test('a design reply where no part joins gives featurePatterns: []', () {
      final base = _answerOf(1);
      final answer = ContextAnswer(
        text: base.text,
        json: const {'for': 'design'},
        entries: base.entries,
        tokens: base.tokens,
      );
      expect(bundleIndexJson(answer, '/p')['featurePatterns'], isEmpty);
    });
    test('outside design --json has no featurePatterns key', () {
      for (final mode in ['implement', 'query']) {
        final json = bundleIndexJson(answerOf(mode), '/p/b.txt');
        expect(json, isNot(contains('featurePatterns')));
      }
    });
  });

  group('answerContext places each doc and part', () {
    void expectPlaced(ContextAnswer answer) {
      final lines = answer.text.split('\n');
      expect(answer.entries, isNotEmpty);
      for (final entry in answer.entries) {
        final reason = '${entry.doc.name} at ${entry.first}';
        expect(lines[entry.first - 1], startsWith('==> '), reason: reason);
        expect(lines[entry.last - 1], isNotEmpty, reason: reason);
        expect(
          lines[entry.last],
          anyOf('', startsWith('==> bundle: ')),
          reason: reason,
        );
        for (final section in entry.sections) {
          expect(
            lines[section.first - 1],
            startsWith('## '),
            reason: '$reason ${section.key}',
          );
          expect(section.first, inInclusiveRange(entry.first, entry.last));
        }
      }
    }

    /// Returns the one index line of [answer] that matches [pattern].
    void expectIndexLine(ContextAnswer answer, String pattern) {
      final lines = bundleIndex(answer, '/p').split('\n');
      expect(lines.where(RegExp('^$pattern\$').hasMatch), hasLength(1));
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
          (e) => e.doc.name == 'login' && e.doc.docTypeId == 'feature',
        );
        expect(
          [for (final s in feature.sections) s.key],
          ['problem', 'out_of_scope'],
        );
        expectIndexLine(
          answer,
          r'- login \(feature\) · \d+-\d+ · problem \d+, out_of_scope \d+',
        );
        expectIndexLine(
          answer,
          r'- signup \(architecture\) · \d+-\d+ · cited components · components \d+',
        );
        expectIndexLine(
          answer,
          r'- signup \(domain\) · \d+-\d+ · cited invariants \[INV-14\]',
        );
        expectIndexLine(
          answer,
          r'- signup/create_account \(user_story\) · \d+-\d+ · summary · cited · use_case \d+',
        );
        expect(
          answer.entries.where((e) => e.kind != BundleEntryKind.cited),
          hasLength(12),
        );
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
        expectIndexLine(
          answer,
          r'- login/email_login \(user_story\) · \d+-\d+ · summary · use_case \d+',
        );
      },
    );
    test('a naming-line part has one index line with its range and cited, no section', () async {
      final index = await indexWith({
        'docs/prds/PROJECT.md':
            '---\nowner: Owner\n---\n\n# Project context\n\n## Project name\n'
            'Login demo; see [resets](../measurements/fewer_resets/MEASUREMENT.md).\n',
        'docs/measurements/fewer_resets/MEASUREMENT.md':
            '# Fewer resets\n\n## Scope\n- Resets per week.\n',
      });
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
      expectIndexLine(
        answer,
        r'- fewer_resets \(measurement\) · (\d+)-\1 · cited',
      );
      final entry = bundleIndexJson(answer, '/p')['docs']! as List;
      expect(
        entry.firstWhere((d) => (d as Map)['name'] == 'fewer_resets'),
        containsPair('sections', isEmpty),
      );
    });
    test('an appended cut has one index line marked summary then cited, with its section, and a summary --json row', () async {
      final index = await indexWith({
        'docs/prds/PROJECT.md':
            '---\nowner: Owner\n---\n\n# Project context\n\n## Project name\n'
            'Login demo; see [results](../measurements/fewer_resets/MEASUREMENT.md#results).\n',
        'docs/measurements/fewer_resets/MEASUREMENT.md':
            '# Fewer resets\n\n## Scope\n- Resets per week.\n\n## Results\n'
            'Newest first.\n\n| Date | Run | Met |\n|---|---|---|\n| 2026-11-14 | 2 | no |\n| 2026-11-01 | 1 | no |\n',
      });
      final answer = answerContext(
        index,
        pickBundle(index, 'project', BundleMode.implement, noProject: false),
        label: 'project',
        byCode: false,
      );
      expectPlaced(answer);
      expectIndexLine(
        answer,
        r'- fewer_resets \(measurement\) · \d+-\d+ · summary · cited results · results \d+',
      );
      final docs = bundleIndexJson(answer, '/p')['docs']! as List;
      final row =
          docs.firstWhere((d) => (d as Map)['name'] == 'fewer_resets') as Map;
      expect(row['summary'], isTrue);
      expect(row['cited'], isTrue);
      expect((row['sections'] as List).single, containsPair('key', 'results'));
    });
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

  group('answerBundleFile refuses a path under .specstone/', () {
    test('the config is refused and its bytes stay whole', () async {
      final project = await writeLoginProject();
      final config = File('${project.path}/.specstone/config.yaml');
      final before = config.readAsBytesSync();
      final session = openSession(project);
      addTearDown(session.close);
      final answer = answerContext(
        session.index,
        pickBundle(
          session.index,
          'login/email_login',
          BundleMode.implement,
          noProject: false,
        ),
        label: 'login/email_login',
        byCode: false,
      );
      expect(
        () => answerBundleFile(
          answer,
          config,
          project: session.project,
          isBare: false,
        ),
        throwsA(
          isA<RenderFault>()
              .having(
                (fault) => fault.code,
                'code',
                RenderFaultCode.outputNotWritable,
              )
              .having(
                (fault) => fault.message,
                'message',
                'the output path is inside .specstone/ but outside its '
                    'bundles/ and reports/',
              ),
        ),
      );
      expect(config.readAsBytesSync(), before);
    });
  });
}
