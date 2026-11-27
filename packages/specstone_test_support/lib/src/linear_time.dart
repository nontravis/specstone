import 'dart:math';

import 'package:specstone_test_support/src/thread_cpu_time.dart';
import 'package:test/test.dart';

/// Expects [scan] to take time linear in the length of the body it reads.
///
/// Times one scan of the bodies [bodyOf] builds for a twentieth of [n] and
/// for [n] by [cpuTimeOf], the median of 5 interleaved samples each. A linear
/// scan's time grows as much as the body, a quadratic one's as its square; the
/// bound is the body's growth to the power 1.5, between the two on a log scale.
void expectLinearTime(
  String Function(int n) bodyOf,
  int n,
  void Function(String body) scan,
) {
  final small = bodyOf(n ~/ 20);
  final large = bodyOf(n);
  final span = _sampleSpan();
  final smallRepeats = _repeatsFor(scan, small, span);
  final largeRepeats = _repeatsFor(scan, large, span);
  final smallTimes = <double>[];
  final largeTimes = <double>[];
  for (var sample = 0; sample < _samples; sample++) {
    smallTimes.add(_scanTime(scan, small, smallRepeats));
    largeTimes.add(_scanTime(scan, large, largeRepeats));
  }
  final smallTime = _median(smallTimes);
  final largeTime = _median(largeTimes);
  final bodyGrowth = large.length / small.length;
  final timeGrowth = largeTime / smallTime;

  expect(
    timeGrowth,
    lessThan(pow(bodyGrowth, 1.5)),
    reason:
        'the body grew ${bodyGrowth.toStringAsFixed(1)} times and the time '
        'of one scan ${timeGrowth.toStringAsFixed(1)} times '
        '(${smallTime.round()} µs to ${largeTime.round()} µs)',
  );
}

const _samples = 5;

const _minimumSpan = Duration(milliseconds: 20);

const _ticksPerSpan = 10;

const _stepProbes = 3;

/// Returns the shortest time a sample takes: 20 ms, and 10 clock steps.
Duration _sampleSpan() {
  final ticks = _smallestStep() * _ticksPerSpan;
  return ticks > _minimumSpan ? ticks : _minimumSpan;
}

/// Returns the smallest step of the bound clock seen over a few empty calls.
Duration _smallestStep() =>
    [for (var probe = 0; probe < _stepProbes; probe++) _firstNonzeroSpan()]
        .reduce((a, b) => a < b ? a : b);

Duration _firstNonzeroSpan() {
  var span = Duration.zero;
  while (span == Duration.zero) {
    span = cpuTimeOf(() {});
  }
  return span;
}

/// Returns how many scans of [body] in a row take at least [span].
int _repeatsFor(void Function(String body) scan, String body, Duration span) {
  var repeats = 1;
  while (_timeOf(scan, body, repeats) < span) {
    repeats *= 2;
  }
  return repeats;
}

/// Returns the microseconds one scan of [body] takes, over [repeats] scans.
double _scanTime(void Function(String body) scan, String body, int repeats) =>
    _timeOf(scan, body, repeats).inMicroseconds / repeats;

Duration _timeOf(void Function(String body) scan, String body, int repeats) =>
    cpuTimeOf(() {
      for (var i = 0; i < repeats; i++) {
        scan(body);
      }
    });

double _median(List<double> values) =>
    (values.toList()..sort())[values.length ~/ 2];
