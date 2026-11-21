// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_render.dart';
import 'package:specstone_core/src/index_query/bundle_trim.dart';
import 'package:specstone_core/src/index_query/cited_by.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart' show leadKey;
import 'package:specstone_core/src/index_query/item_links.dart'
    show citedSectionsOf;
import 'package:specstone_core/src/index_query/models/bundle_entry.dart';
import 'package:specstone_core/src/index_query/models/cited_by.dart';
import 'package:specstone_core/src/index_query/models/cited_item.dart';
import 'package:specstone_core/src/index_query/models/cited_place.dart';
import 'package:specstone_core/src/index_query/models/indexed_link.dart';
import 'package:specstone_core/src/index_query/models/line_range.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';

const _fr =
    'docs/prds/features/f01_login/us01_email_login/fr01_validate_credentials.md';
const _specs = '../../../../specs';
const _domain = 'specs/f02_signup/DOMAIN.md';
const _frName = 'login/email_login/validate_credentials';
const _frPath =
    'prds/features/f01_login/us01_email_login/fr01_validate_credentials.md';

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
  test('a cited-by line names the citer, its item, and its section, with no link text', () async {
    const line = '1. E01 — A wrong password → refused, by $_inv14.';
    final cited = _citedBy(await _index('Check it.', edge: line));
    expect(_of(cited, _domain, 'INV-14'), [
      const CitedBy(
        docPath: _frPath,
        name: _frName,
        docType: 'fr',
        byItem: 'E01',
        bySection: 'edge_cases',
      ),
    ]);
    expect(
      citedByLineOf(_of(cited, _domain, 'INV-14').single),
      '  · cited by $_frName (fr) E01 #edge_cases',
    );
  });

  test('a link on a line that belongs to no item reads no item', () async {
    const line = 'The system shall lock, by $_inv13.';
    final cited = _citedBy(await _index(line));
    expect(_of(cited, _domain, 'INV-13'), [
      const CitedBy(
        docPath: _frPath,
        name: _frName,
        docType: 'fr',
        byItem: null,
        bySection: 'statement',
      ),
    ]);
    expect(
      citedByLineOf(_of(cited, _domain, 'INV-13').single),
      '  · cited by $_frName (fr) — #statement',
    );
  });

  test("a link in a doc's lead names the lead's section key", () async {
    final cited = _citedBy(
      await _index(
        'Check it.',
        extra: {
          'docs/specs/topics/guide.md': '# Guide\n\nSee [INV-14](../f02_signup/DOMAIN.md#invariants).\n\n## Purpose\nNothing.\n',
        },
      ),
    );
    expect(_of(cited, _domain, 'INV-14').single.bySection, leadKey);
  });

  test('a filtered index drops links from the given docs into the given docs alone', () async {
    const guideLine = 'Also [INV-14](../f02_signup/DOMAIN.md#invariants).';
    final index = await _index(
      'Cites $_inv13, $_inv14, and [RULE-2]($_specs/topics/ranges.md#rules).',
      extra: {
        'docs/specs/topics/guide.md': '# Guide\n\n## Purpose\n$guideLine\n',
      },
    );
    final cited = _citedBy(index);
    final guide = index.at('specs/topics/guide.md')!;

    final filtered = cited.withoutLinks(from: {_frPath}, into: {_domain});

    expect(_of(filtered, _domain, 'INV-14'), [
      CitedBy(
        docPath: guide.docPath,
        name: guide.name,
        docType: 'topic',
        byItem: null,
        bySection: 'purpose',
      ),
    ]);
    expect(
      filtered.containsKey(
        const CitedPlace(docPath: _domain, kind: CitedKind.item, key: 'INV-13'),
      ),
      isFalse,
    );
    expect(_of(filtered, 'specs/topics/ranges.md', 'RULE-2'), hasLength(1));
    expect(_of(cited, _domain, 'INV-13'), hasLength(1));
    expect(_of(cited, _domain, 'INV-14'), hasLength(2));
    expect(filtered.inline, cited.inline);
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
        CitedBy(
          docPath: guide.docPath,
          name: guide.name,
          docType: 'topic',
          byItem: null,
          bySection: 'purpose',
        ),
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
      final i = await _index(
        statement,
        extra: {
          ...glossaryFile,
          'docs/specs/topics/guide.md': '# Guide\n\n## Purpose\nSee [E01](../../prds/features/f01_login/us01_email_login/fr01_validate_credentials.md#edge-cases).\n',
        },
      );
      final a = answerContext(
        i,
        pickBundle(i, [_frName], BundleMode.design, noProject: false),
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
      expect(a.text, contains('  · cited by guide (topic) — #purpose'));
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

  test(
    'an item many docs cite gets one line per citing doc, item, and section',
    () async {
      final index = await _index(
        'Check it, by $_inv14.',
        edge: '1. E01 — Refused, by $_inv14.',
        extra: {
          'docs/specs/topics/guide.md': '# Guide\n\n## Purpose\nFirst [INV-14](../f02_signup/DOMAIN.md#invariants).\n\n## Notes\nSecond [INV-14](../f02_signup/DOMAIN.md#invariants).\n',
        },
      );
      final cited = _of(_citedBy(index), _domain, 'INV-14');
      expect(cited.map((c) => (c.name, c.byItem, c.bySection)), [
        (_frName, null, 'statement'),
        (_frName, 'E01', 'edge_cases'),
        ('guide', null, 'purpose'),
        ('guide', null, 'notes'),
      ]);
    },
  );

  test(
    'two links from one item and section into one place give one line',
    () async {
      const edge = '1. E01 — Refused, by $_inv14 and $_inv14.';
      final index = await _index('Both $_inv14 and $_inv14.', edge: edge);
      final cited = _of(_citedBy(index), _domain, 'INV-14');
      expect(cited.map((c) => (c.byItem, c.bySection)), [
        (null, 'statement'),
        ('E01', 'edge_cases'),
      ]);
      expect({for (final by in cited) citedByLineOf(by)}.length, cited.length);
    },
  );

  test(
    'ID-less items of one section linking one place print one line',
    () async {
      final index = await _index(
        'Check it.',
        extra: {
          'docs/specs/topics/guide.md':
              '# Guide\n\n## Purpose\n- First [INV-14](../f02_signup/DOMAIN.md#invariants).\n'
              '- Second [INV-14](../f02_signup/DOMAIN.md#invariants).\n',
        },
      );
      final cited = _of(_citedBy(index), _domain, 'INV-14');
      expect(cited.map((c) => (c.name, c.byItem, c.bySection)), [
        ('guide', null, 'purpose'),
      ]);
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

  test('two separate ranges on one line give an item both span one entry', () async {
    const line =
        'See [RULE-2](ranges.md#rules) to [RULE-3](ranges.md#rules) and [RULE-2](ranges.md#rules) to [RULE-4](ranges.md#rules).';
    final index = await _index(
      'Check it.',
      extra: {'docs/specs/topics/guide.md': '# Guide\n\n## Purpose\n$line\n'},
    );
    final cited = _citedBy(index);
    const counts = {'RULE-2': 1, 'RULE-3': 1, 'RULE-4': 1};
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
      by: [
        CitedBy(
          docPath: 'a.md',
          name: 'a',
          docType: 'fr',
          byItem: null,
          bySection: 'statement',
        ),
      ],
    );
    const inner = CitedItem(
      kind: CitedKind.item,
      item: 'INV-15',
      sectionKey: 'invariants',
      after: 7,
      by: [
        CitedBy(
          docPath: 'b.md',
          name: 'b',
          docType: 'fr',
          byItem: 'E01',
          bySection: 'edge_cases',
        ),
      ],
    );
    expect(citedLinesAfter(null, [inner, outer]), {
      7: [
        '  · cited by b (fr) E01 #edge_cases',
        '  · cited by a (fr) — #statement',
      ],
    });
  });

  test('a section or whole-doc link many docs cite gets one line per citing section', () async {
    const toDomain = '../f02_signup/DOMAIN.md';
    final index = await _index(
      'See [the invariants]($_specs/f02_signup/DOMAIN.md#invariants) and [the domain]($_specs/f02_signup/DOMAIN.md).',
      extra: {
        'docs/specs/topics/guide.md':
            '# Guide\n\n## Purpose\nFirst [i]($toDomain#invariants).\n\nSecond [i]($toDomain#invariants).\n\n'
            'Third [d]($toDomain).\n\nFourth [d]($toDomain).\n\n'
            '## Notes\nFifth [i]($toDomain#invariants).\n',
      },
    );
    final cited = _citedBy(index);

    expect(
      _ofSection(
        cited,
        _domain,
        'invariants',
      ).map((c) => (c.name, c.bySection)),
      [(_frName, 'statement'), ('guide', 'purpose'), ('guide', 'notes')],
    );
    expect(_ofDoc(cited, _domain).map((c) => (c.name, c.bySection)), [
      (_frName, 'statement'),
      ('guide', 'purpose'),
    ]);
  });

  test('a persona field, a journey step, and an FR traced_from give no line', () async {
    const toStory =
        '../../prds/features/f01_login/us01_email_login/USER_STORY.md';
    const toPersona = '../../prds/personas/buyer/PERSONA.md';
    final index = await _index(
      'Check it.',
      extra: {
        'docs/prds/features/f01_login/us02_reset_password/fr02_trace.md': '---\nverify_method: test\ntraced_from:\n  - S1\n  - email_login#S2\n---\n\n# Trace\n\n## Statement\nThe system shall trace.\n',
        'docs/prds/journeys/sign_in/JOURNEY.md': '---\npersona:\n  - buyer\n---\n\n# Sign in\n\n## Steps\n### 1. Enter\nstep: login/email_login S1\n',
        'docs/specs/topics/guide.md':
            '# Guide\n\n## Purpose\nSee [the story]($toStory) and [the buyer]($toPersona).\n',
      },
    );
    final cited = _citedBy(index);
    const story = 'prds/features/f01_login/us01_email_login/USER_STORY.md';
    const persona = 'prds/personas/buyer/PERSONA.md';

    expect(index.at('prds/journeys/sign_in/JOURNEY.md')!.isTyped, isTrue);
    expect(_ofDoc(cited, story).map((c) => c.name), ['guide']);
    expect(_ofDoc(cited, persona).map((c) => c.name), ['guide']);
    expect(
      cited.keys.where(
        (k) =>
            k.docPath ==
                'prds/features/f01_login/us02_reset_password/USER_STORY.md' ||
            k.docPath == 'prds/journeys/sign_in/JOURNEY.md',
      ),
      isEmpty,
    );
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
      expect(cited.single.bySection, 'statement');
    },
  );

  group('section, block, and whole-doc links', () {
    const toDomain = '$_specs/f02_signup/DOMAIN.md';
    const toFr =
        '../../prds/features/f01_login/us01_email_login/fr01_validate_credentials.md';

    ContextAnswer design(DocIndex index) => answerContext(
      index,
      pickBundle(index, [_frName], BundleMode.design, noProject: false),
      label: _frName,
      byCode: false,
    );

    List<Map<String, Object?>> docsOf(ContextAnswer answer) =>
        (answer.json['docs']! as List).cast<Map<String, Object?>>();

    test('a section link into an appended section prints no line', () async {
      const line = 'Lock, as [the invariants]($toDomain#invariants) say.';
      final text = design(await _index(line)).text;

      expect(text, contains('## Invariants\n- **INV-13**'));
      expect(text, isNot(contains('cited by')));
    });

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
        contains('## Edge cases\n  · cited by guide (topic) — #purpose\n'),
      );
      expect('cited by guide'.allMatches(text), hasLength(1));
    });

    test(
      'a whole-doc link into an appended summary doc prints no line',
      () async {
        const line = 'Lock, see [the domain]($toDomain).';
        final text = design(await _index(line)).text;

        expect(
          text,
          contains(
            '==> signup (domain) · specs/f02_signup/DOMAIN.md · summary · cited <==\n'
            '# Sign-up domain',
          ),
        );
        expect(text, isNot(contains('cited by')));
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
          '  · cited by guide (topic) — #purpose\n'
          '---\nverify_method: test',
        ),
      );
    });

    test('a block link into an appended block prints no line and its part has no citedBy key', () async {
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

      expect(answer.text, contains('### A note\nShort.'));
      expect(answer.text, isNot(contains('cited by')));
      final part = docsOf(answer)
          .firstWhere((d) => d['path'] == 'specs/topics/blocks.md');
      expect(part.containsKey('citedBy'), isFalse);
    });

    test("a picked part's --json citedBy entry names its citing section, with no line", () async {
      const line = 'See [the edge cases]($toFr#edge-cases).';
      final answer = design(
        await _index(
          'Check it.',
          extra: {
            'docs/specs/topics/guide.md': '# Guide\n\n## Purpose\n$line\n',
          },
        ),
      );

      final picked = docsOf(answer).firstWhere((d) => d['name'] == _frName);
      expect(picked['citedBy'], [
        {
          'kind': 'section',
          'item': null,
          'section': 'edge_cases',
          'name': 'guide',
          'docType': 'topic',
          'byItem': null,
          'bySection': 'purpose',
        },
      ]);
    });

    test('an unplaced anchor joins the doc-level entry', () async {
      const line = 'See [the title]($toFr#validate-credentials).';
      final index = await _index(
        'Check it.',
        extra: {'docs/specs/topics/guide.md': '# Guide\n\n## Purpose\n$line\n'},
      );
      final cited = _citedBy(index);
      final fr = index.at(_fr.substring('docs/'.length))!.docPath;

      expect(_ofDoc(cited, fr).map((c) => c.bySection), ['purpose']);
      expect(_ofSection(cited, fr, 'statement'), isEmpty);
      final picked = docsOf(design(index))
          .firstWhere((d) => d['name'] == _frName);
      expect((picked['citedBy']! as List).single, containsPair('kind', 'doc'));
    });

    test('an unplaced-anchor line prints right after the naming line of the doc', () async {
      const line = 'See [the title]($toFr#validate-credentials).';
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
          '  · cited by guide (topic) — #purpose\n'
          '---\nverify_method: test',
        ),
      );
      expect('cited by guide'.allMatches(text), hasLength(1));
    });

    test('an anchor matching nothing gets no line', () async {
      final cited = _citedBy(await _index('See [it]($toDomain#nothing-here).'));

      expect(cited.keys.where((k) => k.docPath == _domain), isEmpty);
    });

    test('one line holding an item link and a section link gives two entries, the item one once', () async {
      const line = 'See $_inv14 and [the invariants]($toDomain#invariants).';
      final cited = _citedBy(await _index(line));

      expect(_of(cited, _domain, 'INV-14').map((c) => c.bySection), [
        'statement',
      ]);
      expect(_ofSection(cited, _domain, 'invariants').map((c) => c.bySection), [
        'statement',
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

    test('the --json citedBy entry carries bySection and no line', () {
      const by = <CitedBy>[
        CitedBy(
          docPath: 'specs/topics/guide.md',
          name: 'guide',
          docType: 'topic',
          byItem: null,
          bySection: 'purpose',
        ),
      ];
      const own = {
        'name': 'guide',
        'docType': 'topic',
        'byItem': null,
        'bySection': 'purpose',
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
    const edge = '1. E01 — A wrong password → refused.';
    const citedLine = '  · cited by guide (topic) — #purpose';
    const frHead = '==> $_frName (fr) · $_frPath#edge_cases · item E01';
    const guide =
        '# Guide\n\n## Purpose\nSee [E01](../../prds/features/f01_login/us01_email_login/fr01_validate_credentials.md#edge-cases).\n';

    Future<DocIndex> citedIndex() => _index(
      'Check it.',
      edge: edge,
      extra: {'docs/specs/topics/guide.md': guide},
    );

    Future<ContextAnswer> splitDesign() async {
      final i = await citedIndex();
      return answerContext(
        i,
        pickBundle(i, [_frName], BundleMode.design, noProject: false),
        label: _frName,
        byCode: false,
        split: true,
      );
    }

    test('prints cited-by lines as refs parts', () async {
      final a = await splitDesign();

      expect(a.text, isNot(contains('cited by')));
      expect(a.refs!.text, contains('$frHead · cited by <==\n$citedLine\n'));
    });
    test('lists each cited-by part in the refs list', () async {
      final a = await splitDesign();

      expect(a.refs!.text, contains('- $_frName (fr) · cited by [E01]\n'));
    });
    test('marks each cited-by part as one in its entry', () async {
      final a = await splitDesign();

      final entry = a.refs!.entries.singleWhere(
        (e) => e.kind == BundleEntryKind.citedBy && e.itemId != null,
      );
      final lines = a.refs!.text.split('\n');
      expect(entry.doc.name, _frName);
      expect(entry.sectionKey, 'edge_cases');
      expect(entry.itemId, 'E01');
      expect(lines[entry.first - 1], '$frHead · cited by <==');
      expect(entry.last, entry.first + 1);
    });
    test('an item whose lines print inline leaves no part for them', () async {
      final i = await citedIndex();
      final a = answerContext(
        i,
        pickBundle(i, [_frName], BundleMode.design, noProject: false),
        label: _frName,
        byCode: false,
      );

      expect(a.text, contains('$edge\n$citedLine\n'));
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
        CitedBy(
          docPath: 'specs/topics/guide.md',
          name: 'guide',
          docType: 'topic',
          byItem: null,
          bySection: 'purpose',
        ),
      ],
    );
    final inline = CitedByIndex(const {}, inline: true);
    final parts = CitedByIndex(const {}, inline: false);

    expect(citedLinesAfter(parts, [item]), isEmpty);
    expect(citedLinesAfter(inline, [item]), {
      3: ['  · cited by guide (topic) — #purpose'],
    });
  });

  test('the stored lines equal a fresh scan of the docs, place by place and line by line, whatever the link names', () async {
    const toDomain = '$_specs/f02_signup/DOMAIN.md';
    const toFr =
        '../../prds/features/f01_login/us01_email_login/fr01_validate_credentials.md';
    final index = await _index(
      'Lock by $_inv13 and $_inv14, see [the domain]($toDomain) and '
      '[the invariants]($toDomain#invariants), per [a note]($_specs/topics/blocks.md#a-note) '
      'and [the title]($_specs/topics/blocks.md#blocks).',
      extra: {
        'docs/specs/topics/blocks.md':
            '# Blocks\n\n## Examples\n### A note\nShort.\n',
        'docs/specs/topics/guide.md':
            '# Guide\n\n## Purpose\nSee [RULE-2](ranges.md#rules) to [RULE-4](ranges.md#rules), '
            '[the edge cases]($toFr#edge-cases), and [the rule]($toFr).\n',
      },
    );

    final stored = citedByIndex(index);
    final fresh = scanCitedBy(
      index.docs,
      set: index.set,
      contentOf: index.contentOf,
      links: [
        for (final doc in index.docs)
          for (final to in index.linkedFrom(doc))
            IndexedLink(source: doc.docPath, target: to.docPath),
      ],
    );

    expect({
      for (final place in fresh.keys) place.kind,
    }, CitedKind.values.toSet());
    expect(fresh.length, greaterThan(8));
    expect(Map.of(stored), fresh);
    expect(stored.keys.toList(), fresh.keys.toList());
  });

  test('a scan loads only the docs a link starts from or reaches', () async {
    const lonely = 'docs/specs/topics/lonely.md';
    final index = await _index(
      'Lock by $_inv13.',
      extra: {lonely: '# Lonely\n\n## Purpose\nNothing links here.\n'},
    );
    final loaded = <String>{};

    scanCitedBy(
      index.docs,
      set: index.set,
      contentOf: (doc) {
        loaded.add(doc.docPath);
        return index.contentOf(doc);
      },
      links: [
        for (final doc in index.docs)
          for (final to in index.linkedFrom(doc))
            IndexedLink(source: doc.docPath, target: to.docPath),
      ],
    );

    expect(loaded, contains(_domain));
    expect(loaded, contains(_frPath));
    expect(loaded, isNot(contains('specs/topics/lonely.md')));
  });

  test('the line of a link on the last line of a doc with no final newline is read', () async {
    const guide = 'docs/specs/topics/guide.md';
    const last = 'See [INV-14](../f02_signup/DOMAIN.md#invariants)';
    final cited = _citedBy(
      await _index(
        'Check it.',
        extra: {guide: '# Guide\n\n## Purpose\nFirst.\n$last'},
      ),
    );

    expect(_of(cited, _domain, 'INV-14').map((by) => by.bySection), [
      'purpose',
    ]);
  });

  group('citedItemsIn', () {
    const inv15 = '[INV-15]($_specs/f02_signup/DOMAIN.md#invariants)';
    const nesting = <String, String>{
      'docs/specs/f02_signup/DOMAIN.md':
          '# Sign-up domain\n\n## Invariants\n'
          '- **INV-13** One.\n'
          '  - **INV-14** Nested in one.\n'
          '- **INV-15** Three.\n'
          '- **INV-13** One again.\n',
    };

    /// The cited items of the domain's Invariants as `<ID>@<line printed after>`.
    Future<List<String>> citedIn({
      LineRange? within,
      Map<String, LineRange>? extents,
    }) async {
      final index = await _index(
        'Cites $_inv13, $_inv14, and $inv15.',
        extra: nesting,
      );
      final doc = index.at('specs/f02_signup/DOMAIN.md')!;
      final content = index.contentOf(doc);
      final sections = citedSectionsOf(content, index.typeOf(doc));
      final at = sections.indexWhere((s) => s.key == 'invariants');
      return [
        for (final item in citedItemsIn(
          _citedBy(index),
          doc,
          content,
          sections[at],
          at,
          within: within,
          extents: extents,
        ))
          '${item.item}@${item.after}',
      ];
    }

    test('a nested item prints before its outer item, a repeated ID spans its first item', () async {
      expect(await citedIn(), ['INV-14@5', 'INV-13@5', 'INV-15@6']);
    });

    test(
      'items whole inside the lines asked for are the only ones given',
      () async {
        expect(await citedIn(within: const LineRange(first: 6, last: 6)), [
          'INV-15@6',
        ]);
      },
    );

    test(
      'the extents a caller holds are the ones read, not the section again',
      () async {
        expect(
          await citedIn(
            extents: const {'INV-15': LineRange(first: 9, last: 9)},
          ),
          ['INV-15@9'],
        );
      },
    );
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
