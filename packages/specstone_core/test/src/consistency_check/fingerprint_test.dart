// The expected texts are plan literals kept as written.

import 'package:specstone_core/src/consistency_check/fingerprint.dart';
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
}
