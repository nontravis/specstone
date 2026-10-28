/// The number of timed runs every NFR timing gate takes the fastest of.
///
/// The owner ruled the method on 2026-10-28 (option A): the best of five runs
/// against the same limit, every run always made and printed, so a shared
/// runner's slow minute cannot fail a gate alone.
const timingRuns = 5;

/// Calls [run] [runs] times and returns the fastest [Duration].
///
/// Every run is made and timed; there is no stop at the first pass. Each run's
/// time is printed in run order as one `diagnostic:` line, so CI output shows
/// all margins under the limit.
Duration bestOf(int runs, Duration Function() run, {required String label}) {
  final durations = [for (var i = 0; i < runs; i++) run()];
  // ignore: avoid_print, the gate reports every run so the margin under the limit can be read.
  print(
    'diagnostic: $label '
    '${durations.map((d) => d.inMilliseconds).join(', ')} ms',
  );
  return durations.reduce((a, b) => a < b ? a : b);
}
