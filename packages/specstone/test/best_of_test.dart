import 'dart:async';

import 'package:test/test.dart';

import 'helpers/best_of.dart';

void main() {
  test('NFR-P01, NFR-P02, NFR-P03, FN1: bestOf makes every run, prints each '
      'time, and returns the fastest', () {
    final times = [
      const Duration(milliseconds: 1200),
      const Duration(milliseconds: 400),
      const Duration(milliseconds: 900),
      const Duration(milliseconds: 700),
      const Duration(milliseconds: 1100),
    ];
    var calls = 0;
    Duration run() => times[calls++];
    final lines = <String>[];
    final best = runZoned(
      () => bestOf(5, run, label: 'full index runs'),
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) {
          lines.add(line);
        },
      ),
    );
    expect(calls, 5);
    expect(best, const Duration(milliseconds: 400));
    expect(lines, ['diagnostic: full index runs 1200, 400, 900, 700, 1100 ms']);
  });

  test('NFR-P01, NFR-P02, NFR-P03, FN1: bestOf prints the finished runs '
      'when a run throws', () async {
    const times = [Duration(milliseconds: 1200), Duration(milliseconds: 400)];
    var calls = 0;
    Duration run() => calls < times.length
        ? times[calls++]
        : throw StateError('run ${calls + 1} died');
    final lines = <String>[];

    await expectLater(
      () => runZoned(
        () => bestOf(3, run, label: 'full index runs'),
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) {
            lines.add(line);
          },
        ),
      ),
      throwsStateError,
    );

    expect(lines, ['diagnostic: full index runs 1200, 400 ms']);
  });
}
