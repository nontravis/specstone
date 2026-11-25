import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/doc_model/percent_decode.dart';
import 'package:test/test.dart';

void main() {
  group('resolveDocLink', () {
    const from = 'prds/f/us/fr01.md';

    test('a relative .md link resolves against the linking '
        "doc's folder", () {
      expect(
        (resolveDocLink('USER_STORY.md', from) as DocTarget).docPath,
        'prds/f/us/USER_STORY.md',
      );
      expect(
        (resolveDocLink('../FEATURE.md#goal', from) as DocTarget).docPath,
        'prds/f/FEATURE.md',
      );
      expect((resolveDocLink('#goal', from) as DocTarget).docPath, from);
    });

    test('a web address is a WebTarget; a rooted path or one '
        'above the docs root is outside', () {
      expect(resolveDocLink('https://example.com', from), isA<WebTarget>());
      expect(
        (resolveDocLink('/abs.md', from) as OutsideTarget).shown,
        '/abs.md',
      );
      expect(
        (resolveDocLink('../../../../x.md', from) as OutsideTarget).shown,
        '../../../../x.md',
      );
    });

    test('an escape that is not UTF-8 reads as '
        'U+FFFD', () {
      expect(
        (resolveDocLink('%DB.md', from) as DocTarget).docPath,
        'prds/f/us/\u{FFFD}.md',
      );
      expect(
        (resolveDocLink('%C3%28.md', from) as DocTarget).docPath,
        'prds/f/us/\u{FFFD}(.md',
      );
      expect(
        (resolveDocLink('%ED%A0%80.md', from) as DocTarget).docPath,
        contains('\u{FFFD}'),
      );
      expect(percentDecoded('caf%C3%A9'), 'café');
      expect(percentDecoded('50%'), '50%');
      expect(percentDecoded('a%2Fb'), 'a/b');
    });

    test('a character outside the BMP after an escape '
        'keeps its UTF-8 bytes', () {
      expect(percentDecoded('%41\u{1F600}'), 'A\u{1F600}');
      expect(percentDecoded('\u{1F600}%41\u{1F600}'), '\u{1F600}A\u{1F600}');
    });

    test('a text with no escape decodes to itself', () {
      expect(percentDecoded('abc'), 'abc');
      expect(percentDecoded('\u{1F600}.md'), '\u{1F600}.md');
    });

    test('percentDecodesCleanly is false only when '
        'an escape needs U+FFFD', () {
      expect(percentDecodesCleanly('%DB.md'), isFalse);
      expect(percentDecodesCleanly('a%C3%28b'), isFalse);
      expect(percentDecodesCleanly('caf%C3%A9'), isTrue);
      expect(percentDecodesCleanly('50%'), isTrue);
      expect(percentDecodesCleanly('abc'), isTrue);
      expect(percentDecodesCleanly('\u{FFFD}.md'), isTrue);
    });

    test('an encoded slash still names no doc', () {
      expect(resolveDocLink('a%2Fb.md', from), isA<OutsideTarget>());
    });

    test('a malformed http href is a WebTarget', () {
      expect(resolveDocLink('http://h:abc/x.md', from), isA<WebTarget>());
    });

    test('a link to a doc carries its anchor', () {
      final target = resolveDocLink(
        '../../d03_non_functional.md#performance',
        'prds/f/us01/fr01.md',
      ) as DocTarget;
      expect(target.docPath, 'prds/d03_non_functional.md');
      expect(target.anchor, 'performance');
    });

    test('a bare fragment resolves against the linking '
        'doc with its anchor', () {
      final target = resolveDocLink('#rules', from) as DocTarget;
      expect(target.docPath, from);
      expect(target.anchor, 'rules');
    });

    test('an empty fragment resolves with anchor ""', () {
      final target = resolveDocLink('#', from) as DocTarget;
      expect(target.docPath, from);
      expect(target.anchor, '');
    });

    test('a doc link keeps its fragment as written in rawAnchor', () {
      final target = resolveDocLink('x.md#caf%C3%A9', from) as DocTarget;
      expect(target.anchor, 'caf\u00e9');
      expect(target.rawAnchor, 'caf%C3%A9');
    });

    test('a doc link with no fragment has anchor null', () {
      final target = resolveDocLink('USER_STORY.md', from) as DocTarget;
      expect(target.anchor, isNull);
    });

    test('a path out of the docs root and back in '
        'by name is the doc it names', () {
      final target = resolveDocLink('../../../docs/prds/x.md', 'prds/f/a.md');
      expect(target, isA<DocTarget>());
      expect((target as DocTarget).docPath, 'prds/x.md');
      expect(
        resolveDocLink('../../../../docs/prds/x.md', 'prds/f/a.md'),
        isA<OutsideTarget>(),
      );
    });
  });

  group('relativeFilePathOf', () {
    const from = 'prds/f/FEATURE.md';

    test('a path leaving the docs root keeps its leading '
        '../ segments', () {
      expect(relativeFilePathOf('../../../x/a.png', from), '../x/a.png');
      expect(relativeFilePathOf('../../../../x.md', from), '../../x.md');
      expect(
        relativeFilePathOf('../../../../docs/p.md', from),
        '../../docs/p.md',
      );
    });

    test('a path out of the docs root and back in '
        'by name is relative to the docs root', () {
      expect(
        relativeFilePathOf('../../../docs/prds/x.md', 'prds/f/a.md'),
        'prds/x.md',
      );
      expect(
        relativeFilePathOf('../../../../docs/prds/x.md', 'prds/f/a.md'),
        '../../docs/prds/x.md',
      );
    });

    test('a path inside the docs root is relative to it, '
        'decoded, with no fragment or query', () {
      expect(
        relativeFilePathOf('flow%20chart.png#top', from),
        'prds/f/flow chart.png',
      );
      expect(relativeFilePathOf('a.png?raw=1', from), 'prds/f/a.png');
      expect(
        relativeFilePathOf('./sub/../a/./b.dart', from),
        'prds/f/a/b.dart',
      );
      expect(relativeFilePathOf('../../d03.md', from), 'd03.md');
    });

    test('a web address, another scheme, an authority, a '
        'rooted path, and an empty path give null', () {
      for (final href in [
        'https://e.com/a.png',
        'mailto:a@b.c',
        '//host/a.png',
        '/abs/x.md',
        '#top',
        '?q=1',
        '',
        'a%2Fb.png',
      ]) {
        expect(relativeFilePathOf(href, from), isNull, reason: href);
      }
    });
  });

  group('relativeFilePathOf for a record', () {
    const record = '.specstone/records/f01_login/IMPLEMENTATION.md';

    test('a path in the project keeps its project-root spelling', () {
      expect(relativeFilePathOf('../../../docs/x.md', record), 'docs/x.md');
      expect(relativeFilePathOf('../../../lib/a.dart', record), 'lib/a.dart');
    });

    test('a walk ending at the docs root or the project root gives null', () {
      expect(relativeFilePathOf('../../../docs/', record), isNull);
      expect(relativeFilePathOf('../../../docs/.', record), isNull);
      expect(relativeFilePathOf('../../../', record), isNull);
    });
  });

  group('a link between the docs root and the records root', () {
    const record = '.specstone/records/f01_login/IMPLEMENTATION.md';
    const doc = 'prds/f/us/fr01.md';

    String? docPathOf(String href, String from) =>
        switch (resolveDocLink(href, from)) {
          DocTarget(:final docPath) => docPath,
          _ => null,
        };

    test('a record reaches a docs doc through the project root', () {
      expect(
        docPathOf('../../../docs/specs/topics/rules.md#r1', record),
        'specs/topics/rules.md',
      );
    });

    test('a record reaches another record by its records DocPath', () {
      expect(
        docPathOf('../f02_signup/IMPLEMENTATION.md', record),
        '.specstone/records/f02_signup/IMPLEMENTATION.md',
      );
    });

    test('a record link to a project file outside both roots is outside', () {
      expect(
        resolveDocLink('../../../README.md', record),
        isA<OutsideTarget>(),
      );
      expect(resolveDocLink('../../../../x.md', record), isA<OutsideTarget>());
    });

    test('a docs doc reaches a record by its records DocPath', () {
      expect(docPathOf('../../../../$record', doc), record);
    });

    test('a docs doc link to a project file outside both roots is outside', () {
      expect(
        resolveDocLink('../../../../README.md', doc),
        isA<OutsideTarget>(),
      );
    });

    test('a file path stays relative to the root of the doc that holds it', () {
      expect(
        relativeFilePathOf('../../../docs/specs/rules.md', record),
        'docs/specs/rules.md',
      );
      expect(relativeFilePathOf('../../../README.md', record), 'README.md');
      expect(relativeFilePathOf('../../../../$record', doc), '../$record');
    });
  });
}
