import 'package:specstone_core/src/index_query/cite_candidates.dart';
import 'package:test/test.dart';

/// Each candidate of [lf] as `(line, written, sectionKey, item IDs)`, the IDs
/// joined by a space, so a record compares by value.
List<(int, String, String?, String)> _readAll(String lf) => [
  for (final c in citeCandidatesOf(lf))
    (c.line, c.written, c.sectionKey, c.itemIds.join(' ')),
];

/// A doc whose body starts at file line 6, after a 3-line frontmatter.
String _doc(String body) => '---\nstatus: planned\n---\n\n# T\n$body';

void main() {
  group('citeCandidatesOf', () {
    test('domain:index_query INV-86: a name, a bare one-slug name, and a '
        'path each give one candidate at its file line', () {
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
        (7, 'login', null, ''),
        (8, '../f01_login/DOMAIN.md', null, ''),
        (9, '../f01_login/DOMAIN.md', null, ''),
      ]);
    });

    test('topic:doc_model#rules RULE-48: the #key of a name span and of a '
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

    test('report_old_cite_forms E08: a section header in a code span right '
        'after a path is its section key', () {
      final read = _readAll(
        _doc('`../f01_login/ERROR.md` `## Error envelope` stays.\n'),
      );
      expect(read, [(6, '../f01_login/ERROR.md', 'error_envelope', '')]);
    });

    test('apply_steps_and_pins E47: the item IDs after a candidate on its '
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

    test('topic:doc_model#rules RULE-33: a lettered ID makes no item ID', () {
      expect(_readAll(_doc('`a/b` RULE-7a and RULE-8\n')), [
        (6, 'a/b', null, 'RULE-8'),
      ]);
    });

    test('topic:doc_model#rules RULE-48: fenced code, a link, its text, a '
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

    test('topic:doc_model#rules RULE-48: a doc without a backtick or a .md '
        'path gives none', () {
      expect(_readAll('# T\n\nPlain text, INV-1.\n'), isEmpty);
    });
  });
}
