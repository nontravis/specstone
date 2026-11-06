import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/doc_model/whatwg_url.dart';
import 'package:test/test.dart';

import '../../helpers/package_root.dart';

void main() {
  group('web-platform-tests urltestdata.json with a file: base', () {
    final entries = _fixtureEntries();

    test('holds the 590 entries README.md counts, 180 of them failures', () {
      final failures = entries.where((entry) => entry.failure);

      expect(entries, hasLength(590));
      expect(failures, hasLength(180));
    });

    for (final (index, entry) in entries.indexed) {
      final outcome = entry.failure ? 'fails' : 'reads';
      test('$index: ${jsonEncode(entry.input)} $outcome', () {
        expect(whatwgParseFails(entry.input), entry.failure);
      });
    }
  });

  group('doc_model RULE-11: the parser runs with a file: base', () {
    test('1:x.md reads: a digit opens no scheme, so it is a path', () {
      expect(whatwgParseFails('1:x.md'), isFalse);
    });

    test(':x.md reads: an empty scheme is no scheme, so it is a path', () {
      expect(whatwgParseFails(':x.md'), isFalse);
    });

    test('http:// fails: a special URL needs a host', () {
      expect(whatwgParseFails('http://'), isTrue);
    });

    test('http://h:99999/ fails: the port is over 65535', () {
      expect(whatwgParseFails('http://h:99999/'), isTrue);
    });

    test('http://h:65535/ reads and http://h:65536/ fails: 65535 is the '
        'highest port', () {
      expect(whatwgParseFails('http://h:65535/'), isFalse);
      expect(whatwgParseFails('http://h:65536/'), isTrue);
    });

    test('https://exa mple.com/x.md fails: a space is a forbidden host '
        'code point', () {
      expect(whatwgParseFails('https://exa mple.com/x.md'), isTrue);
    });
  });

  group('consistency_check/find_broken_pointers/resolve_doc_links E21', () {
    test('http://h:abc/x.md fails: the port is not digits', () {
      expect(whatwgParseFails('http://h:abc/x.md'), isTrue);
    });

    test('a%zz.md reads: a % without two hex digits stays as written', () {
      expect(whatwgParseFails('a%zz.md'), isFalse);
    });
  });

  group('doc_model RULE-11: UTS46 domain-to-ASCII does not run', () {
    for (final input in [
      'http://exämple.com/x.md',
      'http://日本.jp/',
      'http://xn--/',
      'http://xn--zz.example/',
    ]) {
      test('$input reads: its host holds a non-ASCII code point or an xn-- '
          'label', () {
        expect(whatwgParseFails(input), isFalse);
      });
    }

    test('http://ex ämple.com/ reads: a non-ASCII host skips the forbidden '
        'code point check', () {
      expect(whatwgParseFails('http://ex ämple.com/'), isFalse);
    });

    test('a soft hyphen before 1.2.3.4 reads: a non-ASCII host skips the '
        'IPv4 parser', () {
      expect(whatwgParseFails('http://${_softHyphen}1.2.3.4/'), isFalse);
    });

    test('http://%C2%AD1.2.3.4/ reads: the host is non-ASCII once '
        'percent-decoded', () {
      expect(whatwgParseFails('http://%C2%AD1.2.3.4/'), isFalse);
    });

    test('http://%EF%BB%BF%3C/ reads: a decoded leading U+FEFF makes the '
        'host non-ASCII', () {
      expect(whatwgParseFails('http://%EF%BB%BF%3C/'), isFalse);
    });

    test('a < before a combining overlay reads: a non-ASCII host skips the '
        'forbidden code point check', () {
      expect(whatwgParseFails('http://a<$_combiningOverlay.com/'), isFalse);
    });

    test('http://exämple.com:99999/ fails: the port is over 65535', () {
      expect(whatwgParseFails('http://exämple.com:99999/'), isTrue);
    });
  });
}

final _softHyphen = String.fromCharCode(0xAD);
final _combiningOverlay = String.fromCharCode(0x338);

typedef _Entry = ({String input, bool failure});

List<_Entry> _fixtureEntries() {
  final file = File.fromUri(
    packageRoot().uri.resolve('test/fixtures/whatwg_url/urltestdata.json'),
  );
  final entries = jsonDecode(file.readAsStringSync()) as List<Object?>;
  return [
    for (final entry in entries)
      switch (entry) {
        {'input': final String input, 'failure': final bool failure} => (
          input: input,
          failure: failure,
        ),
        _ => throw FormatException('not a fixture entry: $entry'),
      },
  ];
}
