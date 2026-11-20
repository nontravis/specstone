// The expected lines are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/structure.dart';
import 'package:specstone_core/src/rendering/formatter.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';
import '../../helpers/nested_fixture.dart';
import '../../helpers/record_fixture.dart' show recordsRootTemplates;
import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';

const _frKey =
    'docs/prds/features/f01_login/us01_email_login/fr01_validate_credentials.md';
const _frTarget = 'fr:login/email_login/validate_credentials';
const _storyKey = 'docs/prds/features/f01_login/us01_email_login/USER_STORY.md';

String _padded(String start, int length) => start.padRight(length, '.');

final _e09Fr =
    '---\ntraced_from:\n  - S1\n  - S2\n---\n\n'
    '# Validate credentials\n\n## Statement\n'
    '${_padded('The system shall check the email and the password.', 165)}\n\n'
    '## Edge cases\n${_padded('1. E01 — A wrong password → refused', 106)}\n'
    '${_padded('2. E02 — An unknown email → refused', 121)}\n';

final String _leadFr = _e09Fr.replaceFirst(
  '# Validate credentials\n\n',
  '# Validate credentials\n\n${_padded('The lead says what the check covers.', 681)}\n\n',
);

/// The `sections` of the doc [target] names, as `--json` prints them.
List<Map<String, Object?>> _jsonSections(DocIndex index, String target) =>
    ((answerStructure(index, targets: [target]).json['docs']! as List)
                .cast<Map<String, Object?>>()
                .single['sections']!
            as List)
        .cast<Map<String, Object?>>();

void main() {
  late DocIndex index;
  setUpAll(() async => index = await indexWith(loginRecords));
  int tokensOf(String key) => tokenSizeOf(loginProject[key]!);

  test('the whole tree, tops in tree order, children two spaces deeper', () async {
    final lines = answerStructure(index).text.split('\n');
    expect(lines.take(4), [
      'features (features) — Feature index · ${tokensOf('docs/prds/FEATURES.md')} tokens',
      'gnfr (gnfr) — Global non-functional requirements · ${tokensOf('docs/prds/GNFR.md')} tokens',
      'project (project) — Project context · ${tokensOf('docs/prds/PROJECT.md')} tokens',
      'login (feature) — Login · planned · ${tokensOf('docs/prds/features/f01_login/FEATURE.md')} tokens',
    ]);
    expect(
      lines[4],
      '  login/email_login (user_story) — Agent signs in with email · planned · draft · '
      '${tokensOf('docs/prds/features/f01_login/us01_email_login/USER_STORY.md')} tokens',
    );
    expect(lines.sublist(5, 8).map((l) => l.trim().split(' ').first), [
      'login/email_login/validate_credentials',
      'login/email_login/login_latency',
      'login/email_login/lock_after_failures',
    ]);
  });
  test('untyped docs follow under their folder line', () async {
    final text = answerStructure(index).text;
    expect(
      text,
      endsWith(
        './\n  README.md — Readme · ${tokensOf('docs/README.md')} tokens\n'
        'prds/\n  prds/d01_context.md — D-01 — Project context · ${tokensOf('docs/prds/d01_context.md')} tokens\n',
      ),
    );
  });
  test('login prints the feature subtree once, spec docs inside it', () async {
    final lines = answerStructure(
      index,
      targets: ['login'],
    ).text.trim().split('\n');
    expect(lines, hasLength(11));
    expect(lines.first, startsWith('login (feature)'));
  });
  test('a feature line shows the computed status', () async {
    expect(
      answerStructure(index, targets: ['signup']).text,
      startsWith('signup (feature) — Sign up · implemented · '),
    );
  });
  test('a target no doc carries is doc_not_found', () async {
    expect(
      () => answerStructure(index, targets: ['logn']),
      throwsA(isA<IndexFault>()),
    );
  });
  test('an unknown doc type prefix is doc_type_unknown', () async {
    expect(
      () => answerStructure(index, targets: ['featur:login']),
      throwsA(isA<TemplateFault>()),
    );
  });
  test('an untyped DocPath target prints its one line', () async {
    expect(
      answerStructure(index, targets: ['prds/d01_context.md']).text,
      'prds/d01_context.md — D-01 — Project context · ${tokensOf('docs/prds/d01_context.md')} tokens\n',
    );
  });
  test('--json nests children and lists untyped docs by folder', () async {
    final json = answerStructure(index, targets: ['login/email_login']).json;
    final story = (json['docs']! as List).single as Map<String, Object?>;
    expect(story.keys.toList(), [
      'name',
      'docType',
      'path',
      'title',
      'status',
      'draft',
      'tokens',
      'sections',
      'children',
    ]);
    expect(
      ((story['children']! as List).first as Map)['name'],
      'login/email_login/validate_credentials',
    );
    expect(answerStructure(index).json['untyped'], [
      {
        'folder': './',
        'docs': [
          {
            'name': 'README.md',
            'path': 'README.md',
            'title': 'Readme',
            'draft': false,
            'tokens': tokensOf('docs/README.md'),
          },
        ],
      },
      {
        'folder': 'prds/',
        'docs': [
          {
            'name': 'prds/d01_context.md',
            'path': 'prds/d01_context.md',
            'title': 'D-01 — Project context',
            'draft': false,
            'tokens': tokensOf('docs/prds/d01_context.md'),
          },
        ],
      },
    ]);
  });
  test('plan ruling: resolve and childrenOf return lists that cannot be sorted in place', () async {
    final feature = index.resolve('login').first;
    int keep(IndexedDoc a, IndexedDoc b) => 0;
    expect(() => index.resolve('login').sort(keep), throwsUnsupportedError);
    expect(() => index.childrenOf(feature).sort(keep), throwsUnsupportedError);
  });
  test('structure shop prints shop, cart and its two stories, then pay and its two', () async {
    final nested = await nestedIndexWith();
    final lines = answerStructure(nested, targets: ['shop']).text.split('\n');
    expect(
      [
        for (final line in lines)
          if (line.contains('(feature)') || line.contains('(user_story)'))
            line.split(' — ').first,
      ],
      [
        'shop (feature)',
        '  shop/cart (feature)',
        '    shop/cart/add_item (user_story)',
        '    shop/cart/drop_item (user_story)',
        '  shop/pay (feature)',
        '    shop/pay/card (user_story)',
        '    shop/pay/refund (user_story)',
      ],
    );
  });

  group('several targets', () {
    List<String> namesOf(String text) => [
      for (final line in text.trim().split('\n')) line.split(' (').first.trim(),
    ];

    test('two stories of one feature as targets print one tree', () {
      const stories = ['login/reset_password', 'login/email_login'];
      final answer = answerStructure(index, targets: stories);
      final names = namesOf(answer.text);
      final wholeOrder = [
        for (final name in namesOf(answerStructure(index).text))
          if (name.startsWith('login/')) name,
      ];

      expect(names, wholeOrder);
      expect(names.toSet(), hasLength(names.length));
      expect(names.first, 'login/email_login');
      expect(answer.text, isNot(contains(' chars')));
    });

    test('a feature and its story as targets print the feature tree alone', () {
      final answer = answerStructure(
        index,
        targets: ['login', 'login/email_login'],
      );

      expect(answer.text, answerStructure(index, targets: ['login']).text);
      expect(answer.json['docs'], hasLength(1));
    });

    test('an untyped DocPath beside a feature target prints in the folders part', () {
      final text = answerStructure(
        index,
        targets: ['login', 'prds/d01_context.md'],
      ).text;

      expect(
        text,
        '${answerStructure(index, targets: ['login']).text}'
        'prds/\n  prds/d01_context.md — D-01 — Project context · ${tokensOf('docs/prds/d01_context.md')} tokens\n',
      );
    });

    test('--json with two targets matches the whole-tree shape and has no sections key', () {
      final json = answerStructure(
        index,
        targets: ['login/email_login', 'signup'],
      ).json;

      expect(json.keys.toList(), ['docs', 'untyped']);
      expect(
        [for (final doc in json['docs']! as List) (doc as Map)['name']],
        ['login/email_login', 'signup'],
      );
      expect(jsonEncode(json), isNot(contains('"sections"')));
    });
  });

  group('Print the docs tree', () {
    late DocIndex e09;
    setUpAll(
      () async => e09 = await indexWith({...loginRecords, _frKey: _e09Fr}),
    );

    test('a typed doc target prints each section and item with its characters', () async {
      expect(
        answerStructure(e09, targets: [_frTarget]).text,
        'login/email_login/validate_credentials (fr) — Validate credentials · implemented · ${tokenSizeOf(_e09Fr)} tokens\n'
        '  statement · 166 chars\n'
        '    line 11 · 165 chars\n'
        '  edge_cases · 229 chars\n'
        '    E01 · 106 chars\n'
        '    E02 · 121 chars\n',
      );
    });

    test(
      '--json gives the doc object sections with key, chars, and items',
      () async {
        final json = answerStructure(e09, targets: [_frTarget]).json;
        final doc = (json['docs']! as List).single as Map<String, Object?>;

        expect(doc.keys.toList(), [
          'name',
          'docType',
          'path',
          'title',
          'status',
          'draft',
          'tokens',
          'sections',
          'children',
        ]);
        expect(doc['sections'], [
          {
            'key': 'statement',
            'chars': 166,
            'items': [
              {'line': 11, 'chars': 165},
            ],
          },
          {
            'key': 'edge_cases',
            'chars': 229,
            'items': [
              {'id': 'E01', 'line': 15, 'chars': 106},
              {'id': 'E02', 'line': 16, 'chars': 121},
            ],
          },
        ]);
      },
    );

    test(
      'item line prints the visible count and the section line the raw one',
      () async {
        const item = '- See [the rule](a/b.md#rules).';
        final index = await indexWith({
          ...loginRecords,
          _frKey: _e09Fr.replaceFirst(
            RegExp(r'The system shall check[^\n]*\n'),
            '$item\n',
          ),
        });
        final lines = answerStructure(
          index,
          targets: [_frTarget],
        ).text.split('\n');

        expect(lines.skip(1).take(2), [
          '  statement · ${'\n$item'.length} chars',
          '    line 11 · 15 chars',
        ]);
        expect(_jsonSections(index, _frTarget).first, {
          'key': 'statement',
          'chars': '\n$item'.length,
          'items': [
            {'line': 11, 'chars': 15},
          ],
        });
      },
    );

    test('a lead prints first as _lead with its items, as text', () async {
      final index = await indexWith({...loginRecords, _frKey: _leadFr});
      expect(
        answerStructure(index, targets: [_frTarget]).text,
        'login/email_login/validate_credentials (fr) — Validate credentials · implemented · ${tokenSizeOf(_leadFr)} tokens\n'
        '  _lead · 681 chars\n'
        '    line 9 · 681 chars\n'
        '  statement · 166 chars\n'
        '    line 13 · 165 chars\n'
        '  edge_cases · 229 chars\n'
        '    E01 · 106 chars\n'
        '    E02 · 121 chars\n',
      );
    });

    test(
      'a lead gives the first sections entry key _lead under --json',
      () async {
        final index = await indexWith({...loginRecords, _frKey: _leadFr});
        final sections = _jsonSections(index, _frTarget);

        expect(sections.first, {
          'key': '_lead',
          'chars': 681,
          'items': [
            {'line': 9, 'chars': 681},
          ],
        });
        expect(
          [for (final s in sections) s['key']],
          ['_lead', 'statement', 'edge_cases'],
        );
      },
    );

    test(
      'a lead that holds no text prints no _lead line and no _lead entry',
      () async {
        final text = answerStructure(e09, targets: [_frTarget]).text;

        expect(text, isNot(contains('_lead')));
        expect(
          [for (final s in _jsonSections(e09, _frTarget)) s['key']],
          ['statement', 'edge_cases'],
        );
      },
    );

    test('a lead of blank lines only prints no _lead line', () async {
      final blank = _e09Fr.replaceFirst(
        '# Validate credentials\n\n',
        '# Validate credentials\n\n   \n\n',
      );
      final index = await indexWith({...loginRecords, _frKey: blank});

      expect(
        answerStructure(index, targets: [_frTarget]).text,
        isNot(contains('_lead')),
      );
    });

    test('a doc with no title line takes its whole head as the lead', () async {
      final untitled = _leadFr.replaceFirst('# Validate credentials\n\n', '');
      final index = await indexWith({...loginRecords, _frKey: untitled});

      expect(_jsonSections(index, _frTarget), [
        {
          'key': '_lead',
          'chars': 681,
          'items': [
            {'line': 7, 'chars': 681},
          ],
        },
        {
          'key': 'statement',
          'chars': 166,
          'items': [
            {'line': 11, 'chars': 165},
          ],
        },
        {
          'key': 'edge_cases',
          'chars': 229,
          'items': [
            {'id': 'E01', 'line': 15, 'chars': 106},
            {'id': 'E02', 'line': 16, 'chars': 121},
          ],
        },
      ]);
    });

    test('sections out of template order print in file order with the laid-out item lines', () async {
      final shuffled = _e09Fr.replaceFirst(
        RegExp(r'## Statement\n.*\n\n## Edge cases\n.*\n.*\n', dotAll: true),
        '## Edge cases\n${_padded('1. E01 — A wrong password → refused', 106)}\n'
        '${_padded('2. E02 — An unknown email → refused', 121)}\n\n'
        '## Statement\n${_padded('The system shall check the email and the password.', 165)}\n',
      );
      final index = await indexWith({...loginRecords, _frKey: shuffled});

      expect(_jsonSections(index, _frTarget), [
        {
          'key': 'edge_cases',
          'chars': 229,
          'items': [
            {'id': 'E01', 'line': 15, 'chars': 106},
            {'id': 'E02', 'line': 16, 'chars': 121},
          ],
        },
        {
          'key': 'statement',
          'chars': 166,
          'items': [
            {'line': 11, 'chars': 165},
          ],
        },
      ]);
    });

    test('a doc with a repeated header keeps each section its own items, counted on disk', () async {
      final repeated = _e09Fr.replaceFirst(
        '## Edge cases',
        '## Statement\nsecond\n\n## Edge cases',
      );
      final index = await indexWith({...loginRecords, _frKey: repeated});

      expect(_jsonSections(index, _frTarget), [
        {
          'key': 'statement',
          'chars': 165,
          'items': [
            {'line': 10, 'chars': 165},
          ],
        },
        {
          'key': 'statement',
          'chars': 6,
          'items': [
            {'line': 13, 'chars': 6},
          ],
        },
        {
          'key': 'edge_cases',
          'chars': 228,
          'items': [
            {'id': 'E01', 'line': 16, 'chars': 106},
            {'id': 'E02', 'line': 17, 'chars': 121},
          ],
        },
      ]);
    });

    test('a lettered item ID prints as a line, never as an ID', () async {
      final lettered = _e09Fr.replaceFirst('2. E02 —', '2. E02a —');
      final index = await indexWith({...loginRecords, _frKey: lettered});
      final lines = answerStructure(
        index,
        targets: [_frTarget],
      ).text.split('\n');

      expect(lines, contains('    E01 · 106 chars'));
      expect(lines, contains(matches(RegExp(r'^    line 16 · \d+ chars$'))));
      expect(lines.where((l) => l.contains('E02a')), isEmpty);
    });

    test(
      'a name that several docs carry prints the tree with no section line',
      () async {
        final text = answerStructure(e09, targets: ['login']).text;

        expect(text, isNot(contains(' chars')));
        expect(answerStructure(e09).text, isNot(contains(' chars')));
        expect(
          answerStructure(e09, targets: ['login']).json.toString(),
          isNot(contains('sections')),
        );
      },
    );

    test(
      'feature:login prints the feature sections and items, then its subtree',
      () async {
        final lines = answerStructure(
          e09,
          targets: ['feature:login'],
        ).text.trim().split('\n');

        expect(lines.first, startsWith('login (feature)'));
        expect(lines[1], matches(RegExp(r'^  problem · \d+ chars$')));
        expect(lines[2], matches(RegExp(r'^    line \d+ · \d+ chars$')));
        expect(lines.where((l) => l.contains('(user_story)')), hasLength(2));
        expect(
          lines.where((l) => l.contains(' (') && l.contains(' tokens')),
          hasLength(11),
        );
      },
    );

    test('Review Focus: each printed section count is the SectionCounts.chars check compares', () async {
      final doc = e09.resolve(_frTarget).single;
      final content = e09.contentOf(doc);
      final stored = {
        for (final (i, section) in content.sections.indexed)
          section.key: content.lineFacts.sectionCounts[i].chars,
      };
      final sections =
          (answerStructure(e09, targets: [_frTarget]).json['docs']! as List)
                  .cast<Map<String, Object?>>()
                  .single['sections']!
              as List;

      expect({
        for (final s in sections.cast<Map<String, Object?>>())
          s['key']: s['chars'],
      }, stored);
    });

    test(
      'a scenario heading prints as Scenario <n> by its number value',
      () async {
        final index = await indexWith({
          _storyKey:
              '---\nstatus: planned\n---\n\n# Agent signs in with email\n\n## Acceptance Criteria\n'
              '### Scenario 01 — [happy] Sign in\n- **Given** a user\n- **When** it signs in\n',
        });
        final lines = answerStructure(
          index,
          targets: ['user_story:login/email_login'],
        ).text.split('\n');

        expect(lines[1], startsWith('  acceptance_criteria · '));
        expect(lines[2], matches(RegExp(r'^    Scenario 1 · \d+ chars$')));
        expect(lines[3], matches(RegExp(r'^    line \d+ · \d+ chars$')));
      },
    );

    test('counts and lines are those of the laid-out text', () async {
      final drifted = _e09Fr.replaceFirst(
        '## Statement\n',
        '## Statement\n\n\n',
      );
      final index = await indexWith({_frKey: drifted});
      final doc = index.resolve(_frTarget).single;
      final laid = layOutDoc(
        toLf(index.contentOf(doc).text),
        index.typeOf(doc),
      ).split('\n');
      final json =
          (answerStructure(index, targets: [_frTarget]).json['docs']! as List)
                  .cast<Map<String, Object?>>()
                  .single['sections']!
              as List;
      final statement = (json.first as Map<String, Object?>)['items']! as List;

      expect(laid, isNot(drifted.split('\n')));
      expect(
        laid[((statement.single as Map)['line']! as int) - 1],
        startsWith('The system shall'),
      );
      expect((statement.single as Map)['chars'], 165);
    });

    test('a doc the formatter refuses counts its text as on disk', () async {
      final refused = _e09Fr.replaceFirst(
        '## Edge cases',
        '## Mystery\nx\n\n## Edge cases',
      );
      final index = await indexWith({_frKey: refused});
      final doc = index.resolve(_frTarget).single;
      final disk = refused.split('\n');
      final content = index.contentOf(doc);
      final sections =
          (answerStructure(index, targets: [_frTarget]).json['docs']! as List)
                  .cast<Map<String, Object?>>()
                  .single['sections']!
              as List;

      expect(layOutDoc(refused, index.typeOf(doc)), refused);
      expect(
        [for (final s in sections) (s as Map)['key']],
        ['statement', 'mystery', 'edge_cases'],
      );
      expect(
        [for (final s in sections) (s as Map)['chars']],
        [for (final c in content.lineFacts.sectionCounts) c.chars],
      );
      final first = ((sections.last as Map)['items']! as List).first as Map;
      expect(disk[(first['line']! as int) - 1], startsWith('1. E01'));
    });

    test('a doc whose bytes are not UTF-8 counts its text as decoded, as check stores', () async {
      const before =
          '# Validate credentials\n\n## Statement\nThe system shall check ';
      const after =
          ' the email.\n\n## Edge cases\n1. E01 — A wrong password → refused\n';
      final project = await writeLoginProject();
      File(
        '${project.path}/$_frKey',
      ).writeAsBytesSync([...utf8.encode(before), 0xFF, ...utf8.encode(after)]);
      final session = openSession(project);
      addTearDown(session.close);
      final index = session.index;
      final doc = index.resolve(_frTarget).single;
      final stored = index.contentOf(doc).lineFacts.sectionCounts;
      final sections =
          (answerStructure(index, targets: [_frTarget]).json['docs']! as List)
                  .cast<Map<String, Object?>>()
                  .single['sections']!
              as List;
      final statement = (sections.first as Map)['items']! as List;
      final disk = index.contentOf(doc).text.split('\n');

      expect(doc.formatted, isNull);
      expect(
        [for (final s in sections) (s as Map)['chars']],
        [for (final c in stored) c.chars],
      );
      expect(
        disk[((statement.single as Map)['line']! as int) - 1],
        startsWith('The system shall'),
      );
      expect((statement.single as Map)['line'], 4);
    });

    test('an item with an emoji counts one character per code point', () async {
      const item = '2. E02 — 😀 a wrong email → refused';
      final index = await indexWith({
        _frKey: _e09Fr.replaceFirst(RegExp(r'2\. E02.*\n'), '$item\n'),
      });
      final sections =
          (answerStructure(index, targets: [_frTarget]).json['docs']! as List)
                  .cast<Map<String, Object?>>()
                  .single['sections']!
              as List;
      final items = (sections.last as Map)['items']! as List;

      expect((items.last as Map)['chars'], item.runes.length);
      expect(item.runes.length, lessThan(item.length));
    });

    test('a scenario heading check does not read prints as a line', () async {
      final index = await indexWith({
        _storyKey:
            '---\nstatus: planned\n---\n\n# Agent signs in with email\n\n## Acceptance Criteria\n'
            '### **Scenario 1** — [happy] Sign in\n- **Given** a user\n',
      });
      final lines = answerStructure(
        index,
        targets: ['user_story:login/email_login'],
      ).text.split('\n');

      expect(lines[2], matches(RegExp(r'^    line \d+ · \d+ chars$')));
    });
  });

  group('status per code target', () {
    const featureText =
        '---\nstatus: implemented\n---\n\n# Toast\n\n## Problem\nBurnt '
        'toast.\n';
    const showText =
        '---\nstatus: implemented\n---\n\n# Agent sees a toast\n\n## Use '
        'Case\nUse it.\n';
    const swipeText =
        '---\nstatus: implemented\n---\n\n# Agent swipes a toast away\n\n'
        '## Use Case\nUse it.\n';
    const archText = '# Toast architecture\n';

    String record(String lines) => lines.isEmpty
        ? '# Record\n'
        : '---\nstatuses:\n$lines---\n\n# Record\n';

    /// Returns the index of the two-target fixture: `feedback/toast`, its two
    /// stories, its architecture doc in both targets, and each target's record.
    Future<DocIndex> toastIndex({
      String flutterStatuses = '',
      String jasprStatuses = '',
      Map<String, String> extra = const {},
    }) async {
      final session = openSession(
        await writeTree({
          ...extra,
          '.specstone/templates/architecture.yaml':
              'id: architecture\nper_target: true\n',
          '.specstone/templates/implementation.yaml':
              'id: implementation\n'
              'description: One feature record per target.\n'
              'path: .specstone/records/f{nn}_{slug}/IMPLEMENTATION.md\n'
              'parent: feature\n'
              'per_target: true\n'
              'fields:\n'
              '  - id: statuses\n'
              '    type: record_status\n'
              '    list: true\n',
          '.specstone/config.yaml':
              '${shippedPinsConfig()}targets:\n'
              '  flutter:\n    code_root: flutter_lib\n'
              '  jaspr:\n    code_root: jaspr_lib\n',
          'flutter_lib/.keep': '',
          'jaspr_lib/.keep': '',
          'docs/prds/features/f02_feedback/FEATURE.md': featureText,
          'docs/prds/features/f02_feedback/f03_toast/FEATURE.md': featureText,
          'docs/prds/features/f02_feedback/f03_toast/us01_show/USER_STORY.md':
              showText,
          'docs/prds/features/f02_feedback/f03_toast/us02_swipe/USER_STORY.md':
              swipeText,
          'docs/specs/flutter/f02_feedback/f03_toast/ARCHITECTURE.md': archText,
          'docs/specs/jaspr/f02_feedback/f03_toast/ARCHITECTURE.md': archText,
          '.specstone/records/flutter/f02_feedback/f03_toast/IMPLEMENTATION.md':
              record(flutterStatuses),
          '.specstone/records/jaspr/f02_feedback/f03_toast/IMPLEMENTATION.md':
              record(jasprStatuses),
        }),
      );
      addTearDown(session.close);
      return session.index;
    }

    test('each line holds each target status in targets order, a skipped story skipped', () async {
      const flutter = '  - show:implemented\n  - swipe:implemented\n';
      const jaspr = '  - show:planned\n  - swipe:skipped:no jaspr\n';
      final index = await toastIndex(
        flutterStatuses: flutter,
        jasprStatuses: jaspr,
      );

      expect(
        answerStructure(index, targets: ['feedback/toast']).text,
        'feedback/toast (feature) — Toast · flutter: implemented, jaspr: '
        'planned · ${tokenSizeOf(featureText)} tokens\n'
        '  feedback/toast/show (user_story) — Agent sees a toast · flutter: '
        'implemented, jaspr: planned · ${tokenSizeOf(showText)} tokens\n'
        '  feedback/toast/swipe (user_story) — Agent swipes a toast away · '
        'flutter: implemented, jaspr: skipped · '
        '${tokenSizeOf(swipeText)} tokens\n'
        '  feedback/toast (architecture) — Toast architecture · '
        '${tokenSizeOf(archText)} tokens\n'
        '  feedback/toast (architecture) — Toast architecture · '
        '${tokenSizeOf(archText)} tokens\n',
      );
    });

    test('an fr line holds each target status in targets order', () async {
      const frText =
          '---\nstatus: implemented\n---\n\n# Render it\n\n## Statement\n'
          'Shall.\n';
      final index = await toastIndex(
        flutterStatuses: '  - show:implemented\n  - show/render:implemented\n',
        jasprStatuses: '  - show:planned\n  - show/render:skipped:no jaspr\n',
        extra: {
          'docs/prds/features/f02_feedback/f03_toast/us01_show/fr01_render.md':
              frText,
        },
      );

      expect(
        answerStructure(index, targets: ['feedback/toast']).text.split('\n'),
        contains(
          '    feedback/toast/show/render (fr) — Render it · flutter: '
          'implemented, jaspr: skipped · ${tokenSizeOf(frText)} tokens',
        ),
      );
    });

    test(
      '--json holds statuses, target name to status, in targets order',
      () async {
        final index = await toastIndex(
          flutterStatuses: '  - show:implemented\n  - swipe:implemented\n',
          jasprStatuses: '  - show:planned\n  - swipe:skipped:no jaspr\n',
        );

        final doc =
            (answerStructure(index, targets: ['feedback/toast']).json['docs']!
                    as List)
                .cast<Map<String, Object?>>()
                .single;
        expect(doc.keys.toList(), [
          'name',
          'docType',
          'path',
          'title',
          'statuses',
          'draft',
          'tokens',
          'children',
        ]);
        expect(doc['statuses'], {'flutter': 'implemented', 'jaspr': 'planned'});
        final swipe = (doc['children']! as List)
            .cast<Map<String, Object?>>()
            .singleWhere((c) => c['name'] == 'feedback/toast/swipe');
        expect(swipe['statuses'], {
          'flutter': 'implemented',
          'jaspr': 'skipped',
        });
      },
    );

    test(
      '--target jaspr prints jaspr statuses alone and no flutter spec doc',
      () async {
        final index = await toastIndex(
          flutterStatuses: '  - show:implemented\n  - swipe:implemented\n',
          jasprStatuses: '  - show:planned\n  - swipe:skipped:no jaspr\n',
        );

        final lines = answerStructure(
          index,
          targets: ['feedback/toast'],
          codeTarget: 'jaspr',
        ).text.split('\n');
        expect(
          lines.where((l) => l.contains('flutter')),
          isEmpty,
          reason: 'no flutter status and no flutter spec doc',
        );
        expect(lines.first, contains(' · planned · '));
        expect(
          lines.where((l) => l.contains('(user_story)')).last,
          contains(' · skipped · '),
        );
      },
    );

    test(
      'one target, named or not, shows its one status with no name',
      () async {
        final single = await toastIndex(
          flutterStatuses: '  - show:implemented\n  - swipe:implemented\n',
        );
        final plain = await indexWith();

        expect(
          answerStructure(
            single,
            targets: ['feedback/toast'],
            codeTarget: 'flutter',
          ).text.split('\n').first,
          startsWith('feedback/toast (feature) — Toast · implemented · '),
        );
        expect(
          answerStructure(plain, targets: ['login']).text.split('\n').first,
          startsWith('login (feature) — Login · planned · '),
        );
      },
    );

    test('a project that names one target reads its records with no flag, '
        'one status with no name', () async {
      final session = openSession(
        await writeTree({
          '.specstone/templates/implementation.yaml':
              'id: implementation\n'
              'description: One feature record per target.\n'
              'path: .specstone/records/f{nn}_{slug}/IMPLEMENTATION.md\n'
              'parent: feature\n'
              'per_target: true\n'
              'fields:\n'
              '  - id: statuses\n'
              '    type: record_status\n'
              '    list: true\n',
          '.specstone/config.yaml':
              '${shippedPinsConfig()}targets:\n'
              '  flutter:\n    code_root: flutter_lib\n',
          'flutter_lib/.keep': '',
          'docs/prds/features/f02_feedback/FEATURE.md': featureText,
          'docs/prds/features/f02_feedback/f03_toast/FEATURE.md': featureText,
          'docs/prds/features/f02_feedback/f03_toast/us01_show/USER_STORY.md':
              showText,
          '.specstone/records/f02_feedback/f03_toast/IMPLEMENTATION.md': record(
            '  - show:implemented\n',
          ),
        }),
      );
      addTearDown(session.close);
      final index = session.index;
      expect(index.targetNames, ['flutter']);

      final featureLine =
          'feedback/toast (feature) — Toast · implemented · '
          '${tokenSizeOf(featureText)} tokens';
      final storyLine =
          '  feedback/toast/show (user_story) — Agent sees a toast · '
          'implemented · ${tokenSizeOf(showText)} tokens';
      expect(
        answerStructure(index, targets: ['feature:feedback/toast']).text,
        '$featureLine\n'
        '  problem · 13 chars\n'
        '    line 9 · 12 chars\n'
        '$storyLine\n',
      );
    });

    test('an unknown code target is argument_invalid with '
        'no positional target too', () async {
      final index = await toastIndex();
      expect(
        () => answerStructure(index, codeTarget: 'web'),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
              .having(
                (f) => f.message,
                'message',
                '--target web: the code targets are flutter, jaspr',
              ),
        ),
      );
    });

    test('a parentless doc of another target is left out with '
        '--target', () async {
      final session = openSession(
        await writeTree({
          '.specstone/templates/architecture.yaml':
              'id: architecture\nper_target: true\n',
          '.specstone/templates/implementation.yaml':
              'id: implementation\n'
              'description: One feature record per target.\n'
              'path: .specstone/records/f{nn}_{slug}/IMPLEMENTATION.md\n'
              'parent: feature\n'
              'per_target: true\n'
              'fields:\n'
              '  - id: statuses\n'
              '    type: record_status\n'
              '    list: true\n',
          '.specstone/config.yaml':
              '${shippedPinsConfig()}targets:\n'
              '  flutter:\n    code_root: flutter_lib\n'
              '  jaspr:\n    code_root: jaspr_lib\n',
          'flutter_lib/.keep': '',
          'jaspr_lib/.keep': '',
          'docs/prds/features/f02_feedback/FEATURE.md': featureText,
          'docs/specs/flutter/f99_gone/ARCHITECTURE.md':
              '# Feedback architecture\n',
        }),
      );
      addTearDown(session.close);

      expect(
        answerStructure(session.index, codeTarget: 'jaspr').text,
        'feedback (feature) — Toast · planned · '
        '${tokenSizeOf(featureText)} tokens\n',
      );
    });
  });

  group('records under the records root', () {
    const recordsRoot = '.specstone/records';
    late DocIndex underRoot;
    setUpAll(() async {
      underRoot = await indexWith({
        ...recordsRootTemplates,
        '$recordsRoot/f01_login/IMPLEMENTATION.md':
            loginRecords['.specstone/records/f01_login/IMPLEMENTATION.md']!,
        '$recordsRoot/f02_signup/IMPLEMENTATION.md':
            loginRecords['.specstone/records/f02_signup/IMPLEMENTATION.md']!,
      });
    });

    List<String> withoutRecordLines(String text) => [
      for (final line in text.split('\n'))
        if (!line.contains(' (implementation) ')) line,
    ];

    test('the whole tree prints no record line and the statuses it printed with the records beside the feature', () {
      final text = answerStructure(underRoot).text;

      expect(text, isNot(contains('(implementation)')));
      expect(text.split('\n'), withoutRecordLines(answerStructure(index).text));
      expect(text, contains('login (feature) — Login · planned · '));
      expect(text, contains('signup (feature) — Sign up · implemented · '));
    });

    test(
      'a feature prints its subtree with no record line and the same statuses',
      () {
        final text = answerStructure(underRoot, targets: ['login']).text;

        expect(text, isNot(contains('(implementation)')));
        expect(
          text.split('\n'),
          withoutRecordLines(answerStructure(index, targets: ['login']).text),
        );
      },
    );

    test('--json on the whole tree holds no record doc', () {
      final docs = answerStructure(underRoot).json['docs']! as List;

      expect(jsonEncode(docs), isNot(contains('"docType":"implementation"')));
      expect(jsonEncode(docs), isNot(contains(recordsRoot)));
    });

    test('a record and a feature as two targets print no record line', () {
      final text = answerStructure(
        underRoot,
        targets: ['implementation:login', 'signup'],
      ).text;

      expect(text, isNot(contains('(implementation)')));
      expect(text, startsWith('signup (feature) — Sign up'));
    });

    test('the record target prints the record lines', () {
      final answer = answerStructure(
        underRoot,
        targets: ['implementation:login'],
      );

      expect(
        answer.text.split('\n').first,
        startsWith('login (implementation) — Login implementation · '),
      );
      expect(answer.json['docs'], hasLength(1));
    });
  });
}
