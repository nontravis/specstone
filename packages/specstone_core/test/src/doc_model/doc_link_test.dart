import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/doc_model/percent_decode.dart';
import 'package:test/test.dart';

void main() {
  group('resolveDocLink', () {
    const from = 'prds/f/us/fr01.md';

    test('plan decision 2: a relative .md link resolves against the linking '
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

    test('plan decision 2: a web address is a WebTarget; a rooted path or one '
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

    test('doc_model/s03/inv7, LP1: an escape that is not UTF-8 reads as '
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

    test('doc_model/s03/inv7, LP1: a character outside the BMP after an escape '
        'keeps its UTF-8 bytes', () {
      expect(percentDecoded('%41\u{1F600}'), 'A\u{1F600}');
      expect(percentDecoded('\u{1F600}%41\u{1F600}'), '\u{1F600}A\u{1F600}');
    });

    test(
      'doc_model/s03/inv7, LP1: a text with no escape decodes to itself',
      () {
        expect(percentDecoded('abc'), 'abc');
        expect(percentDecoded('\u{1F600}.md'), '\u{1F600}.md');
      },
    );

    test('doc_model/s03/inv7, LP1: percentDecodesCleanly is false only when '
        'an escape needs U+FFFD', () {
      expect(percentDecodesCleanly('%DB.md'), isFalse);
      expect(percentDecodesCleanly('a%C3%28b'), isFalse);
      expect(percentDecodesCleanly('caf%C3%A9'), isTrue);
      expect(percentDecodesCleanly('50%'), isTrue);
      expect(percentDecodesCleanly('abc'), isTrue);
      expect(percentDecodesCleanly('\u{FFFD}.md'), isTrue);
    });

    test('doc_model/s03/inv7, LP1: an encoded slash still names no doc', () {
      expect(resolveDocLink('a%2Fb.md', from), isA<OutsideTarget>());
    });

    test('f04/us02/fr04/e21: a WHATWG-unreadable href is an '
        'UnreadableTarget', () {
      expect(
        resolveDocLink('http://h:abc/x.md', from),
        isA<UnreadableTarget>(),
      );
    });

    test('f04/us02/fr04/e03: a link to a doc carries its anchor', () {
      final target = resolveDocLink(
        '../../d03_non_functional.md#performance',
        'prds/f/us01/fr01.md',
      ) as DocTarget;
      expect(target.docPath, 'prds/d03_non_functional.md');
      expect(target.anchor, 'performance');
    });

    test('f04/us02/fr04/e16: a bare fragment resolves against the linking '
        'doc with its anchor', () {
      final target = resolveDocLink('#rules', from) as DocTarget;
      expect(target.docPath, from);
      expect(target.anchor, 'rules');
    });

    test('f04/us02/fr04/e22: an empty fragment resolves with anchor ""', () {
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

    test('f04/us02/fr04/e10, M1: a path out of the docs root and back in '
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

    test('f04/us02/fr04/e10: a path leaving the docs root keeps its leading '
        '../ segments', () {
      expect(relativeFilePathOf('../../../x/a.png', from), '../x/a.png');
      expect(relativeFilePathOf('../../../../x.md', from), '../../x.md');
      expect(
        relativeFilePathOf('../../../../docs/p.md', from),
        '../../docs/p.md',
      );
    });

    test('f04/us02/fr04/e10, M1: a path out of the docs root and back in '
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

    test('f04/us02/fr04/e11: a path inside the docs root is relative to it, '
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

    test('f04/us02/fr04/e13: a web address, another scheme, an authority, a '
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
}
