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
  });
}
