// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';

void main() {
  test('cc-s03/inv3, f04/us04/fr01/e06, review focus 1: a fingerprint ignores trailing blank lines and CRLF', () {
    expect(fingerprintOf(''), 'e3b0c44298fc');
    expect(fingerprintOf(loginScenario2), fingerprintFor(loginScenario2));
    expect(
      fingerprintOf('$loginScenario2\n\n\n'),
      fingerprintFor(loginScenario2),
    );
    expect(
      fingerprintOf(loginScenario2.replaceAll('\n', '\r\n')),
      fingerprintFor(loginScenario2),
    );
    expect(fingerprintOf(loginScenario2), matches(RegExp(r'^[0-9a-f]{12}$')));
  });

  test('cc-s03/inv3: upstream text keeps one final line break, and an all-blank block stays empty', () {
    expect(upstreamText('a\nb'), 'a\nb\n');
    expect(upstreamText('a\nb\n  \n\n'), 'a\nb\n');
    expect(upstreamText('\n \n'), '');
  });

  group('E06: a fingerprint reads the block as format lays it out', () {
    const laid =
        '### Scenario 3 — [happy] Table\n\n| Item | Count |\n| --- | --- |\n'
        '| apple | 2 |\n';
    const padded =
        '### Scenario 3 — [happy] Table\n\n| Item  | Count |\n| ----- | ----- |\n'
        '| apple | 2     |\n';
    const noGap =
        '### Scenario 3 — [happy] Table\n| Item | Count |\n| --- | --- |\n'
        '| apple | 2 |\n';

    test('a padded table fingerprints as the laid-out block does', () {
      expect(fingerprintOf(padded), fingerprintOf(laid));
    });

    test('a dropped heading gap fingerprints as the laid-out block does', () {
      expect(fingerprintOf(noGap), fingerprintOf(laid));
    });

    test('a changed word still changes the fingerprint', () {
      expect(
        fingerprintOf(laid.replaceAll('apple', 'pear')),
        isNot(fingerprintOf(laid)),
      );
    });
  });

  test('E06: a section body fingerprints the same with or without the gap under its heading', () {
    expect(fingerprintOf('Text\n'), fingerprintOf('\nText\n'));
    expect(fingerprintOf('\n\nText\n'), fingerprintOf('Text\n'));
    expect(fingerprintOf('\nText\n'), isNot(fingerprintOf('\nTest\n')));
  });

  test('a laid-out block fingerprints to a pinned literal', () {
    // Hashes the text '### Scenario 3\n\n- **Given** a\n'.
    expect(fingerprintOf('### Scenario 3\n\n- **Given** a\n'), '71d315dbe8d8');
  });

  test(
    'the legacy fingerprint keeps the 1.1.0 recipe when the layout changes',
    () {
      const block = '### Scenario 3 — [happy] Table\n| a  | b |\n';
      expect(
        legacyFingerprintOf(block),
        baseHashOf('### Scenario 3 — [happy] Table\n| a  | b |\n'),
      );
      expect(legacyFingerprintOf(block), isNot(fingerprintOf(block)));
    },
  );
}
