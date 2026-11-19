import 'dart:convert';

import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/index_query/bare_item_ids.dart';
import 'package:specstone_core/src/index_query/cite_candidates.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_words.dart'
    show scenarioRefPrefix;
import 'package:specstone_core/src/index_query/models/bare_item_id.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:test/test.dart';

import '../../helpers/record_doc_type.dart';

const _prefixes = {'INV-', 'E', 'PG-'};

List<BareItemId> _read(String text) => bareItemIdsOf(
  text,
  idPrefixes: _prefixes,
  citeForms: citeFormsOf(text, idPrefixes: _prefixes),
);

BareItemId _id(int line, int column, String id, [BareIdCitation? citation]) =>
    BareItemId(line: line, column: column, id: id, citation: citation);

const _recordPath = 'specs/f01_feedback/IMPLEMENTATION.md';

/// The bare item IDs a typed doc stores for [bytes].
List<BareItemId> _stored(List<int> bytes) => parseIndexedDoc(
  docPath: _recordPath,
  bytes: bytes,
  match: DocTypeMatcher(
    MergedSet(docTypes: [recordDocType(sections: const [])]),
    targetNames: const [],
  ).match(_recordPath),
  statusesOutside: true,
  idPrefixes: {..._prefixes, scenarioRefPrefix},
).content.lineFacts.bareItemIds;

void main() {
  group('bareItemIdsOf', () {
    test('an ID with no citation before it is stored with none', () {
      expect(_read('see INV-3 here'), [_id(1, 4, 'INV-3')]);
    });

    test('IDs right after a doc link carry its destination as written', () {
      const link = LinkCitation(destination: '../DOMAIN.md');
      expect(_read('[domain:shop](../DOMAIN.md) INV-3 and INV-4'), [
        _id(1, 28, 'INV-3', link),
        _id(1, 38, 'INV-4', link),
      ]);
    });

    test('a link with an anchor and a bare anchor link both cite as '
        'written', () {
      expect(_read('[x](../DOMAIN.md#invariants) INV-3'), [
        _id(
          1,
          29,
          'INV-3',
          const LinkCitation(destination: '../DOMAIN.md#invariants'),
        ),
      ]);
      expect(_read('[rules](#invariants) INV-3'), [
        _id(1, 21, 'INV-3', const LinkCitation(destination: '#invariants')),
      ]);
    });

    test('an ID after a code-span cite carries the cite as written', () {
      expect(_read('`domain:shop` INV-3'), [
        _id(1, 14, 'INV-3', const CiteCitation(written: 'domain:shop')),
      ]);
    });

    test('a comma right after a citation starts no run', () {
      expect(_read('([INV-43](../DOMAIN.md#inv-43), E03)'), [
        _id(1, 32, 'E03'),
      ]);
    });

    test('no ID is read from a code span, a link text, frontmatter, or '
        'fenced code', () {
      expect(_read('see `INV-3` here'), isEmpty);
      expect(_read('see [INV-3](../DOMAIN.md#inv-3) here'), isEmpty);
      expect(_read('---\nnote: INV-3\n---\n# T\n'), isEmpty);
      expect(_read('# T\n\n```\nINV-3\n```\n'), isEmpty);
    });

    test('a scenario ref and a lettered ID are no bare item ID', () {
      expect(_read('see S6 here'), isEmpty);
      expect(_read('see INV-7a here'), isEmpty);
      expect(_stored(utf8.encode('see S6 here\n')), isEmpty);
    });

    test('a range in a run stores each end', () {
      const link = LinkCitation(destination: '../DOMAIN.md');
      expect(_read('[domain:x](../DOMAIN.md) INV-3 to INV-5'), [
        _id(1, 25, 'INV-3', link),
        _id(1, 34, 'INV-5', link),
      ]);
    });

    test('a scenario ref inside a link run is read, never stored', () {
      const link = LinkCitation(destination: '../DOMAIN.md');
      const text = '[domain:x](../DOMAIN.md) S6, INV-3\n';
      const prefixes = {..._prefixes, scenarioRefPrefix};
      expect(
        bareItemIdsOf(
          text,
          idPrefixes: prefixes,
          citeForms: citeFormsOf(text, idPrefixes: prefixes),
        ),
        [_id(1, 29, 'INV-3', link)],
      );
    });

    test('a scenario ref after a link is read, with the link, when asked', () {
      const text = '[domain:x](../DOMAIN.md) S6, INV-3\n';
      const prefixes = {..._prefixes, scenarioRefPrefix};
      const link = LinkCitation(destination: '../DOMAIN.md');
      expect(
        bareItemIdsOf(
          text,
          idPrefixes: prefixes,
          citeForms: citeFormsOf(text, idPrefixes: prefixes),
          includeScenarioRefs: true,
        ),
        [_id(1, 25, 'S6', link), _id(1, 29, 'INV-3', link)],
      );
    });

    test('a cite with a section key before its run carries the cite as '
        'citeFormsOf gives it', () {
      expect(_read('`domain:shop#invariants` INV-3'), [
        _id(1, 25, 'INV-3', const CiteCitation(written: 'domain:shop')),
      ]);
    });

    test('a link spanning two lines starts its run on the line it ends', () {
      expect(_read('[a\nb](../DOMAIN.md) INV-3'), [
        _id(2, 17, 'INV-3', const LinkCitation(destination: '../DOMAIN.md')),
      ]);
    });

    test('a link reference definition label is no bare ID', () {
      expect(_read('See [INV-3].\n\n[INV-3]: ../DOMAIN.md#inv-3\n'), isEmpty);
    });

    test('a CRLF text gives the lines and columns of its LF text', () {
      const lf =
          '---\nstatus: planned\n---\n\n# T\n\n'
          'see INV-3 here\n[domain:x](../DOMAIN.md) INV-4\n';
      final fromLf = _stored(utf8.encode(lf));
      expect(fromLf, [
        _id(7, 4, 'INV-3'),
        _id(8, 25, 'INV-4', const LinkCitation(destination: '../DOMAIN.md')),
      ]);
      expect(_stored(utf8.encode(lf.replaceAll('\n', '\r\n'))), fromLf);
    });
  });
}
