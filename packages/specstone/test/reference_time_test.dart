import 'package:test/test.dart';

import 'helpers/reference_time.dart';

void main() {
  test('the probe does its whole fixed workload', () {
    expect(probeWork(), probeChecksum);
  });

  test('on Linux a bound passes at the limit and fails past it', () {
    const bound = Duration(milliseconds: 500);
    expectWithinBound(bound, bound, onLinux: true);
    expect(
      () => expectWithinBound(
        bound + const Duration(milliseconds: 1),
        bound,
        onLinux: true,
      ),
      throwsA(isA<TestFailure>()),
    );
  });
}
