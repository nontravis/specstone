// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_file.dart';
import 'package:specstone_core/src/index_query/bundle_render.dart';
import 'package:specstone_core/src/index_query/code_bundle.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/models/bundle_entry.dart';
import 'package:specstone_core/src/index_query/models/bundle_text.dart';
import 'package:specstone_core/src/index_query/models/read_plan.dart';
import 'package:specstone_core/src/index_query/read_answer.dart'
    show ReadAnswer, nameWithType;
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
      BundleEntry(
        doc: _doc('d$i'),
        summary: false,
        kind: BundleEntryKind.doc,
        sectionKey: null,
        itemId: null,
        featurePattern: null,
        first: 2 * i + 1,
        last: 2 * i + 1,
        sections: [
          for (var s = 0; s < sections; s++)
            EntrySection(key: '$key$s', first: 2 * i + 1),
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
  List<EntrySection> sections = const [],
}) => BundleEntry(
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
BundleText _fileOf(int count, {String prefix = 'd'}) => BundleText(
  text: '${List.filled(2 * count, 'x').join('\n')}\n',
  tokens: 7,
  entries: [
    for (var i = 0; i < count; i++)
      _entryOf(
        '$prefix$i',
        2 * i + 1,
        2 * i + 1,
        sections: [EntrySection(key: 'statement', first: 2 * i + 1)],
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
  return BundleText(
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
          sections: [EntrySection(key: 'statement', first: starts[i] + 1)],
        ),
    ],
  );
}

/// Returns a line of [tokens] est. tokens, four characters each.
String _lineOf(int tokens) => 'x' * (4 * tokens);

/// Returns one block of a read-first file: its naming line, then [body].
List<String> _blockOf(int index, List<String> body) => [
  '==> p$index (fr) · prds/p$index.md <==',
  ...body,
];

/// Returns a read-first file of [blocks] joined by a blank line, after the
/// [head] lines, closed by a closing line and a list, with one entry per block.
BundleText _planFileOf(
  List<List<String>> blocks, {
  List<String> head = const [],
}) {
  final lines = [...head];
  final entries = <BundleEntry>[];
  for (final (i, block) in blocks.indexed) {
    if (i > 0) lines.add('');
    final first = lines.length + 1;
    lines.addAll(block);
    entries.add(_entryOf('p$i', first, lines.length));
  }
  lines
    ..add('==> bundle: ${blocks.length} docs, 1 tokens <==')
    ..add('- p0 (fr)');
  final text = '${lines.join('\n')}\n';
  return BundleText(text: text, entries: entries, tokens: tokenSizeOf(text));
}

int _lineCountOfText(BundleText file) =>
    const LineSplitter().convert(file.text).length;

List<List<int>> _pairsOf(ReadPlan plan) => [
  for (final range in plan.ranges) [range.first, range.last],
];

void main() {
  group('readPlanOf, the read ranges of a read-first file', () {
    test('a file within the limit is one range of every line', () {
      final file = _planFileOf([
        _blockOf(0, [_lineOf(100)]),
        _blockOf(1, [_lineOf(100)]),
        _blockOf(2, [_lineOf(100)]),
      ]);
      final plan = readPlanOf(file);
      expect(_pairsOf(plan), [
        [1, _lineCountOfText(file)],
      ]);
      expect(plan.overLimitLines, isEmpty);
    });

    test('a 30k-token file of small parts gives two ranges split at an entry start', () {
      final file = _planFileOf([
        for (var i = 0; i < 6; i++) _blockOf(i, [_lineOf(4975)]),
      ]);
      final fifth = file.entries[4].first;
      expect(_pairsOf(readPlanOf(file)), [
        [1, fifth - 1],
        [fifth, _lineCountOfText(file)],
      ]);
    });

    test('a part over the limit cuts before its last fitting heading outside fenced code', () {
      final file = _planFileOf([
        _blockOf(0, [
          '## A',
          _lineOf(10000),
          '## B',
          _lineOf(10000),
          '## C',
          _lineOf(3000),
          '```markdown',
          '## Fake',
          '```',
          _lineOf(10000),
        ]),
        _blockOf(1, ['small']),
      ]);
      final lines = file.text.split('\n');
      final heading = lines.indexOf('## C') + 1;
      expect(lines.indexOf('## Fake') + 1, greaterThan(heading));
      expect(_pairsOf(readPlanOf(file)), [
        [1, heading - 1],
        [heading, _lineCountOfText(file)],
      ]);
    });

    test(
      'an oversized part with no fitting heading cuts at its last fitting line',
      () {
        final file = _planFileOf([
          _blockOf(0, [for (var i = 0; i < 6; i++) _lineOf(5000)]),
          _blockOf(1, ['small']),
        ]);
        expect(_pairsOf(readPlanOf(file)), [
          [1, 5],
          [6, _lineCountOfText(file)],
        ]);
      },
    );

    test('a lone oversized line gets a range of its own and is listed', () {
      final file = _planFileOf([
        _blockOf(0, ['a', _lineOf(125000), 'b']),
        _blockOf(1, ['small']),
      ]);
      final plan = readPlanOf(file);
      expect(_pairsOf(plan), [
        [1, 2],
        [3, 3],
        [4, _lineCountOfText(file)],
      ]);
      expect(plan.overLimitLines, [3]);
    });

    test('a code target line on line 1 starts the first range', () {
      final file = _planFileOf(
        [
          for (var i = 0; i < 6; i++) _blockOf(i, [_lineOf(4975)]),
        ],
        head: ['==> code target: jaspr <=='],
      );
      final pairs = _pairsOf(readPlanOf(file));
      expect(file.entries.first.first, 2);
      expect(pairs.first.first, 1);
      expect(pairs, hasLength(2));
      expect(pairs.first.last, file.entries[4].first - 1);
      expect(pairs.last.last, _lineCountOfText(file));
    });
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
    test('a target and its mode', () {
      expect(
        bundleFileName(
          targets: ['index_query/get_task_bundle'],
          mode: BundleMode.design,
          summary: false,
          noProject: false,
        ),
        'index_query-get_task_bundle.design.txt',
      );
    });
    test('a --code path takes code- and each separator written -', () {
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
    test('--target adds its name before .txt', () {
      expect(
        bundleFileName(
          targets: ['feedback/toast/show_toast'],
          mode: BundleMode.implement,
          summary: false,
          noProject: false,
          codeTarget: 'jaspr',
        ),
        'feedback-toast-show_toast.implement.jaspr.txt',
      );
    });
    test('--summary and --no-project follow the mode', () {
      expect(
        bundleFileName(
          targets: ['login'],
          mode: BundleMode.design,
          summary: true,
          noProject: true,
        ),
        'login.design-summary-no-project.txt',
      );
      expect(
        bundleFileName(
          targets: ['login'],
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
          targets: ['architecture:login'],
          mode: BundleMode.implement,
          summary: false,
          noProject: false,
        ),
        'architecture-login.implement.txt',
      );
    });

    String longName(String codePath, BundleMode mode, {String? codeTarget}) =>
        bundleFileName(
          codePath: codePath,
          mode: mode,
          summary: false,
          noProject: false,
          codeTarget: codeTarget,
        );

    int bytesOf(String text) => utf8.encode(text).length;

    test('a 300-byte name keeps its head and ends in a hash', () {
      final path = 'a' * 295;
      final name = longName(path, BundleMode.implement);
      final uncut = 'code-$path.implement.txt';
      expect(bytesOf(name), lessThanOrEqualTo(250));
      expect(name, matches(RegExp(r'^code-a+-[0-9a-f]{8}\.implement\.txt$')));
      expect(
        name,
        contains(
          '-${sha256.convert(utf8.encode(uncut)).toString().substring(0, 8)}.',
        ),
      );
    });

    test('an implement name whose refs name would pass 255 bytes is cut', () {
      final name = longName('a' * 234, BundleMode.implement);
      expect(bytesOf('code-${'a' * 234}.implement.txt'), 253);
      expect(bytesOf(name), lessThanOrEqualTo(250));
      expect(name, endsWith('.implement.txt'));
    });

    test('a query name of 253 bytes keeps its name', () {
      final path = 'a' * 238;
      final uncut = 'code-$path.query.txt';
      expect(bytesOf(uncut), 253);
      expect(longName(path, BundleMode.query), uncut);
    });

    test('a name of 250 bytes keeps its name in every mode', () {
      for (final mode in BundleMode.values) {
        final path = 'a' * (250 - 'code-'.length - '.${mode.wire}.txt'.length);
        final uncut = 'code-$path.${mode.wire}.txt';
        expect(bytesOf(uncut), 250);
        expect(longName(path, mode), uncut, reason: mode.wire);
      }
    });

    test('a --target part stays after the hash', () {
      final name = longName(
        'a' * 295,
        BundleMode.implement,
        codeTarget: 'jaspr',
      );
      expect(name, endsWith('.implement.jaspr.txt'));
      expect(bytesOf(name), lessThanOrEqualTo(250));
    });

    test('a multibyte target is cut on a code point boundary', () {
      for (final character in ['\u65e5', '\u{1F600}']) {
        final name = bundleFileName(
          targets: [character * 100],
          mode: BundleMode.implement,
          summary: false,
          noProject: false,
        );
        expect(utf8.decode(utf8.encode(name)), name);
        expect(bytesOf(name), lessThanOrEqualTo(250));
        expect(name, endsWith('.implement.txt'));
      }
    });

    test('two targets join with a plus in the order given', () {
      String nameOf(List<String> targets, {String? codeTarget}) =>
          bundleFileName(
            targets: targets,
            mode: BundleMode.design,
            summary: false,
            noProject: false,
            codeTarget: codeTarget,
          );
      const trim = 'index_query/task_bundle/trim_task_bundle';
      const get = 'index_query/task_bundle/get_task_bundle';
      expect(
        nameOf([get, trim]),
        'index_query-task_bundle-get_task_bundle+'
        'index_query-task_bundle-trim_task_bundle.design.txt',
      );
      expect(
        nameOf([trim, get]),
        'index_query-task_bundle-trim_task_bundle+'
        'index_query-task_bundle-get_task_bundle.design.txt',
      );
      expect(
        nameOf(['login', 'architecture:login'], codeTarget: 'jaspr'),
        'login+architecture-login.design.jaspr.txt',
      );
    });

    test('a joined name past 255 bytes is cut as one name', () {
      final first = 'a' * 150;
      final second = 'b' * 150;
      final name = bundleFileName(
        targets: [first, second],
        mode: BundleMode.implement,
        summary: false,
        noProject: false,
      );
      final uncut = '$first+$second.implement.txt';
      final hash = sha256
          .convert(utf8.encode(uncut))
          .toString()
          .substring(0, 8);
      expect(bytesOf(name), lessThanOrEqualTo(250));
      expect(
        name,
        matches(RegExp(r'^a{150}\+b+-[0-9a-f]{8}\.implement\.txt$')),
      );
      expect(name, endsWith('-$hash.implement.txt'));
    });
  });

  group('bundleIndex', () {
    test('the header, then each doc and part as <name> (<doc type>) · <first>-<last>, marks after the range', () {
      final answer = ContextAnswer(
        text: 'a\nb\nc\n\nd\ne\n\nf\n\ng\n\nh\n\ni\n',
        json: const {},
        entries: [
          BundleEntry(
            doc: _doc('one'),
            summary: false,
            kind: BundleEntryKind.doc,
            sectionKey: null,
            itemId: null,
            featurePattern: null,
            first: 1,
            last: 3,
            sections: const [
              EntrySection(key: 'statement', first: 2),
              EntrySection(key: 'edge_cases', first: 3),
            ],
          ),
          BundleEntry(
            doc: _doc('two'),
            summary: false,
            kind: BundleEntryKind.cited,
            sectionKey: 'statement',
            itemId: null,
            featurePattern: null,
            first: 5,
            last: 6,
            sections: const [EntrySection(key: 'statement', first: 5)],
          ),
          BundleEntry(
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
          BundleEntry(
            doc: _doc('four'),
            summary: true,
            kind: BundleEntryKind.doc,
            sectionKey: null,
            itemId: null,
            featurePattern: null,
            first: 10,
            last: 10,
            sections: const [EntrySection(key: 'use_case', first: 10)],
          ),
          BundleEntry(
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
          const BundleEntry(
            doc: IndexedDoc(
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
            sections: [],
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
    test('a code target prints its line before the header, and --json holds codeTarget', () {
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

    test('a code target line, the header, and 198 entries make 200 lines and keep their sections', () {
      final index = bundleIndex(withTarget(_answerOf(198)), '/p');
      expect(const LineSplitter().convert(index), hasLength(200));
      expect(index, contains('- d197 (fr) · 395-395 · statement0 395\n'));
    });
    test('a code target line, the header, and 199 entries pass 200 lines and drop the sections', () {
      final index = bundleIndex(withTarget(_answerOf(199)), '/p');
      expect(const LineSplitter().convert(index), hasLength(201));
      expect(index, contains('- d198 (fr) · 397-397\n'));
      expect(index, isNot(contains('statement0')));
    });

    test('an index of 200 lines keeps its sections', () {
      final index = bundleIndex(_answerOf(199), '/p');
      expect(const LineSplitter().convert(index), hasLength(200));
      expect(index, contains('- d198 (fr) · 397-397 · statement0 397\n'));
    });
    test('an index past 200 lines lists every doc and no section', () {
      final index = bundleIndex(_answerOf(200), '/p');
      final lines = const LineSplitter().convert(index);
      expect(lines, hasLength(201));
      expect(lines[1], '- d0 (fr) · 1-1');
      expect(lines.last, '- d199 (fr) · 399-399');
      expect(index, isNot(contains('statement')));
    });
    test('an index past 8 KiB lists every doc and no section', () {
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
    test('an index of exactly 8,192 bytes keeps its sections', () {
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

    test("the plan prints second, under the first file's header, in implement and design", () {
      for (final mode in [BundleMode.implement, BundleMode.design]) {
        final index = bundleIndex(
          _splitOf(2, 2, mode: mode),
          '/p/b.txt',
          refsPath: '/p/b.refs.txt',
        );
        final lines = const LineSplitter().convert(index);
        expect(lines[0], startsWith('==> bundle: 2 docs, 7 tokens, 4 lines'));
        expect(lines[1], 'read whole, in 1 read: lines 1-4');
        expect('read whole'.allMatches(index), hasLength(1));
      }
      final refsHeader = bundleIndex(
        _splitOf(2, 2, mode: BundleMode.design),
        '/p/b.txt',
        refsPath: '/p/b.refs.txt',
      ).split('\n').indexWhere((line) => line.contains('b.refs.txt'));
      expect(refsHeader, greaterThan(2));
      final query = ContextAnswer(
        text: 'x\n',
        json: {'for': BundleMode.query.wire},
        entries: [_entryOf('d0', 1, 1)],
        tokens: 1,
      );
      expect(bundleIndex(query, '/p/b.txt'), isNot(contains('read whole')));
    });
    test('an index past the line bound lists docs only and keeps the read plan line', () {
      final kept = bundleIndex(
        _splitOf(198, 1, mode: BundleMode.implement),
        '/p/b.txt',
        refsPath: '/p/b.refs.txt',
      );
      expect(const LineSplitter().convert(kept), hasLength(201));
      expect(kept, contains('- d197 (fr) · 395-395 · statement 395\n'));
      final dropped = bundleIndex(
        _splitOf(199, 1, mode: BundleMode.implement),
        '/p/b.txt',
        refsPath: '/p/b.refs.txt',
      );
      final lines = const LineSplitter().convert(dropped);
      expect(lines[1], 'read whole, in 1 read: lines 1-398');
      expect(dropped, isNot(contains('statement')));
      expect(lines, contains('- d198 (fr) · 397-397'));
    });
  });

  group('bundleIndex and its --json hold each feature pattern part', () {
    BundleEntry docEntry(String name, int first, int last) => BundleEntry(
      doc: _doc(name),
      summary: false,
      kind: BundleEntryKind.doc,
      sectionKey: null,
      itemId: null,
      featurePattern: null,
      first: first,
      last: last,
      sections: [EntrySection(key: 'statement', first: first)],
    );
    BundleEntry partEntry(String id, int first, int last) => BundleEntry(
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
        'read whole, in 1 read: lines 1-8\n'
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
        'reads',
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
        _entryOf(
          'one',
          1,
          2,
          sections: [const EntrySection(key: 'statement', first: 2)],
        ),
        _entryOf('one', 4, 4, kind: BundleEntryKind.names),
      ],
      refs: BundleText(
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
            sections: [const EntrySection(key: 'statement', first: 3)],
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
    test('the read-first object carries reads, one pair per range, and the refs object carries none', () {
      final json = bundleIndexJson(
        _splitOf(2, 2, mode: BundleMode.design),
        '/p/b.txt',
        refsPath: '/p/b.refs.txt',
      );
      expect(json['reads'], [
        [1, 4],
      ]);
      expect(json['refs'], isNot(contains('reads')));
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
            ['login/email_login'],
            BundleMode.implement,
            noProject: false,
          ),
          targets: ['login/email_login'],
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
            ['login'],
            BundleMode.design,
            noProject: false,
            summary: true,
          ),
          targets: ['login'],
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
          ['login/email_login'],
          BundleMode.implement,
          noProject: false,
        ),
        targets: ['login/email_login'],
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
        pickBundle(index, ['project'], BundleMode.implement, noProject: false),
        targets: ['project'],
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
          ['login/email_login'],
          BundleMode.implement,
          noProject: false,
        ),
        targets: ['login/email_login'],
        budget: 1,
      );
      expect(answer.exitStatus, 1);
      expect(answer.entries, isEmpty);
    });
  });

  group('ancestor spec pieces in the index and its --json', () {
    const apiPath = 'docs/specs/f01_login/API.md';
    const domainPath = 'docs/specs/f01_login/DOMAIN.md';
    const frPath =
        'docs/prds/features/f01_login/us01_email_login/fr01_validate_credentials.md';

    Future<ContextAnswer> designLogin({required bool split}) async {
      final index = await indexWith({
        frPath:
            '# Validate credentials\n\n## Statement\nThe system shall check '
            'the email, by [INV-1](../../../../specs/f01_login/DOMAIN.md#invariants).\n',
        domainPath:
            '# Login domain\n\n## Invariants\n- **INV-1** An account has an email.\n'
            '- **INV-2** An account has a password.\n',
        apiPath:
            '# Login API\n\n## FR trace\n| FR | Operation |\n|----|-----------|\n'
            '| [validate](../../prds/features/f01_login/us01_email_login/fr01_validate_credentials.md) | `signIn` |\n'
            '| other | `signOut` |\n',
      });
      return answerContext(
        index,
        pickBundle(
          index,
          ['login/email_login'],
          BundleMode.design,
          noProject: false,
        ),
        targets: ['login/email_login'],
        split: split,
      );
    }

    List<Map<String, Object?>> docsOf(
      Map<String, Object?> json,
      String name,
    ) => [
      for (final doc in (json['docs']! as List).cast<Map<String, Object?>>())
        if (doc['name'] == name) doc,
    ];

    test('the read-first index lists an outbound piece as cited and an inbound one as cites', () async {
      final answer = await designLogin(split: true);
      final lines = bundleIndex(answer, '/p', refsPath: '/p.refs').split('\n');

      expect(
        lines.where(
          RegExp(r'^- login \(domain\) · \d+-\d+ · cited invariants \[INV-1\]')
              .hasMatch,
        ),
        hasLength(1),
      );
      expect(
        lines.where(
          RegExp(r'^- login \(api\) · \d+-\d+ · cites fr_trace').hasMatch,
        ),
        hasLength(1),
      );
    });
    test(
      'the read-first index line of a lead paragraph piece ends at cites',
      () async {
        final index = await indexWith({
          domainPath:
              '# Login domain\n\nThis doc backs [validate](../../prds/features/f01_login/us01_email_login/fr01_validate_credentials.md).\n\n'
              '## Invariants\n- **INV-1** An account has an email.\n',
        });
        final answer = answerContext(
          index,
          pickBundle(
            index,
            ['login/email_login'],
            BundleMode.design,
            noProject: false,
          ),
          targets: ['login/email_login'],
          split: true,
        );
        final lines = bundleIndex(
          answer,
          '/p',
          refsPath: '/p.refs',
        ).split('\n');

        expect(
          lines.where(
            RegExp(r'^- login \(domain\) · \d+-\d+ · cites$').hasMatch,
          ),
          hasLength(1),
        );
      },
    );
    test('the out json marks an inbound piece cites and not cited', () async {
      final answer = await designLogin(split: true);
      final json = bundleIndexJson(answer, '/p', refsPath: '/p.refs');

      final [inbound] = docsOf(
        json,
        'login',
      ).where((doc) => doc['docType'] == 'api').toList();
      expect(inbound, containsPair('cited', false));
      expect(inbound, containsPair('cites', true));
      expect(inbound, isNot(contains('section')));
      expect(inbound, isNot(contains('item')));
      final [outbound] = docsOf(
        json,
        'login',
      ).where((doc) => doc['docType'] == 'domain').toList();
      expect(outbound, containsPair('cited', true));
      expect(outbound, isNot(contains('cites')));
    });
    test('the refs file holds the domain and the api whole, indexed with no cited or cites mark', () async {
      final answer = await designLogin(split: true);
      final index = bundleIndex(answer, '/p', refsPath: '/p.refs');
      final refsLines = index.split('/p.refs <==\n').last.split('\n');

      expect(
        answer.refs!.text,
        allOf(
          contains('- **INV-2** An account has a password.'),
          contains('| other | `signOut` |'),
        ),
        reason: 'the unlinked invariant and row print too',
      );
      final firstLines = index.split('/p.refs <==\n').first.split('\n');
      expect(
        firstLines.where(
          RegExp(r'^- login \(domain\) · \d+-\d+ · cited invariants \[INV-1\]')
              .hasMatch,
        ),
        hasLength(1),
      );
      expect(
        firstLines.where(
          RegExp(r'^- login \(api\) · \d+-\d+ · cites fr_trace').hasMatch,
        ),
        hasLength(1),
      );
      final json = bundleIndexJson(answer, '/p', refsPath: '/p.refs');
      final api = (json['docs']! as List)
          .cast<Map<String, Object?>>()
          .singleWhere((d) => d['name'] == 'login' && d['docType'] == 'api');
      expect(api, containsPair('cited', false));
      expect(api, containsPair('cites', true));
      for (final type in ['domain', 'api']) {
        final lines = refsLines.where((l) => l.startsWith('- login ($type)'));
        expect(lines, hasLength(1), reason: type);
        expect(lines.single, matches(RegExp(r'^- login \(\w+\) · \d+-\d+')));
        expect(lines.single, isNot(contains('cite')), reason: type);
      }
    });
    test('a --code design bundle written with --out lists no piece, and each spec doc prints whole', () async {
      final project = await writeLoginProject(
        extra: {
          ...loginRecords,
          frPath:
              '# Validate credentials\n\n## Statement\nThe system shall check '
              'the email, by [INV-1](../../../../specs/f01_login/DOMAIN.md#invariants).\n',
          domainPath:
              '# Login domain\n\n## Invariants\n- **INV-1** An account has an email.\n'
              '- **INV-2** An account has a password.\n',
          apiPath:
              '# Login API\n\n## FR trace\n| FR | Operation |\n|----|-----------|\n'
              '| [validate](../../prds/features/f01_login/us01_email_login/fr01_validate_credentials.md) | `signIn` |\n'
              '| other | `signOut` |\n',
        },
      );
      final session = openSession(project);
      addTearDown(session.close);
      const path = 'app/lib/src/login/credential_validator.dart';
      final bundle = pickCodeBundle(
        session.index,
        resolveCodePath(
          path,
          workingDirectory: project,
          targets: session.project.targets,
          codeRootOf: session.project.codeRootOf,
          projectRoot: session.project.projectRoot,
          reachedFromProjectRoot: (_) => false,
        ),
        BundleMode.design,
        noProject: false,
      );

      final answer = answerCodeContext(
        session.index,
        bundle,
        label: path,
        split: true,
      );

      final entries = [...answer.entries, ...?answer.refs?.entries];
      expect(
        entries.where(
          (e) =>
              e.kind == BundleEntryKind.cites ||
              (e.kind == BundleEntryKind.cited &&
                  {'domain', 'api'}.contains(e.doc.docTypeId)),
        ),
        isEmpty,
        reason: 'no ancestor spec piece',
      );
      final wholeSpecs = [
        for (final e in entries)
          if (e.kind == BundleEntryKind.doc &&
              {'domain', 'api'}.contains(e.doc.docTypeId))
            e.doc.docTypeId,
      ];
      expect(wholeSpecs, unorderedEquals(['domain', 'api']));
      final text = '${answer.text}${answer.refs?.text}';
      expect(text, contains('- **INV-2** An account has a password.'));
      expect(text, contains('| other | `signOut` |'));
    });
    test('a design json call with no out lists no piece', () async {
      final answer = await designLogin(split: false);

      expect(
        answer.entries.where((e) => e.kind == BundleEntryKind.cites),
        isEmpty,
      );
      final docs = (answer.json['docs']! as List).cast<Map<String, Object?>>();
      final ancestors = docs.where((doc) => doc['name'] == 'login').toList();
      expect(
        ancestors.map((doc) => doc['docType']),
        containsAll(['api', 'domain']),
      );
      for (final doc in ancestors) {
        expect(doc, isNot(contains('cites')));
        expect(doc, isNot(contains('cited')));
        expect(doc, isNot(contains('item')));
      }
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
          ['login/email_login'],
          BundleMode.design,
          noProject: false,
        ),
        targets: ['login/email_login'],
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
        contains('$naming\n  · cited by guide (topic) — #purpose\n'),
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
          ['login/email_login'],
          BundleMode.implement,
          noProject: false,
        ),
        targets: ['login/email_login'],
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
        ['login/email_login'],
        BundleMode.implement,
        noProject: false,
      ),
      targets: ['login/email_login'],
      split: true,
    );

    test('both files are written, and the reply indexes both by canonical path', () async {
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
      final original = answer.refs!;
      final originalLines = original.text.split('\n');
      final blocksEnd = original.entries.last.last;
      final count = original.entries.length;
      final written = refs.readAsStringSync().split('\n');
      for (final (i, entry) in original.entries.indexed) {
        final first = entry.first + count + 1;
        final last = entry.last + count + 1;
        expect(
          written[i],
          startsWith('- ${nameWithType(entry.doc)} · $first-$last'),
        );
      }
      final tokens = tokenSizeOf(
        written.take(count + 1 + blocksEnd).join('\n'),
      );
      expect(written.skip(count), [
        '',
        ...originalLines.take(blocksEnd),
        '==> bundle: ${docCountOf(original.entries)} docs, $tokens tokens <==',
        ...originalLines.skip(blocksEnd + 1),
      ]);
      final shown = file.resolveSymbolicLinksSync();
      expect(reply.text, contains(' lines · $shown <==\n'));
      expect(
        reply.text,
        contains(' lines · ${refs.resolveSymbolicLinksSync()} <==\n'),
      );
      final json = reply.json;
      expect((json['refs']! as Map)['out'], refs.resolveSymbolicLinksSync());
    });

    test('the read plan is not written into the file', () async {
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
      final written = file.readAsStringSync();
      expect(written, answer.text);
      expect(written, isNot(contains('read whole')));
      final lines = const LineSplitter().convert(written).length;
      expect(
        reply.text,
        contains(
          '==> bundle: ${docCountOf(answer.entries)} docs, '
          '${answer.tokens} tokens, $lines lines · ',
        ),
      );
      expect(reply.text, contains('\nread whole, in 1 read: lines 1-$lines\n'));
    });

    test(
      'a line over the limit warns once with its line, path, and size',
      () async {
        final project = await writeLoginProject();
        final session = openSession(project);
        addTearDown(session.close);
        final text = 'a\n${_lineOf(100000)}\nb\n';
        final answer = ContextAnswer(
          text: text,
          json: {'for': BundleMode.design.wire},
          entries: [_entryOf('d0', 1, 3)],
          tokens: tokenSizeOf(text),
        );
        final file = File('${project.path}/out/b.txt');
        final reply = answerBundleFile(
          answer,
          file,
          project: session.project,
          isBare: false,
        );
        final shown = file.resolveSymbolicLinksSync();
        const tail = 'est. tokens, more than one read holds';
        expect(reply.warnings, [
          '⚠️ WARNING: line 2 of $shown holds 100000 $tail',
        ]);
        expect(
          reply.text,
          contains('read whole, in 3 reads: lines 1-1, lines 2-2, lines 3-3\n'),
        );
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
      pickBundle(index, ['login/email_login'], mode, noProject: noProject),
      targets: ['login/email_login'],
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
        'read whole, in 1 read: lines 1-4\n'
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
        _splitOf(198, 150, mode: BundleMode.implement),
        '/p/b.txt',
        refsPath: '/p/b.refs.txt',
      );
      expect(fits, contains('- d197 (fr) · 395-395 · statement 395\n'));
      expect(fits, endsWith('.refs.txt <==\n'));
      final past = bundleIndex(
        _splitOf(199, 1, mode: BundleMode.implement),
        '/p/b.txt',
        refsPath: '/p/b.refs.txt',
      );
      expect(past, isNot(contains('statement')));
      expect(past, contains('- d198 (fr) · 397-397\n'));
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
        refsFile: const BundleText(text: empty, tokens: 0, entries: []),
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
