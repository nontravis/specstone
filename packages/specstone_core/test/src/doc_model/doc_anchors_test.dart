import 'dart:convert';
import 'dart:io';

import 'package:markdown/markdown.dart';
import 'package:specstone_core/src/doc_model/doc_anchors.dart';
import 'package:specstone_core/src/doc_model/markdown_body.dart';
import 'package:test/test.dart';

import '../../helpers/package_root.dart';

void main() {
  group('github-slugger fixture, one doc in order', () {
    final entries = _fixtureEntries();
    final anchors = anchorsOf([
      for (final entry in entries)
        if (!_skipped.containsKey(entry.name))
          Element('h2', [Text(entry.input)]),
    ]);
    var slugIndex = 0;
    for (final entry in entries) {
      if (_skipped.containsKey(entry.name)) {
        test(
          '${entry.name} (skipped, see README)',
          skip: _skipped[entry.name],
          () {},
        );
        continue;
      }
      final expected = entry.expected;
      final i = slugIndex++;
      test(entry.name, () {
        expect(anchors.headingSlugs[i], expected);
      });
    }
  });

  group('heading slugs', () {
    test('resolve_doc_links E17: ### `move` — FR-01 gives move--fr-01', () {
      final anchors = anchorsOf(_parse('### `move` — FR-01\n'));
      expect(anchors.headingSlugs, ['move--fr-01']);
    });

    test('E17: the second ## Notes of one doc gives notes-1', () {
      final anchors = anchorsOf(_parse('## Notes\n\n## Notes\n'));
      expect(anchors.headingSlugs, ['notes', 'notes-1']);
    });

    test('## A & B gives a--b', () {
      final anchors = anchorsOf(_parse('## A & B\n'));
      expect(anchors.headingSlugs, ['a--b']);
    });

    test('a heading with a link, emphasis, and raw span gives text only', () {
      final anchors = anchorsOf(
        _parse('## [a link](x.md) and *stress* <span>raw</span>\n'),
      );
      expect(anchors.headingSlugs, ['a-link-and-stress-raw']);
    });

    test('Notes, Notes, Notes-1 gives notes, notes-1, notes-1-1', () {
      final anchors = anchorsOf(_parse('## Notes\n\n## Notes\n\n## Notes-1\n'));
      expect(anchors.headingSlugs, ['notes', 'notes-1', 'notes-1-1']);
    });

    test('a Thai heading keeps every vowel and tone mark', () {
      final anchors = anchorsOf(_parse('## ภาษาไทย ทดสอบ\n'));
      expect(anchors.headingSlugs, ['ภาษาไทย-ทดสอบ']);
    });

    test('Résumé² drops the Other_Number superscript', () {
      final anchors = anchorsOf(_parse('## Résumé²\n'));
      expect(anchors.headingSlugs, ['résumé']);
    });

    test('Ⅻ Ⓐ keeps the letter number and the circled letter', () {
      final anchors = anchorsOf(_parse('## Ⅻ Ⓐ\n'));
      expect(anchors.headingSlugs, ['ⅻ-ⓐ']);
    });

    test('a‿b keeps connector punctuation', () {
      final anchors = anchorsOf(_parse('## a‿b\n'));
      expect(anchors.headingSlugs, ['a‿b']);
    });

    test('a zero-width joiner drops', () {
      final anchors = anchorsOf(_parse('## a${_zwj}b\n'));
      expect(anchors.headingSlugs, ['ab']);
    });

    test('Q&A: 50%! gives qa-50', () {
      final anchors = anchorsOf(_parse('## Q&A: 50%!\n'));
      expect(anchors.headingSlugs, ['qa-50']);
    });

    test(
      'the title line counts: # Notes then ## Notes gives notes, notes-1',
      () {
        final anchors = anchorsOf(_parse('# Notes\n\n## Notes\n'));
        expect(anchors.headingSlugs, ['notes', 'notes-1']);
      },
    );
  });

  group('html ids', () {
    test('resolve_doc_links E16: <a id>, <span id>, <a name> all count', () {
      final anchors = anchorsOf(
        _parse(
          '<a id="my-id"></a>\n<span id="my-id"></span>\n'
          '<a name="my-id">x</a>\n',
        ),
      );
      expect(anchors.htmlIds, contains('my-id'));
      expect(anchors.holds('my-id'), isTrue);
    });

    test('RULE-13: A, A-1, A headings and a body id a', () {
      final anchors = anchorsOf(
        _parse('<p id="A">x</p>\n\n## A\n\n## A\n\n## A-1\n\n## A\n'),
      );
      expect(anchors.holds('a'), isTrue);
      expect(anchors.holds('a-1'), isTrue);
      expect(anchors.holds('a-2'), isTrue);
    });

    test('a footnote id stays out of the set', () {
      final anchors = anchorsOf(_parse('a footnote[^1]\n\n[^1]: note\n'));
      expect(anchors.htmlIds.contains('fn-1'), isFalse);
      expect(anchors.htmlIds.contains('fnref-1'), isFalse);
      expect(anchors.holds('fn-1'), isFalse);
    });

    test('an id inside a script tag the filter escapes does not count', () {
      final anchors = anchorsOf(
        _parse(
          '<script type="text/javascript" id="on-script">var x = '
          '"<span id=\'in-script\'>";</script>\n',
        ),
      );
      expect(anchors.htmlIds.contains('in-script'), isFalse);
      expect(anchors.htmlIds.contains('on-script'), isFalse);
    });

    test('an id inside an html comment does not count', () {
      final anchors = anchorsOf(_parse('<!-- <span id="in-comment"> -->\n'));
      expect(anchors.htmlIds.contains('in-comment'), isFalse);
    });

    test('an id inside inline code does not count', () {
      final anchors = anchorsOf(_parse('`<span id="in-code">`\n'));
      expect(anchors.htmlIds.contains('in-code'), isFalse);
    });

    test('an id inside a fenced block does not count', () {
      final anchors = anchorsOf(_parse('```\n<span id="in-fence">\n```\n'));
      expect(anchors.htmlIds.contains('in-fence'), isFalse);
    });
  });

  group('headingSlugOf', () {
    test('lower-cases, drops other characters, space becomes dash', () {
      expect(headingSlugOf('Hello, World!'), 'hello-world');
      expect(headingSlugOf('Résumé²'), 'résumé');
    });
  });
}

final _zwj = String.fromCharCode(0x200D);

// Entries skipped because a code point's casing or Unicode category changed
// between github-slugger's tables (V8's) and Dart's; reasons in the README.
const _skipped = <String, String>{
  'Cased_Letter': 'Dart toLowerCase leaves U+01C5-class capitals uncased',
  'Letter': 'Dart toLowerCase leaves U+A640-class capitals uncased',
  'Uppercase_Letter':
      'Dart toLowerCase leaves U+0524 and Cherokee capitals '
      'uncased, and maps U+0130 to i, not i + U+0307',
  'Unassigned':
      'U+3174F is Lo in Dart Unicode tables and unassigned in '
      "github-slugger's",
};

typedef _FixtureEntry = ({String name, String input, String expected});

List<_FixtureEntry> _fixtureEntries() {
  final file = File.fromUri(
    packageRoot().uri.resolve('test/fixtures/github_slugger/fixtures.json'),
  );
  final entries = jsonDecode(file.readAsStringSync()) as List<Object?>;
  return [
    for (final entry in entries)
      switch (entry) {
        {
          'name': final String name,
          'input': final String input,
          'expected': final String expected,
        } =>
          (name: name, input: input, expected: expected),
        _ => throw FormatException('not a fixture entry: $entry'),
      },
  ];
}

List<Node> _parse(String text) {
  final nodes = parseMarkdown(text);
  if (nodes == null) throw StateError('parseMarkdown failed: $text');
  return nodes;
}
