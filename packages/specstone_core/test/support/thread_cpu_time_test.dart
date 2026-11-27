// D18
import 'dart:io';

import 'package:specstone_test_support/specstone_test_support.dart';
import 'package:test/test.dart';

void main() {
  test('a 300 ms sleep adds under 50 ms', () {
    final before = threadCpuTime();
    sleep(const Duration(milliseconds: 300));

    expect(
      threadCpuTime() - before,
      lessThan(const Duration(milliseconds: 50)),
    );
  });

  test('a busy spin of 200 ms wall adds more than zero and no more than the '
      'wall span plus one tick', () {
    final tick = _firstStep();
    final wall = Stopwatch()..start();
    final before = threadCpuTime();
    while (wall.elapsed < const Duration(milliseconds: 200)) {}
    final spent = threadCpuTime() - before;
    wall.stop();

    expect(spent, greaterThan(Duration.zero));
    expect(spent, lessThanOrEqualTo(wall.elapsed + tick));
  });

  test('readings never decrease', () {
    var previous = threadCpuTime();
    for (var i = 0; i < 10000; i++) {
      final reading = threadCpuTime();
      expect(reading, greaterThanOrEqualTo(previous));
      previous = reading;
    }
  });
}

/// Returns the first change of the thread clock, one tick of it.
Duration _firstStep() {
  final start = threadCpuTime();
  var reading = start;
  while (reading == start) {
    reading = threadCpuTime();
  }
  return reading - start;
}
