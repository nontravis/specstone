import 'dart:io';

import 'children_cpu_time.dart';

/// What a timing gate measures for a spawned child.
enum TimingMetric { cpu, wall }

/// Returns [TimingMetric.wall] on CI or Windows, else [TimingMetric.cpu].
TimingMetric metricFor({
  required Map<String, String> environment,
  required bool isWindows,
}) => environment.containsKey('CI') || isWindows
    ? TimingMetric.wall
    : TimingMetric.cpu;

final TimingMetric timingMetric = metricFor(
  environment: Platform.environment,
  isWindows: Platform.isWindows,
);

/// A child's result and the time [measureChild] charged to it.
final class MeasuredRun {
  const new(this.result, this.elapsed);

  final ProcessResult result;
  final Duration elapsed;
}

/// Runs [work] and returns the time [timingMetric] picks for this process.
///
/// Valid only while no other isolate or child works in the window.
Duration measureInProcess(void Function() work) {
  switch (timingMetric) {
    case TimingMetric.wall:
      final watch = Stopwatch()..start();
      work();
      return (watch..stop()).elapsed;
    case TimingMetric.cpu:
      final before = selfCpuTime();
      work();
      return selfCpuTime() - before;
  }
}

/// Runs [run] and returns its result with the time [timingMetric] picks.
///
/// [run] must block until the child is reaped, as `Process.runSync` does.
MeasuredRun measureChild(ProcessResult Function() run) {
  switch (timingMetric) {
    case TimingMetric.wall:
      final watch = Stopwatch()..start();
      final result = run();
      return MeasuredRun(result, (watch..stop()).elapsed);
    case TimingMetric.cpu:
      final before = childrenCpuTime();
      final result = run();
      return MeasuredRun(result, childrenCpuTime() - before);
  }
}
