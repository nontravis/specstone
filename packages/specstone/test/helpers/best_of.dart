import 'reference_time.dart';
import 'timing_metric.dart';

/// The number of timed runs an NFR timing gate takes the fastest of, unless
/// its NFR names another count.
///
/// The owner ruled the method on 2026-10-28 (option A): the best of five runs
/// against the same limit, every run always made and printed, so a shared
/// runner's slow minute cannot fail a gate alone.
const timingRuns = 5;

/// Calls [run] [runs] times and returns the fastest time in reference-runner
/// time.
///
/// Every run is made and printed in run order on one `diagnostic:` line with
/// this runner's probe, the [scale] factor, and the converted fastest time.
/// When a run throws, the finished runs are still printed before the rethrow.
Duration bestOf(
  int runs,
  Duration Function() run, {
  required String label,
  required TimingMetric metric,
  required ReferenceScale scale,
}) => _fastestOf(runs, run, (durations) {
  final reference = scale.toReference(_fastest(durations));
  _report(
    label,
    metric,
    durations,
    ' · probe ${scale.probe.inMilliseconds} ms'
    ' · factor ${scale.factor.toStringAsFixed(3)}'
    ' · reference-runner ${reference.inMilliseconds} ms',
  );
  return reference;
});

/// Calls [run] [runs] times and returns the fastest time as measured.
///
/// Prints the same `diagnostic:` line as [bestOf] without a conversion; the
/// probe that fixes the [bestOf] conversion is timed this way.
Duration bestOfUnscaled(
  int runs,
  Duration Function() run, {
  required String label,
  required TimingMetric metric,
}) => _fastestOf(runs, run, (durations) {
  _report(label, metric, durations, '');
  return _fastest(durations);
});

Duration _fastestOf(
  int runs,
  Duration Function() run,
  Duration Function(List<Duration> durations) report,
) {
  final durations = <Duration>[];
  try {
    for (var i = 0; i < runs; i++) {
      durations.add(run());
    }
  } catch (_) {
    if (durations.isNotEmpty) report(durations);
    rethrow;
  }
  return report(durations);
}

Duration _fastest(List<Duration> durations) =>
    durations.reduce((a, b) => a < b ? a : b);

void _report(
  String label,
  TimingMetric metric,
  List<Duration> durations,
  String tail,
) {
  // ignore: avoid_print, the gate reports every finished run so the margin under the limit can be read.
  print(
    'diagnostic: $label ${metric.name} '
    '${durations.map((d) => d.inMilliseconds).join(', ')} ms$tail',
  );
}
