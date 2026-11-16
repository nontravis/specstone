import 'package:specstone_core/src/index_query/cite_candidates.dart';
import 'package:specstone_core/src/index_query/item_words.dart'
    show itemIdPrefixesOf;
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

/// The item ID prefixes of the shipped packs.
final Set<String> _idPrefixes = itemIdPrefixesOf(
  TemplateResolver()
      .resolveCarried(
        packNames: const ['prd-core', 'software-tech'],
        homeDirectory: null,
      )
      .docTypes,
);

/// Each candidate of [lf] as `(line, written, sectionKey, item IDs)`, the IDs
/// joined by a space, so a record compares by value.
List<(int, String, String?, String)> _readAll(String lf) => [
  for (final c in citeCandidatesOf(lf, idPrefixes: _idPrefixes))
    (c.line, c.written, c.sectionKey, c.itemIds.join(' ')),
];

/// A doc whose body starts at file line 6, after a 3-line frontmatter.
String _doc(String body) => '---\nstatus: planned\n---\n\n# T\n$body';

void main() {
  group('citeCandidatesOf', () {
    test('a prefixed address and a path are candidates, a lone-word span is '
        'not', () {
      final read = _readAll(
        _doc(
          '`domain:login`\n'
          '`login`\n'
          'See ../f01_login/DOMAIN.md here.\n'
          '`../f01_login/DOMAIN.md`\n',
        ),
      );
      expect(read, [
        (6, 'domain:login', null, ''),
        (8, '../f01_login/DOMAIN.md', null, ''),
        (9, '../f01_login/DOMAIN.md', null, ''),
      ]);
    });

    test('the #key of a name span and of a '
        'path is its section key, and the written text leaves it out', () {
      final read = _readAll(
        _doc(
          '`feature:login#problem` and `topic:doc_model#rules`\n'
          '`../f01_login/DOMAIN.md#invariants` then ../a/B.md#rules.\n',
        ),
      );
      expect(read, [
        (6, 'feature:login', 'problem', ''),
        (6, 'topic:doc_model', 'rules', ''),
        (7, '../f01_login/DOMAIN.md', 'invariants', ''),
        (7, '../a/B.md', 'rules', ''),
      ]);
    });

    test('a section header in a code span right '
        'after a path is its section key', () {
      final read = _readAll(
        _doc('`../f01_login/ERROR.md` `## Error envelope` stays.\n'),
      );
      expect(read, [(6, '../f01_login/ERROR.md', 'error_envelope', '')]);
    });

    test('the item IDs after a candidate on its '
        'line are its own, up to the next citation', () {
      final read = _readAll(
        _doc(
          '`domain:login` INV-6 and INV-7, then `topic:doc_model` RULE-12.\n'
          '`a/b` see `c/d` RULE-7 and NFR-P01\n'
          '(`DOMAIN.md` INV-6)\n'
          '`a/b` INV-1 [l](../x.md) INV-2\n',
        ),
      );
      expect(read, [
        (6, 'domain:login', null, 'INV-6 INV-7'),
        (6, 'topic:doc_model', null, 'RULE-12'),
        (7, 'a/b', null, ''),
        (7, 'c/d', null, 'RULE-7 NFR-P01'),
        (8, 'DOMAIN.md', null, 'INV-6'),
        (9, 'a/b', null, 'INV-1'),
      ]);
    });

    test('a file link, an image, and a web address '
        'end no citation, but a link to a doc does', () {
      final read = _readAll(
        _doc(
          '`domain:login` INV-6, see ![d](d.png) INV-7 [f](f.dart) INV-8 '
          '<https://x.dev> INV-9\n'
          '`a/b` INV-1 [l](../x.md) INV-2 [s](#top) INV-3\n',
        ),
      );
      expect(read, [
        (6, 'domain:login', null, 'INV-6 INV-7 INV-8 INV-9'),
        (7, 'a/b', null, 'INV-1'),
      ]);
    });

    test('a token of no section prefix, such '
        'as UTF-8, SHA256, or Base64, makes no item ID', () {
      expect(
        _readAll(_doc('`gnfr:gnfr` UTF-8, SHA256, Base64 and NFR-P01\n')),
        [(6, 'gnfr:gnfr', null, 'NFR-P01')],
      );
    });

    test('a lettered ID makes no item ID', () {
      expect(_readAll(_doc('`a/b` RULE-7a and RULE-8\n')), [
        (6, 'a/b', null, 'RULE-8'),
      ]);
    });

    test('fenced code, a link, its text, a '
        'reference definition, a scenario ref, and frontmatter give none', () {
      final read = _readAll(
        '---\nnote: `domain:login`\n---\n\n# T\n'
        '```\n`domain:login` ../a/B.md\n```\n'
        '[l](../a/B.md) and [`a/b`](../a/B.md#x)\n'
        '\n[ref]: ../a/B.md\n\n'
        '`S1` and `not a name`\n',
      );
      expect(read, isEmpty);
    });

    test(
      'a doc address inside a longer code span gives none, while a span '
      'that is the whole address, with its #key, and a plain path give one',
      () {
        final read = _readAll(
          _doc(
            '`==> login (domain) · ../f01_login/DOMAIN.md#invariants · base 01 <==`\n'
            '`see ../f01_login/DOMAIN.md now` and `lib/src/journeys/`\n'
            '`domain:login#invariants`\n'
            'See ../f01_login/DOMAIN.md here.\n',
          ),
        );
        expect(read, [
          (8, 'domain:login', 'invariants', ''),
          (9, '../f01_login/DOMAIN.md', null, ''),
        ]);
      },
    );

    test('a doc without a backtick or a .md '
        'path gives none', () {
      expect(_readAll('# T\n\nPlain text, INV-1.\n'), isEmpty);
    });
  });
}
