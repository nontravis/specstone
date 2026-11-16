// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_file.dart';
import 'package:specstone_core/src/index_query/bundle_render.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart'
    show ReadAnswer;
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

BundleEntry _entryOf(
  String name,
  int first,
  int last, {
  BundleEntryKind kind = BundleEntryKind.doc,
  bool summary = false,
  String? sectionKey,
  String? itemId,
  List<({String key, int first})> sections = const [],
}) => (
  doc: _doc(name),
  summary: summary,
  kind: kind,
  sectionKey: sectionKey,
  itemId: itemId,
  featurePattern: null,
  first: first,
  last: last,
  sections: sections,
);

/// Returns one file of [count] docs named `<prefix><n>`, each of one section
/// and one line, as [_answerOf] does.
BundleText _fileOf(int count, {String prefix = 'd'}) => (
  text: '${List.filled(2 * count, 'x').join('\n')}\n',
  tokens: 7,
  entries: [
    for (var i = 0; i < count; i++)
      _entryOf(
        '$prefix$i',
        2 * i + 1,
        2 * i + 1,
        sections: [(key: 'statement', first: 2 * i + 1)],
      ),
  ],
);

/// Returns a split answer whose read-first file holds [readFirst] docs and
/// whose refs file holds [refs] docs.
ContextAnswer _splitOf(
  int readFirst,
  int refs, {
  BundleMode? mode,
  BundleText? refsFile,
}) {
  final first = _fileOf(readFirst);
  return ContextAnswer(
    text: first.text,
    json: {'for': ?mode?.wire},
    entries: first.entries,
    tokens: first.tokens,
    refs: refsFile ?? _fileOf(refs, prefix: 'r'),
  );
}

/// Returns a refs file of [count] docs `r<n>`, each a naming line, one text
/// line, and one section, closed as a bundle text closes.
BundleText _closedRefsOf(int count) {
  final blocks = [
    for (var i = 0; i < count; i++)
      '==> r$i (fr) · prds/r$i.md <==\n## Statement\nx',
  ];
  final starts = [for (var i = 0; i < count; i++) 4 * i + 1];
  return (
    text:
        '${blocks.join('\n\n')}\n==> bundle: $count docs, 9 tokens <==\n'
        '${[for (var i = 0; i < count; i++) '- r$i (fr)\n'].join()}',
    tokens: 9,
    entries: [
      for (var i = 0; i < count; i++)
        _entryOf(
          'r$i',
          starts[i],
          starts[i] + 2,
          sections: [(key: 'statement', first: starts[i] + 1)],
        ),
    ],
  );
}

void main() {
  group('isBundlesFolderOf, the bundles folder right below a project root', () {
    test('a folder below a project root is the own folder', () {
      expect(
        isBundlesFolderOf('/p', '/p/.specstone/bundles', isWindows: false),
        isTrue,
      );
    });
    test('a project at a volume root has one separator before .specstone', () {
      expect(
        isBundlesFolderOf('/', '/.specstone/bundles', isWindows: false),
        isTrue,
      );
      expect(
        isBundlesFolderOf(r'C:\', r'C:\.specstone\bundles', isWindows: true),
        isTrue,
      );
    });
    test(
      'a folder a link leads elsewhere, or deeper, is not the own folder',
      () {
        expect(
          isBundlesFolderOf('/p', '/home/me/Documents', isWindows: false),
          isFalse,
        );
        expect(
          isBundlesFolderOf(
            '/p',
            '/p/.specstone/bundles/sub',
            isWindows: false,
          ),
          isFalse,
        );
        expect(isBundlesFolderOf('/p', '/p', isWindows: false), isFalse);
      },
    );
  });

  group('refsPathOf, the refs file of a path', () {
    test('a bare name takes .refs before .txt', () {
      expect(refsPathOf('a.implement.jaspr.txt'), 'a.implement.jaspr.refs.txt');
    });
    test('a named path takes .refs before its extension, or at its end when it has none', () {
      expect(refsPathOf('out/b.txt'), 'out/b.refs.txt');
      expect(refsPathOf('out/b'), 'out/b.refs');
    });
    test(
      'a dotted folder or a dot file has no extension to put .refs before',
      () {
        expect(refsPathOf('out.d/b'), 'out.d/b.refs');
        expect(refsPathOf('out/.bundle'), 'out/.bundle.refs');
      },
    );
  });

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

  group('bundleIndex and its --json of a split answer', () {
    ContextAnswer splitAnswer({String? codeTarget}) => ContextAnswer(
      text: 'a\nb\n\nc\n',
      json: const {},
      tokens: 5,
      codeTarget: codeTarget,
      entries: [
        _entryOf('one', 1, 2, sections: [(key: 'statement', first: 2)]),
        _entryOf('one', 4, 4, kind: BundleEntryKind.names),
      ],
      refs: (
        text: 'x\n\ny\nz\n',
        tokens: 3,
        entries: [
          _entryOf('two', 1, 1, summary: true),
          _entryOf(
            'three',
            3,
            3,
            kind: BundleEntryKind.cited,
            sectionKey: 'statement',
            itemId: 'E01',
            sections: [(key: 'statement', first: 3)],
          ),
          _entryOf(
            'one',
            4,
            4,
            kind: BundleEntryKind.citedBy,
            sectionKey: 'invariants',
            itemId: 'INV-14',
          ),
        ],
      ),
    );

    test('the index prints the read-first header and lines, then the refs header and lines, each counting its own file', () {
      expect(
        bundleIndex(splitAnswer(), '/p/b.txt', refsPath: '/p/b.refs.txt'),
        '==> bundle: 1 docs, 5 tokens, 4 lines · /p/b.txt <==\n'
        '- one (fr) · 1-2 · statement 2\n'
        '- one (fr) · 4-4 · names\n'
        '==> bundle: 1 docs, 3 tokens, 4 lines · /p/b.refs.txt <==\n'
        '- two (fr) · 1-1 · summary\n'
        '- three (fr) · 3-3 · cited statement [E01] · statement 3\n'
        '- one (fr) · 4-4 · cited by [INV-14]\n',
      );
    });
    test('a code target line comes first, before both headers', () {
      final index = bundleIndex(
        splitAnswer(codeTarget: 'jaspr'),
        '/p/b.txt',
        refsPath: '/p/b.refs.txt',
      );
      expect(
        index,
        startsWith('==> code target: jaspr <==\n==> bundle: 1 docs, 5'),
      );
      expect(index.split('==> code target').length, 2);
    });
    test('the index bound counts both files together: 200 lines keep every section', () {
      final index = bundleIndex(
        _splitOf(99, 99),
        '/p/b.txt',
        refsPath: '/p/b.refs.txt',
      );
      expect(const LineSplitter().convert(index), hasLength(200));
      expect(index, contains('- d98 (fr) · 197-197 · statement 197\n'));
      expect(index, contains('- r98 (fr) · 197-197 · statement 197\n'));
    });
    test('the index bound counts both files together: 201 lines drop the sections of both and keep every doc', () {
      final index = bundleIndex(
        _splitOf(100, 99),
        '/p/b.txt',
        refsPath: '/p/b.refs.txt',
      );
      final lines = const LineSplitter().convert(index);
      expect(lines, hasLength(201));
      expect(index, isNot(contains('statement')));
      expect(lines, contains('- d99 (fr) · 199-199'));
      expect(lines.last, '- r98 (fr) · 197-197');
    });

    test('--json adds a refs object of {out, tokens, lines, docs}, and docs hold docs and appended parts only', () {
      final json = bundleIndexJson(
        splitAnswer(),
        '/p/b.txt',
        refsPath: '/p/b.refs.txt',
      );
      expect(json.keys.toList(), ['out', 'tokens', 'lines', 'docs', 'refs']);
      expect(
        [for (final doc in json['docs']! as List) (doc as Map)['name']],
        ['one'],
      );
      final refs = json['refs']! as Map<String, Object?>;
      expect(refs.keys.toList(), ['out', 'tokens', 'lines', 'docs']);
      expect(refs['out'], '/p/b.refs.txt');
      expect(refs['tokens'], 3);
      expect(refs['lines'], 4);
      final docs = (refs['docs']! as List).cast<Map<String, Object?>>();
      expect([for (final doc in docs) doc['name']], ['two', 'three']);
      expect([for (final doc in docs) doc['cited']], [false, true]);
      expect(docs.first['summary'], isTrue);
    });
    test('an unsplit answer has no refs object and prints one header', () {
      final json = bundleIndexJson(_answerOf(1), '/p/b.txt');
      expect(json, isNot(contains('refs')));
      expect(
        '==> bundle: '.allMatches(bundleIndex(_answerOf(1), '/p/b.txt')),
        hasLength(1),
      );
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

  group('cited-by parts of a split design answer', () {
    const domain = 'docs/specs/f01_login/DOMAIN.md';
    const domainName = 'login (domain)';
    const link = '../f01_login/DOMAIN.md';
    const guide = 'docs/specs/topics/guide.md';

    /// Returns the split design answer on a guide that cites the login domain
    /// by [links], over a domain whose Entities section holds [entities].
    Future<ContextAnswer> splitWith(
      String links, {
      String entities = '### Account\nOne per email.\n',
    }) async {
      final index = await indexWith({
        domain:
            '# Login domain\n\n## Entities\n$entities\n## Invariants\n'
            '- **INV-1** An account locks after five failures.\n',
        guide: '# Guide\n\n## Purpose\n$links\n',
      });
      return answerContext(
        index,
        pickBundle(
          index,
          'login/email_login',
          BundleMode.design,
          noProject: false,
        ),
        label: 'login/email_login',
        byCode: false,
        split: true,
      );
    }

    /// Returns the cited-by parts of [answer]'s refs file that cite the domain.
    List<BundleEntry> domainParts(ContextAnswer answer) => [
      for (final e in answer.refs!.entries)
        if (e.kind == BundleEntryKind.citedBy &&
            e.doc.docPath == 'specs/f01_login/DOMAIN.md')
          e,
    ];

    /// Returns the naming line of the one cited-by part of the domain and the
    /// stdout index line that lists it.
    ({String naming, String listed}) lineOf(ContextAnswer answer) {
      final refs = answer.refs!;
      final entry = domainParts(answer).single;
      final index = bundleIndex(answer, '/p/b.txt', refsPath: '/p/b.refs.txt');
      return (
        naming: refs.text.split('\n')[entry.first - 1],
        listed: index
            .split('\n')
            .singleWhere(
              (l) => l.startsWith(
                '- $domainName · ${entry.first}-${entry.last} · ',
              ),
            ),
      );
    }

    test('a section part names its section and lists as #key', () async {
      final answer = await splitWith('See [entities]($link#entities).');

      final (:naming, :listed) = lineOf(answer);
      expect(
        naming,
        '==> $domainName · specs/f01_login/DOMAIN.md#entities · cited by <==',
      );
      expect(listed, matches(RegExp(r' · cited by \[#entities\]$')));
      expect(
        answer.refs!.text,
        contains('$naming\n  · cited by guide (topic) —: See [entities]'),
      );
      final entry = domainParts(answer).single;
      expect((entry.sectionKey, entry.itemId), ('entities', null));
    });

    test(
      'a whole-doc part names the doc alone and lists with no mark',
      () async {
        final answer = await splitWith('See [the domain]($link).');

        final (:naming, :listed) = lineOf(answer);
        expect(
          naming,
          '==> $domainName · specs/f01_login/DOMAIN.md · cited by <==',
        );
        expect(listed, matches(RegExp(r' · \d+-\d+ · cited by$')));
        final entry = domainParts(answer).single;
        expect((entry.sectionKey, entry.itemId), (null, null));
      },
    );

    test('a block part lists like an item', () async {
      final answer = await splitWith('See [an account]($link#account).');

      final (:naming, :listed) = lineOf(answer);
      expect(
        naming,
        '==> $domainName · specs/f01_login/DOMAIN.md#entities · item account · cited by <==',
      );
      expect(listed, matches(RegExp(r' · cited by \[account\]$')));
    });

    test('no cited-by part for a section left unprinted', () async {
      final answer = await splitWith(
        'See [entities]($link#entities).',
        entities: 'N/A — no entities yet\n',
      );

      expect(domainParts(answer), isEmpty);
      expect(answer.refs!.text, isNot(contains('cited by guide (topic)')));
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

  group('answerBundleFile writes the two files of a split answer', () {
    ContextAnswer splitAnswer(DocIndex index) => answerContext(
      index,
      pickBundle(
        index,
        'login/email_login',
        BundleMode.implement,
        noProject: false,
      ),
      label: 'login/email_login',
      byCode: false,
      split: true,
    );

    test(
      'both files are written, and the reply indexes both by canonical path',
      () async {
        final project = await writeLoginProject();
        final session = openSession(project);
        addTearDown(session.close);
        final answer = splitAnswer(session.index);
        final file = File('${project.path}/out/b.txt');
        final reply = answerBundleFile(
          answer,
          file,
          project: session.project,
          isBare: false,
        );
        final refs = File('${project.path}/out/b.refs.txt');
        expect(file.readAsStringSync(), answer.text);
        expect(refs.readAsStringSync(), startsWith('- '));
        expect(
          refs.readAsStringSync(),
          contains(
            answer.refs!.text.split('\n')[answer.refs!.entries.first.first - 1],
          ),
        );
        final shown = file.resolveSymbolicLinksSync();
        expect(reply.text, contains(' lines · $shown <==\n'));
        expect(
          reply.text,
          contains(' lines · ${refs.resolveSymbolicLinksSync()} <==\n'),
        );
        final json = reply.json;
        expect((json['refs']! as Map)['out'], refs.resolveSymbolicLinksSync());
      },
    );

    test(
      'a refs path that is the read-first file is refused and writes nothing',
      () async {
        final project = await writeLoginProject();
        final session = openSession(project);
        addTearDown(session.close);
        final out = Directory('${project.path}/out')..createSync();
        final file = File('${out.path}/b.txt')..writeAsStringSync('mine\n');
        Link('${out.path}/b.refs.txt').createSync(file.path);
        expect(
          () => answerBundleFile(
            splitAnswer(session.index),
            file,
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
                  'the refs file is the read-first file',
                ),
          ),
        );
        expect(file.readAsStringSync(), 'mine\n');
      },
      skip: Platform.isWindows ? 'a link needs a privilege on Windows' : null,
    );

    test('a refs path the writer refuses writes neither file', () async {
      final project = await writeLoginProject();
      final session = openSession(project);
      addTearDown(session.close);
      final bundles = Directory('${project.path}/.specstone/bundles')
        ..createSync(recursive: true);
      final config = File('${project.path}/.specstone/config.yaml');
      final before = config.readAsBytesSync();
      Link('${bundles.path}/b.refs.txt').createSync(config.path);
      final file = File('${bundles.path}/b.txt');
      expect(
        () => answerBundleFile(
          splitAnswer(session.index),
          file,
          project: session.project,
          isBare: false,
        ),
        throwsA(
          isA<RenderFault>().having(
            (fault) => fault.code,
            'code',
            RenderFaultCode.outputNotWritable,
          ),
        ),
      );
      expect(file.existsSync(), isFalse);
      expect(config.readAsBytesSync(), before);
    }, skip: Platform.isWindows ? 'a link needs a privilege on Windows' : null);
  });

  group('the implement refs file opens with its own index', () {
    final stdoutHeader = RegExp(
      r'^==> bundle: (\d+) docs, (\d+) tokens, (\d+) lines · (.+) <==$',
    );

    ContextAnswer answerOf(
      DocIndex index,
      BundleMode mode, {
      bool noProject = false,
    }) => answerContext(
      index,
      pickBundle(index, 'login/email_login', mode, noProject: noProject),
      label: 'login/email_login',
      byCode: false,
      split: true,
    );

    /// Writes [mode]'s files for the login project and returns the refs
    /// file's lines, the stdout reply, and the answer that was written.
    Future<({List<String> lines, ReadAnswer reply, ContextAnswer answer})>
    written(
      BundleMode mode, {
      bool noProject = false,
      Map<String, String> extra = _layoutDocs,
    }) async {
      final project = await writeLoginProject(extra: extra);
      final session = openSession(project);
      addTearDown(session.close);
      final answer = answerOf(session.index, mode, noProject: noProject);
      final reply = answerBundleFile(
        answer,
        File('${project.path}/out/b.txt'),
        project: session.project,
        isBare: false,
      );
      return (
        lines: File('${project.path}/out/b.refs.txt').readAsLinesSync(),
        reply: reply,
        answer: answer,
      );
    }

    test('implement stdout prints the refs header line alone', () {
      final index = bundleIndex(
        _splitOf(2, 3, mode: BundleMode.implement),
        '/p/b.txt',
        refsPath: '/p/b.refs.txt',
      );
      expect(
        index,
        '==> bundle: 2 docs, 7 tokens, 4 lines · /p/b.txt <==\n'
        '- d0 (fr) · 1-1 · statement 1\n'
        '- d1 (fr) · 3-3 · statement 3\n'
        '==> bundle: 3 docs, 7 tokens, 6 lines · /p/b.refs.txt <==\n',
      );
    });

    test('each refs head range opens on its doc naming line', () async {
      final (:lines, :reply, :answer) = await written(BundleMode.implement);
      final head = lines.takeWhile((line) => line.startsWith('- ')).toList();
      expect(head, hasLength(answer.refs!.entries.length));
      expect(lines[head.length], isEmpty);
      for (final line in head) {
        final parsed = RegExp(r'^- (.+?) · (\d+)-(\d+)(?: · (.*))?$')
            .firstMatch(line)!;
        final first = int.parse(parsed.group(2)!);
        final last = int.parse(parsed.group(3)!);
        expect(
          lines[first - 1],
          startsWith('==> ${parsed.group(1)} · '),
          reason: line,
        );
        expect(
          lines[last],
          anyOf('', startsWith('==> bundle: ')),
          reason: line,
        );
        for (final section in RegExp(
          r'[a-z_]+ (\d+)(?=,|$)',
        ).allMatches(parsed.group(4) ?? '')) {
          expect(
            lines[int.parse(section.group(1)!) - 1],
            startsWith('## '),
            reason: line,
          );
        }
      }
    });

    test('the refs header and json count the head', () async {
      final (:lines, :reply, :answer) = await written(BundleMode.implement);
      final text = '${lines.join('\n')}\n';
      final closing = text.lastIndexOf('\n==> bundle: ') + 1;
      final tokens = tokenSizeOf(text.substring(0, closing - 1));
      final header = stdoutHeader.firstMatch(
        reply.text.split('\n').lastWhere((line) => line.contains('.refs.txt')),
      )!;
      expect(header.group(2), '$tokens');
      expect(header.group(3), '${lines.length}');
      final refs = reply.json['refs']! as Map<String, Object?>;
      expect((refs['tokens'], refs['lines']), (tokens, lines.length));
      expect(
        lines.singleWhere((line) => line.startsWith('==> bundle: ')),
        '==> bundle: ${header.group(1)} docs, $tokens tokens <==',
      );
      expect(tokens, greaterThan(answer.refs!.tokens));
    });

    test('the implement cap counts the read-first index alone', () {
      final fits = bundleIndex(
        _splitOf(199, 150, mode: BundleMode.implement),
        '/p/b.txt',
        refsPath: '/p/b.refs.txt',
      );
      expect(fits, contains('- d198 (fr) · 397-397 · statement 397\n'));
      expect(fits, endsWith('.refs.txt <==\n'));
      final past = bundleIndex(
        _splitOf(200, 1, mode: BundleMode.implement),
        '/p/b.txt',
        refsPath: '/p/b.refs.txt',
      );
      expect(past, isNot(contains('statement')));
      expect(past, contains('- d199 (fr) · 399-399\n'));
    });

    test('past the cap the implement refs head still lists sections', () async {
      final project = await writeLoginProject();
      final session = openSession(project);
      addTearDown(session.close);
      final answer = _splitOf(
        201,
        0,
        mode: BundleMode.implement,
        refsFile: _closedRefsOf(3),
      );
      final reply = answerBundleFile(
        answer,
        File('${project.path}/out/b.txt'),
        project: session.project,
        isBare: false,
      );
      expect(reply.text, isNot(contains('statement')));
      final lines = File('${project.path}/out/b.refs.txt').readAsLinesSync();
      expect(lines[0], '- r0 (fr) · 5-7 · statement 6');
      expect(lines[2], '- r2 (fr) · 13-15 · statement 14');
      expect(lines[4], '==> r0 (fr) · prds/r0.md <==');
    });

    test('design keeps both indexes on stdout and no head', () async {
      final (:lines, :reply, :answer) = await written(BundleMode.design);
      expect(lines.join('\n'), answer.refs!.text.trimRight());
      final stdout = reply.text.split('\n');
      final refsHeader = stdout.indexWhere(
        (line) => line.contains('.refs.txt'),
      );
      final first = answer.refs!.entries.first;
      expect(
        stdout
            .skip(refsHeader + 1)
            .any((line) => line.contains(' · ${first.first}-${first.last}')),
        isTrue,
      );
      expect(lines[first.first - 1], startsWith('==> '));
    });

    test('an empty refs file stays the empty closing text with no head', () async {
      final project = await writeLoginProject();
      final session = openSession(project);
      addTearDown(session.close);
      const empty = '==> bundle: 0 docs, 0 tokens <==\n';
      final answer = _splitOf(
        2,
        0,
        mode: BundleMode.implement,
        refsFile: (text: empty, tokens: 0, entries: const []),
      );
      final reply = answerBundleFile(
        answer,
        File('${project.path}/out/b.txt'),
        project: session.project,
        isBare: false,
      );
      expect(File('${project.path}/out/b.refs.txt').readAsStringSync(), empty);
      expect(
        reply.text,
        endsWith(
          '1 lines · ${project.resolveSymbolicLinksSync()}/out/b.refs.txt <==\n',
        ),
      );
    });
  });
}
