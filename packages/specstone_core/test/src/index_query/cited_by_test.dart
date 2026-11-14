// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/index_query/bundle_trim.dart';
import 'package:specstone_core/src/index_query/cited_by.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
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
    cited[(docPath: docPath, itemId: itemId)] ?? const [];

void main() {
  test('f01/us05/fr06/e01: an item link from an item of another doc gives its line, doc, and item', () async {
    const line = '1. E01 — A wrong password → refused, by $_inv14.';
    final cited = _citedBy(await _index('Check it.', edge: line));
    expect(_of(cited, _domain, 'INV-14'), [
      (name: _frName, docType: 'fr', byItem: 'E01', line: line),
    ]);
  });

  test(
    'f01/us05/fr06/e02: a link on a line that belongs to no item reads no item',
    () async {
      const line = 'The system shall lock, by $_inv13.';
      final cited = _citedBy(await _index(line));
      expect(_of(cited, _domain, 'INV-13'), [
        (name: _frName, docType: 'fr', byItem: null, line: line),
      ]);
    },
  );

  test(
    'f01/us05/fr06/e03: a range gives one line under each item it spans',
    () async {
      const line =
          'See [RULE-2](ranges.md#rules) to [RULE-4](ranges.md#rules).';
      final index = await _index(
        'Check it.',
        extra: {'docs/specs/topics/guide.md': '# Guide\n\n## Purpose\n$line\n'},
      );
      final cited = _citedBy(index);
      final guide = index.at('specs/topics/guide.md')!;
      for (final id in ['RULE-2', 'RULE-3', 'RULE-4']) {
        expect(_of(cited, 'specs/topics/ranges.md', id), [
          (name: guide.name, docType: 'topic', byItem: null, line: line),
        ], reason: id);
      }
      expect(_of(cited, 'specs/topics/ranges.md', 'RULE-1'), isEmpty);
      expect(_of(cited, 'specs/topics/ranges.md', 'RULE-5'), isEmpty);
    },
  );

  test('f01/us05/fr06/e04: an item of a doc whose type lists bundle: gets no line, read by the key', () async {
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

  test('f01/us05/fr06/e05: a link from the item own doc, or from an untyped doc, gives no line', () async {
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
  });

  test('f01/us05/fr06/e07: an item many docs cite gets one line per link, none dropped', () async {
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
    'f01/us05/fr06/e07: two links to one item on one line give one line',
    () async {
      const line = 'Both $_inv14 and $_inv14.';
      final cited = _of(_citedBy(await _index(line)), _domain, 'INV-14');
      expect(cited, hasLength(1));
    },
  );

  test('f01/us05/fr06/e08: a doc link or a section link names no item and gives no line', () async {
    final cited = _citedBy(
      await _index(
        'See [the domain]($_specs/f02_signup/DOMAIN.md) and [invariants]($_specs/f02_signup/DOMAIN.md#invariants).',
      ),
    );
    expect(cited.keys.where((k) => k.docPath == _domain), isEmpty);
  });

  test('f01/us05/fr06/e09: the lines come from the stored index; the call reads no file', () async {
    final project = await writeLoginProject(
      extra: {..._docs, _fr: _frWith('Lock, by $_inv14.')},
    );
    final session = openSession(project);
    addTearDown(session.close);
    File('${project.path}/docs/specs/f02_signup/DOMAIN.md').deleteSync();
    File('${project.path}/$_fr').deleteSync();
    final cited = _of(citedByIndex(session.index), _domain, 'INV-14');
    expect(cited.single.line, 'Lock, by $_inv14.');
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
