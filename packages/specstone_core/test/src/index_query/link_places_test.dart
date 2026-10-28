import 'package:specstone_core/src/index_query/link_places.dart';
import 'package:test/test.dart';

void main() {
  group('linkPlacesOf', () {
    List<LinkPlace> placesOf(String body) =>
        linkPlacesOf(body, docPath: 'x.md', firstLine: 1);

    test('final-fix M1: a link is placed by its own href, whatever the links '
        'before it matched', () {
      final places = placesOf('[a](b\\.md)\n\n[u](z.md)\n\n[c](b.md)\n');

      expect(places.map((p) => p.target), ['b.md', 'z.md', 'b.md']);
      expect(places[1].line, 3);
    });

    test('final-fix M1: a use of a reference definition in a blockquote does '
        'not move the line of a later link', () {
      final places = placesOf(
        '> [d]: b.md\n\n[x][d]\n\n[u](z.md)\n\n[c](b.md)\n',
      );

      expect(places.map((p) => p.target), ['b.md', 'z.md', 'b.md']);
      expect(places[1].line, 5);
    });

    test(
      'final-fix M2: 10,000 links in one body are placed within two seconds',
      () {
        final body = List.filled(
          10000,
          'Some filler prose around the link [l](b.md) and more prose after.',
        ).join('\n\n');
        final watch = Stopwatch()..start();

        final places = placesOf(body);

        expect(places, hasLength(10000));
        expect(places.last.line, 19999);
        expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      },
    );

    test('final-fix M2: 10,000 unclosed brackets in one body are scanned '
        'within two seconds', () {
      final body =
          '${'[unclosed link text on its own line\n' * 10000}'
          '[l](b.md)\n';
      final watch = Stopwatch()..start();

      final places = placesOf(body);

      expect(places.map((p) => p.target), ['b.md']);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('final-fix M2: 10,000 definitions with an unclosed < destination are '
        'scanned within two seconds', () {
      final body = [
        for (var i = 0; i < 10000; i++) '[x$i]: <',
        '[l](b.md)',
        '',
      ].join('\n');
      final watch = Stopwatch()..start();

      final places = placesOf(body);

      expect(places.map((p) => p.target), ['b.md']);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });
  });
}
