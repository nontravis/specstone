import 'dart:io';

import 'package:test/test.dart';

import 'best_of.dart';
import 'timing_metric.dart';

const _probeSteps = 6000000;
const _probeKeys = 1024;

/// What [probeWork] returns when it does all of its steps.
const probeChecksum = 43665727;

/// Does a fixed pure-Dart workload and returns its checksum.
///
/// Every step folds into the checksum, so the VM cannot drop any of it.
int probeWork() {
  final table = {for (var k = 0; k < _probeKeys; k++) 'k$k': k * 31};
  final buffer = StringBuffer();
  var checksum = 0;
  for (var i = 0; i < _probeSteps; i++) {
    checksum = (checksum * 33 + (i ^ (i >> 3))) & 0x3fffffff;
    if (i % 64 == 0) buffer.write(i.toRadixString(16));
    checksum ^= table['k${i % _probeKeys}']!;
  }
  return checksum ^ buffer.length;
}

/// Median over three `ubuntu-latest` CI runs of the fastest CPU probe time.
const referenceProbeCpu = Duration(milliseconds: 356);

/// Median over three `ubuntu-latest` CI runs of the fastest wall probe time.
const referenceProbeWall = Duration(milliseconds: 355);

/// How this runner's speed compares with the reference runner's.
final class ReferenceScale {
  const new(this.probe, this.referenceProbe);

  /// Times the probe in [timingMetric], and the wall probe too on Linux.
  ///
  /// The wall probe is printed only; Windows takes no CPU probe.
  static ReferenceScale measure() {
    final probe = probeTime(timingMetric);
    if (Platform.isLinux) probeTime(TimingMetric.wall);
    return ReferenceScale(probe, switch (timingMetric) {
      TimingMetric.cpu => referenceProbeCpu,
      TimingMetric.wall => referenceProbeWall,
    });
  }

  /// The fastest probe time on this runner.
  final Duration probe;

  /// The fastest probe time on the reference runner, in the same metric.
  final Duration referenceProbe;

  /// Below 1 on a runner slower than the reference runner.
  double get factor => referenceProbe.inMicroseconds / probe.inMicroseconds;

  /// Converts a time measured on this runner to reference-runner time.
  Duration toReference(Duration measured) => measured * factor;
}

/// Times [probeWork] in [metric], prints every run, and returns the fastest.
Duration probeTime(TimingMetric metric) => bestOfUnscaled(
  timingRuns,
  () => measureInProcessBy(metric, () {
    final checksum = probeWork();
    if (checksum != probeChecksum) {
      throw StateError('probe checksum $checksum, want $probeChecksum');
    }
  }),
  label: 'probe',
  metric: metric,
);

/// Asserts [time] is within [bound] on Linux, else marks the test skipped.
///
/// Linux is the reference runner's OS; the probe tracks runner speed there,
/// not the CLI's cost on another OS, so no other OS judges a bound.
/// [onLinux] defaults to the running OS.
void expectWithinBound(Duration time, Duration bound, {bool? onLinux}) {
  if (onLinux ?? Platform.isLinux) {
    expect(time, lessThanOrEqualTo(bound));
    return;
  }
  markTestSkipped(
    'the bound is judged on Linux only: reference-runner time '
    '${time.inMilliseconds} ms, bound ${bound.inMilliseconds} ms',
  );
}
