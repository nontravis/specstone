import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../../tool/generate_shipped_packs.dart';
import '../helpers/package_root.dart';

void main() {
  group('readPackSources', () {
    test('f03/us03/fr03/e08: embeds every fixture pack file as its bytes and '
        'skips dot-names', () {
      final files = readPackSources(
        Directory.fromUri(packageRoot().uri.resolve('test/fixtures/packs/')),
      );

      expect(files.keys, [
        'alpha/feature.yaml',
        'alpha/pack.yaml',
        'alpha/refs/crlf.yaml',
        'alpha/refs/handbook.pdf',
      ]);
      expect(files['alpha/refs/handbook.pdf'], [0xff, 0xfe, 0x00, 0x01]);
      expect(files['alpha/refs/crlf.yaml'], utf8.encode('a: 1\r\nb: 2\r\n'));
    });
  });

  group('renderShippedPacks', () {
    test('f03/us03/fr03/e08: a short entry is one line', () {
      final text = renderShippedPacks({
        'a/x.pdf': Uint8List.fromList([0xff, 0, 1]),
      });

      expect(text, contains("  'a/x.pdf': '/wAB',"));
    });

    test('f03/us03/fr03/e08: no files render the empty map', () {
      expect(
        renderShippedPacks({}),
        contains('const Map<String, String> shippedPackFilesBase64 = {};'),
      );
    });

    test('f03/us03/fr03/e08: a long entry wraps in 64-character literals', () {
      final text = renderShippedPacks({
        'alpha/long.yaml': Uint8List.fromList(List<int>.filled(300, 0x61)),
        'alpha/short.yaml': Uint8List.fromList(utf8.encode('a: 1')),
      });
      final lines = const LineSplitter().convert(text);

      final keyIndex = lines.indexOf("  'alpha/long.yaml':");
      expect(keyIndex, greaterThanOrEqualTo(0));
      final literals = <String>[];
      for (final line in lines.skip(keyIndex + 1)) {
        if (!line.startsWith("      '")) break;
        literals.add(line);
      }
      expect(literals, hasLength(7));
      expect(
        literals.sublist(0, 6),
        everyElement(matches(r"^      '[A-Za-z0-9+/=]{64}'$")),
      );
      expect(literals.last, matches(r"^      '[A-Za-z0-9+/=]{16}',$"));
      expect(
        lines,
        contains(
          "  'alpha/short.yaml': '${base64Encode(utf8.encode('a: 1'))}',",
        ),
      );
    });

    test('f03/us03/fr03/e08: a key with a quote, backslash, dollar, or control '
        'character is refused', () {
      for (final key in ["a'b", r'a\b', r'a$b', 'a\nb']) {
        expect(
          () => renderShippedPacks({key: Uint8List(0)}),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains(key),
            ),
          ),
        );
      }
    });

    test('f03/us03/fr03/e08: the rendered text is dart format stable', () {
      final samples = [
        renderShippedPacks({}),
        renderShippedPacks({
          'alpha/long.yaml': Uint8List.fromList(List<int>.filled(300, 0x61)),
          'alpha/short.yaml': Uint8List.fromList(utf8.encode('a: 1')),
        }),
      ];
      for (final (index, text) in samples.indexed) {
        final out = File(
          '${Directory.systemTemp.path}/specstone_render_$index.dart',
        );
        addTearDown(out.deleteSync);
        out.writeAsStringSync(text);
        final result = Process.runSync(Platform.resolvedExecutable, [
          'format',
          '--output=none',
          '--set-exit-if-changed',
          out.path,
        ]);

        expect(result.exitCode, 0, reason: text);
      }
    });
  });

  group('main output', () {
    test('f03/us03/fr03/e08: the committed constants match packs/', () {
      final root = packageRoot();
      final packs = Directory.fromUri(root.uri.resolve('packs/'));
      final committed = File.fromUri(
        root.uri.resolve('lib/src/templates/shipped_packs.g.dart'),
      );

      expect(
        committed.readAsStringSync(),
        renderShippedPacks(readPackSources(packs)),
      );
    });
  });
}
