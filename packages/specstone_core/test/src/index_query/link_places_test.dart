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

    test('f04/us02/fr04, f04/nfr-p03, FN4: 10,000 brackets nested around one '
        'link are placed within one second', () {
      final body = '${'[' * 10000}x](b.md)${']' * 9999}\n';
      final watch = Stopwatch()..start();

      final places = placesOf(body);
      watch.stop();

      expect(places, [(target: 'b.md', line: 1, shown: 'b.md')]);
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('f04/us02/fr04, f04/nfr-p03, FN4: 10,000 nested inline destinations '
        'are scanned within one second', () {
      final body = '${'[a](' * 10000}x${')' * 10000}\n\n[l](b.md)\n';
      final watch = Stopwatch()..start();

      final places = placesOf(body);
      watch.stop();

      expect(places, [(target: 'b.md', line: 3, shown: 'b.md')]);
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('f04/us02/fr04, f04/nfr-p03, FN4: 10,000 escaped brackets before one '
        'close are scanned within one second', () {
      final body = '[${r'\[' * 10000}]\n\n[d]: b.md\n\n[l](b.md)\n';
      final watch = Stopwatch()..start();

      final places = placesOf(body);
      watch.stop();

      expect(places, [(target: 'b.md', line: 5, shown: 'b.md')]);
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('f04/us02/fr04, f04/nfr-p03, FN4: 40,000 escaped openers sharing one '
        'close before a long destination are scanned within one second', () {
      final body = '[${r'\[' * 40000}](${' ' * 40000}zzzzz)\n\n[l](b.md)\n';
      final watch = Stopwatch()..start();

      final places = placesOf(body);
      watch.stop();

      expect(places, [(target: 'b.md', line: 3, shown: 'b.md')]);
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('f04/us02/fr04, FN4: a reference whose text has blank runs and '
        'capitals is placed at its use', () {
      final places = placesOf('[foo bar]: b.md\n\n[Foo   Bar]\n');

      expect(places, [(target: 'b.md', line: 3, shown: 'b.md')]);
    });

    test('f04/us02/fr04, FN4: an angle-bracket destination with a space is '
        'placed at its use', () {
      final places = placesOf('x\n\n[a](<b c.md>)\n');

      expect(places, [(target: 'b c.md', line: 3, shown: 'b c.md')]);
    });

    test('f04/us02/fr04, FN4: a U+0085 inside an inline destination is not '
        'blank, so the use keeps it', () {
      final places = placesOf('[l](b\u0085c.md)\n');

      expect(places, [(target: 'b\u0085c.md', line: 1, shown: 'b\u0085c.md')]);
    });

    test('f04/us02/fr04, FN4: a shortcut use with a whitespace-only label '
        'does not fall back to the link text', () {
      final places = placesOf('[k]: .md\n[k][ ]\n[k]\n');

      expect(places, [(target: '.md', line: 3, shown: '.md')]);
    });

    test('f04/us02/fr04/e08, LP1: a link whose escape is not UTF-8 is placed '
        'at its line as written', () {
      final places = linkPlacesOf(
        'x\n\n[x](%DB.md)\n',
        docPath: 'prds/f/us/fr01.md',
        firstLine: 1,
      );

      expect(places, [
        (target: 'prds/f/us/\u{FFFD}.md', line: 3, shown: '%DB.md'),
      ]);
    });
  });
}
