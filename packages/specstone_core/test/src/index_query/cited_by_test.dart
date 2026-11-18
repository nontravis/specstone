// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_render.dart';
import 'package:specstone_core/src/index_query/bundle_trim.dart';
import 'package:specstone_core/src/index_query/cited_by.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/models/bundle_entry.dart';
import 'package:specstone_core/src/index_query/models/cited_by.dart';
import 'package:specstone_core/src/index_query/models/cited_item.dart';
import 'package:specstone_core/src/index_query/models/cited_place.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';

const _fr =
    'docs/prds/features/f01_login/us01_email_login/fr01_validate_credentials.md';
const _specs = '../../../../specs';
const _domain = 'specs/f02_signup/DOMAIN.md';
const _frName = 'login/email_login/validate_credentials';

const _inv13 = '[INV-13]($_specs/f02_signup/DOMAIN.md#invariants)';
const _inv14 = '[INV-14]($_specs/f02_signup/DOMAIN.md#invariants)';

/// A domain doc with three invariants, one of which links to a sibling.
const _docs = <String, String>{
  'docs/specs/f02_signup/DOMAIN.md':
      '# Sign-up domain\n\n## Entities\n- Account\n\n## Invariants\n'
      '- **INV-13** An account has one email.\n'
      '- **INV-14** An account locks after five failures.\n'
      '- **INV-15** A locked account mails its owner, as [INV-13](DOMAIN.md#invariants) says.\n',
  'docs/specs/topics/ranges.md':
      '# Ranges\n\n## Rules\n- **RULE-1** One.\n- **RULE-2** Two.\n'
      '- **RULE-3** Three.\n- **RULE-4** Four.\n- **RULE-5** Five.\n',
};

String _frWith(String statement, [String edge = '']) =>
    '---\nverify_method: test\n---\n\n# Validate credentials\n\n'
    '## Statement\n$statement\n\n## Edge cases\n<!-- fill in later -->\n$edge\n';

Future<DocIndex> _index(
  String statement, {
  String edge = '1. E01 — A wrong password → refused.',
  Map<String, String> extra = const {},
}) => indexWith({..._docs, _fr: _frWith(statement, edge), ...extra});

CitedByIndex _citedBy(DocIndex index) => citedByIndex(index);

List<CitedBy> _of(CitedByIndex cited, String docPath, String itemId) =>
    cited[CitedPlace(docPath: docPath, kind: CitedKind.item, key: itemId)] ??
    const [];

List<CitedBy> _ofSection(CitedByIndex cited, String docPath, String key) =>
    cited[CitedPlace(docPath: docPath, kind: CitedKind.section, key: key)] ??
    const [];

List<CitedBy> _ofDoc(CitedByIndex cited, String docPath) =>
    cited[CitedPlace(docPath: docPath, kind: CitedKind.doc, key: null)] ??
    const [];

void main() {
  test(
    'an item link from an item of another doc gives its line, doc, and item',
    () async {
      const line = '1. E01 — A wrong password → refused, by $_inv14.';
      final cited = _citedBy(await _index('Check it.', edge: line));
      expect(_of(cited, _domain, 'INV-14'), [
        const CitedBy(name: _frName, docType: 'fr', byItem: 'E01', line: line),
      ]);
    },
  );

  test('a link on a line that belongs to no item reads no item', () async {
    const line = 'The system shall lock, by $_inv13.';
    final cited = _citedBy(await _index(line));
    expect(_of(cited, _domain, 'INV-13'), [
      const CitedBy(name: _frName, docType: 'fr', byItem: null, line: line),
    ]);
  });

  test('a range gives one line under each item it spans', () async {
    const line = 'See [RULE-2](ranges.md#rules) to [RULE-4](ranges.md#rules).';
    final index = await _index(
      'Check it.',
      extra: {'docs/specs/topics/guide.md': '# Guide\n\n## Purpose\n$line\n'},
    );
    final cited = _citedBy(index);
    final guide = index.at('specs/topics/guide.md')!;
    for (final id in ['RULE-2', 'RULE-3', 'RULE-4']) {
      expect(_of(cited, 'specs/topics/ranges.md', id), [
        CitedBy(name: guide.name, docType: 'topic', byItem: null, line: line),
      ], reason: id);
    }
    expect(_of(cited, 'specs/topics/ranges.md', 'RULE-1'), isEmpty);
    expect(_of(cited, 'specs/topics/ranges.md', 'RULE-5'), isEmpty);
  });

  test('an item of a doc whose type lists bundle: gets no line, read by the key', () async {
    final cited = _citedBy(
      await _index(
        'Cites [PV-01](../../../PROJECT.md#project-vision) and [NFR-Sec01](../../../GNFR.md#security), also $_inv14.',
        extra: {
          'docs/prds/PROJECT.md': '---\nowner: Owner\n---\n\n# Project context\n\n## Project vision\n### PV-01 — One system\nText.\n',
          'docs/prds/GNFR.md': '# Global non-functional requirements\n\n## Security\n### NFR-Sec01 — No plain passwords\nText.\n',
        },
      ),
    );
    expect(_of(cited, 'prds/PROJECT.md', 'PV-01'), isEmpty);
    expect(_of(cited, 'prds/GNFR.md', 'NFR-Sec01'), isEmpty);
    expect(_of(cited, _domain, 'INV-14'), hasLength(1));
  });

  group('a glossary doc another doc cites', () {
    const glossary = 'prds/GLOSSARY.md';
    const glossaryFile = {
      'docs/$glossary': '# Domain glossary\n\n## Terms\n\n- **Doc** — one markdown file under the docs root.\n',
    };
    const statement =
        'Cites [the terms](../../../GLOSSARY.md#terms) and [the glossary](../../../GLOSSARY.md), also $_inv14.';

    test('a section or whole-doc link gets no line, read by the key', () async {
      final cited = _citedBy(await _index(statement, extra: glossaryFile));

      expect(_ofSection(cited, glossary, 'terms'), isEmpty);
      expect(_ofDoc(cited, glossary), isEmpty);
      expect(cited.keys.where((k) => k.docPath == glossary), isEmpty);
      expect(_of(cited, _domain, 'INV-14'), hasLength(1));
    });
    test(
      'the same links give a line once its doc type lists no bundle',
      () async {
        final cited = _citedBy(
          await _index(
            statement,
            extra: {
              ...glossaryFile,
              '.specstone/templates/glossary.yaml':
                  'bundle: {remove: [query, implement, design]}\n',
            },
          ),
        );

        expect(_ofSection(cited, glossary, 'terms'), hasLength(1));
        expect(_ofDoc(cited, glossary), hasLength(1));
      },
    );
    test('a design bundle prints no cited-by line after it', () async {
      final i = await _index(statement, extra: glossaryFile);
      final a = answerContext(
        i,
        pickBundle(i, _frName, BundleMode.design, noProject: false),
        label: _frName,
        byCode: false,
      );

      const head = '==> glossary (glossary) · prds/GLOSSARY.md <==\n';
      final afterHead = a.text.split(head).last;
      expect(a.text, contains(head));
      expect(
        afterHead.substring(0, afterHead.indexOf('==> ')),
        isNot(contains('cited by')),
      );
      expect(a.text, contains('  · cited by $_frName (fr) —: $statement'));
    });
  });

  test(
    'a link from the item own doc, or from an untyped doc, gives no line',
    () async {
      final index = await _index(
        'Check it.',
        extra: {
          'docs/README.md': '# Readme\n\nSee [INV-14](specs/f02_signup/DOMAIN.md#invariants).\n',
        },
      );
      expect(index.at('README.md')!.isTyped, isFalse);
      final cited = _citedBy(index);
      expect(_of(cited, _domain, 'INV-13'), isEmpty);
      expect(_of(cited, _domain, 'INV-14'), isEmpty);
    },
  );

  test('an item many docs cite gets one line per link, none dropped', () async {
    final index = await _index(
      'Check it, by $_inv14.',
      edge: '1. E01 — Refused, by $_inv14.',
      extra: {
        'docs/specs/topics/guide.md': '# Guide\n\n## Purpose\nFirst [INV-14](../f02_signup/DOMAIN.md#invariants).\n\nSecond [INV-14](../f02_signup/DOMAIN.md#invariants).\n',
      },
    );
    final cited = _of(_citedBy(index), _domain, 'INV-14');
    expect(cited.map((c) => (c.name, c.byItem)), [
      (_frName, null),
      (_frName, 'E01'),
      ('guide', null),
      ('guide', null),
    ]);
  });

  test(
    'two links to one item on one line give one line each, none dropped',
    () async {
      const line = 'Both $_inv14 and $_inv14.';
      final cited = _of(_citedBy(await _index(line)), _domain, 'INV-14');
      expect(cited.map((c) => c.line), [line, line]);
    },
  );

  test('items a range chain spans each get one line from it', () async {
    const line =
        'See [RULE-1](ranges.md#rules) to [RULE-3](ranges.md#rules) to [RULE-5](ranges.md#rules).';
    final index = await _index(
      'Check it.',
      extra: {'docs/specs/topics/guide.md': '# Guide\n\n## Purpose\n$line\n'},
    );
    final cited = _citedBy(index);
    for (final id in ['RULE-1', 'RULE-2', 'RULE-3', 'RULE-4', 'RULE-5']) {
      expect(
        _of(cited, 'specs/topics/ranges.md', id),
        hasLength(1),
        reason: id,
      );
    }
  });

  test('two separate ranges on one line count apart', () async {
    const line =
        'See [RULE-2](ranges.md#rules) to [RULE-3](ranges.md#rules) and [RULE-2](ranges.md#rules) to [RULE-4](ranges.md#rules).';
    final index = await _index(
      'Check it.',
      extra: {'docs/specs/topics/guide.md': '# Guide\n\n## Purpose\n$line\n'},
    );
    final cited = _citedBy(index);
    const counts = {'RULE-2': 2, 'RULE-3': 2, 'RULE-4': 1};
    for (final MapEntry(key: id, value: count) in counts.entries) {
      expect(
        _of(cited, 'specs/topics/ranges.md', id),
        hasLength(count),
        reason: id,
      );
    }
  });

  test('nested items that end on one line keep every line, inner first', () {
    const outer = CitedItem(
      kind: CitedKind.item,
      item: 'INV-14',
      sectionKey: 'invariants',
      after: 7,
      by: [CitedBy(name: 'a', docType: 'fr', byItem: null, line: 'outer')],
    );
    const inner = CitedItem(
      kind: CitedKind.item,
      item: 'INV-15',
      sectionKey: 'invariants',
      after: 7,
      by: [CitedBy(name: 'b', docType: 'fr', byItem: 'E01', line: 'inner')],
    );
    expect(citedLinesAfter(null, [inner, outer]), {
      7: ['  · cited by b (fr) E01: inner', '  · cited by a (fr) —: outer'],
    });
  });

  test('a doc link or a section link names no item', () async {
    final cited = _citedBy(
      await _index(
        'See [the domain]($_specs/f02_signup/DOMAIN.md) and [invariants]($_specs/f02_signup/DOMAIN.md#invariants).',
      ),
    );
    expect(cited.keys.where((k) => k.kind == CitedKind.item), isEmpty);
    expect(_ofDoc(cited, _domain), hasLength(1));
    expect(_ofSection(cited, _domain, 'invariants'), hasLength(1));
  });

  test(
    'the lines come from the stored index; the call reads no file',
    () async {
      final project = await writeLoginProject(
        extra: {..._docs, _fr: _frWith('Lock, by $_inv14.')},
      );
      final session = openSession(project);
      addTearDown(session.close);
      File('${project.path}/docs/specs/f02_signup/DOMAIN.md').deleteSync();
      File('${project.path}/$_fr').deleteSync();
      final cited = _of(citedByIndex(session.index), _domain, 'INV-14');
      expect(cited.single.line, 'Lock, by $_inv14.');
    },
  );

  group('section, block, and whole-doc links', () {
    const toDomain = '$_specs/f02_signup/DOMAIN.md';
    const toFr =
        '../../prds/features/f01_login/us01_email_login/fr01_validate_credentials.md';

    ContextAnswer design(DocIndex index) => answerContext(
      index,
      pickBundle(index, _frName, BundleMode.design, noProject: false),
      label: _frName,
      byCode: false,
    );

    List<Map<String, Object?>> docsOf(ContextAnswer answer) =>
        (answer.json['docs']! as List).cast<Map<String, Object?>>();

    test(
      'a section link prints one line right after the section header',
      () async {
        const line = 'Lock, as [the invariants]($toDomain#invariants) say.';
        final text = design(await _index(line)).text;

        expect(
          text,
          contains(
            '## Invariants\n  · cited by $_frName (fr) —: $line\n- **INV-13**',
          ),
        );
        expect('cited by $_frName'.allMatches(text), hasLength(1));
      },
    );

    test('a section link to a picked doc prints right after its header, none under its items', () async {
      const line = 'See [the edge cases]($toFr#edge-cases).';
      final text = design(
        await _index(
          'Check it.',
          extra: {
            'docs/specs/topics/guide.md': '# Guide\n\n## Purpose\n$line\n',
          },
        ),
      ).text;

      expect(
        text,
        contains('## Edge cases\n  · cited by guide (topic) —: $line\n'),
      );
      expect('cited by guide'.allMatches(text), hasLength(1));
    });

    test(
      'a whole-doc link prints one line right after the naming line',
      () async {
        const line = 'Lock, see [the domain]($toDomain).';
        final text = design(await _index(line)).text;

        expect(
          text,
          contains(
            '==> signup (domain) · specs/f02_signup/DOMAIN.md · summary · cited <==\n'
            '  · cited by $_frName (fr) —: $line\n'
            '# Sign-up domain',
          ),
        );
        expect('cited by $_frName'.allMatches(text), hasLength(1));
      },
    );

    test('a whole-doc link to a picked doc prints right after its naming line', () async {
      const line = 'See [the rule]($toFr).';
      final text = design(
        await _index(
          'Check it.',
          extra: {
            'docs/specs/topics/guide.md': '# Guide\n\n## Purpose\n$line\n',
          },
        ),
      ).text;

      expect(
        text,
        contains(
          '==> $_frName (fr) · prds/features/f01_login/us01_email_login/fr01_validate_credentials.md <==\n'
          '  · cited by guide (topic) —: $line\n'
          '---\nverify_method: test',
        ),
      );
    });

    test(
      'a block link prints right after its heading line, kind item',
      () async {
        const line = 'See [a note]($_specs/topics/blocks.md#a-note).';
        final answer = design(
          await _index(
            line,
            extra: {
              'docs/specs/topics/blocks.md':
                  '# Blocks\n\n## Examples\n### A note\nShort.\n',
            },
          ),
        );

        expect(
          answer.text,
          contains('### A note\n  · cited by $_frName (fr) —: $line\nShort.'),
        );
        final part = docsOf(answer)
            .firstWhere((d) => d['path'] == 'specs/topics/blocks.md');
        expect(part['citedBy'], [
          {
            'kind': 'item',
            'item': 'a-note',
            'section': null,
            'name': _frName,
            'docType': 'fr',
            'byItem': null,
            'line': line,
          },
        ]);
      },
    );

    test('an unplaced anchor joins the doc-level entry', () async {
      const line = 'See [the title]($toFr#validate-credentials).';
      final index = await _index(
        'Check it.',
        extra: {'docs/specs/topics/guide.md': '# Guide\n\n## Purpose\n$line\n'},
      );
      final cited = _citedBy(index);
      final fr = index.at(_fr.substring('docs/'.length))!.docPath;

      expect(_ofDoc(cited, fr).map((c) => c.line), [line]);
      expect(_ofSection(cited, fr, 'statement'), isEmpty);
      final picked = docsOf(design(index))
          .firstWhere((d) => d['name'] == _frName);
      expect((picked['citedBy']! as List).single, containsPair('kind', 'doc'));
    });

    test('an anchor matching nothing gets no line', () async {
      final cited = _citedBy(await _index('See [it]($toDomain#nothing-here).'));

      expect(cited.keys.where((k) => k.docPath == _domain), isEmpty);
    });

    test('one line holding an item link and a section link gives two entries, the item one once', () async {
      const line = 'See $_inv14 and [the invariants]($toDomain#invariants).';
      final cited = _citedBy(await _index(line));

      expect(_of(cited, _domain, 'INV-14').map((c) => c.line), [line]);
      expect(_ofSection(cited, _domain, 'invariants').map((c) => c.line), [
        line,
      ]);
    });

    test(
      'a link text with a digit that is no item ID cites its section or doc',
      () async {
        const line = 'See [v2]($toDomain#invariants) and [v3]($toDomain).';
        final cited = _citedBy(await _index(line));

        expect(_ofSection(cited, _domain, 'invariants'), hasLength(1));
        expect(_ofDoc(cited, _domain), hasLength(1));
        expect(cited.keys.where((k) => k.kind == CitedKind.item), isEmpty);
      },
    );

    test('json entries carry kind and section', () {
      const by = <CitedBy>[
        CitedBy(name: 'guide', docType: 'topic', byItem: null, line: 'x'),
      ];
      const own = {
        'name': 'guide',
        'docType': 'topic',
        'byItem': null,
        'line': 'x',
      };

      expect(
        citedByJson([
          const CitedItem(
            kind: CitedKind.section,
            item: null,
            sectionKey: 'invariants',
            after: 5,
            by: by,
          ),
          const CitedItem(
            kind: CitedKind.doc,
            item: null,
            sectionKey: null,
            after: 0,
            by: by,
          ),
          const CitedItem(
            kind: CitedKind.item,
            item: 'INV-14',
            sectionKey: 'invariants',
            after: 7,
            by: by,
          ),
        ]),
        [
          {'kind': 'section', 'item': null, 'section': 'invariants', ...own},
          {'kind': 'doc', 'item': null, 'section': null, ...own},
          {'kind': 'item', 'item': 'INV-14', 'section': null, ...own},
        ],
      );
    });

    test('a bundle: doc, a self link, and an untyped citer get none', () async {
      // A link to the doc itself is a self link, which the index keeps apart from
      // its doc links, so no doc cites itself.
      final index = await _index(
        'Cites [the vision](../../../PROJECT.md#project-vision) and [the project](../../../PROJECT.md).',
        extra: {
          'docs/prds/PROJECT.md': '---\nowner: Owner\n---\n\n# Project context\n\n## Project vision\n### PV-01 — One system\nText.\n',
          'docs/specs/f02_signup/DOMAIN.md': '# Sign-up domain\n\n## Invariants\n- **INV-13** One.\n\nSee [itself](DOMAIN.md#invariants) and [again](DOMAIN.md).\n',
          'docs/README.md': '# Readme\n\nSee [the invariants](specs/f02_signup/DOMAIN.md#invariants) and [the domain](specs/f02_signup/DOMAIN.md).\n',
        },
      );
      expect(index.at('README.md')!.isTyped, isFalse);
      final cited = _citedBy(index);

      expect(
        cited.keys.where(
          (k) => k.docPath == 'prds/PROJECT.md' || k.docPath == _domain,
        ),
        isEmpty,
      );
    });
  });

  group('a split design bundle', () {
    const edge = '1. E01 — A wrong password → refused, by $_inv14.';
    const invHead =
        '==> signup (domain) · specs/f02_signup/DOMAIN.md#invariants · item INV-14';

    Future<ContextAnswer> splitDesign() async {
      final i = await _index('Check it.', edge: edge);
      return answerContext(
        i,
        pickBundle(i, _frName, BundleMode.design, noProject: false),
        label: _frName,
        byCode: false,
        split: true,
      );
    }

    test('prints cited-by lines as refs parts', () async {
      final a = await splitDesign();

      expect(a.text, isNot(contains('cited by')));
      expect(
        a.refs!.text,
        contains(
          '$invHead · cited <==\n'
          '- **INV-14** An account locks after five failures.\n\n'
          '$invHead · cited by <==\n'
          '  · cited by $_frName (fr) E01: $edge\n'
          '==> bundle: ',
        ),
      );
    });
    test('lists each cited-by part after the item it cites', () async {
      final a = await splitDesign();

      expect(
        a.refs!.text,
        contains(
          '- signup (domain) · cited invariants [INV-14]\n'
          '- signup (domain) · cited by [INV-14]\n',
        ),
      );
    });
    test('marks each cited-by part as one in its entry', () async {
      final a = await splitDesign();

      final entry = a.refs!.entries.singleWhere(
        (e) => e.kind == BundleEntryKind.citedBy && e.itemId != null,
      );
      final lines = a.refs!.text.split('\n');
      expect(entry.doc.name, 'signup');
      expect(entry.sectionKey, 'invariants');
      expect(entry.itemId, 'INV-14');
      expect(lines[entry.first - 1], '$invHead · cited by <==');
      expect(entry.last, entry.first + 1);
    });
    test('an item whose lines print inline leaves no part for them', () async {
      final i = await _index('Check it.', edge: edge);
      final a = answerContext(
        i,
        pickBundle(i, _frName, BundleMode.design, noProject: false),
        label: _frName,
        byCode: false,
      );

      expect(a.text, contains('  · cited by $_frName (fr) E01: $edge\n'));
      expect(a.text, isNot(contains('· cited by <==')));
      expect(a.refs, isNull);
    });
  });

  test('an index that prints its lines as parts gives no line to print after an item', () {
    const item = CitedItem(
      kind: CitedKind.item,
      item: 'E01',
      sectionKey: 'edge_cases',
      after: 3,
      by: <CitedBy>[
        CitedBy(name: 'guide', docType: 'topic', byItem: null, line: 'x'),
      ],
    );
    final inline = CitedByIndex(const {}, inline: true);
    final parts = CitedByIndex(const {}, inline: false);

    expect(citedLinesAfter(parts, [item]), isEmpty);
    expect(citedLinesAfter(inline, [item]), {
      3: ['  · cited by guide (topic) —: x'],
    });
  });

  group('printedBodyOf', () {
    test(
      'without lines it equals the comment-free text trimmed at its end',
      () {
        const text = 'a\n<!-- c -->\n- b\n\n<!-- d -->\n';
        expect(printedBodyOf(text), removeHtmlComments(text).trimRight());
      },
    );

    test(
      'places lines right after their file line, past a removed comment',
      () {
        const text = '<!-- one\ntwo -->\n- **E01** x\n- **E02** y\n';
        expect(
          printedBodyOf(
            text,
            firstLine: 10,
            after: {
              12: ['  · a', '  · b'],
              13: ['  · c'],
            },
          ),
          '\n- **E01** x\n  · a\n  · b\n- **E02** y\n  · c',
        );
      },
    );

    test('keeps a line whose file line lies in trailing blanks at the end', () {
      expect(
        printedBodyOf(
          '- x\n\n\n',
          after: {
            1: ['  · a'],
          },
        ),
        '- x\n  · a',
      );
    });
  });
}
