import 'package:specstone_core/src/doc_model/doc_link.dart';
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
  });
}
