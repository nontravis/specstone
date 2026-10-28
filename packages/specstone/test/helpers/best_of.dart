/// The number of timed runs every NFR timing gate takes the fastest of.
///
/// The owner ruled the method on 2026-10-28 (option A): the best of five runs
/// against the same limit, every run always made and printed, so a shared
/// runner's slow minute cannot fail a gate alone.
const timingRuns = 5;

/// Calls [run] [runs] times and returns the fastest [Duration].
///
/// Every run is made; there is no stop at the first pass. Each run returns its
/// own measured duration (the gates time their CLI call inside `run`). Every
/// run's time is printed in run order as one `diagnostic:` line, so CI output
/// shows all margins under the limit. When a run throws, the times of the runs
/// that finished are still printed before the error is rethrown, so a severe
/// regression that dies mid-run does not take its numbers with it.
Duration bestOf(int runs, Duration Function() run, {required String label}) {
  final durations = <Duration>[];
  void report() {
    if (durations.isEmpty) return;
    // ignore: avoid_print, the gate reports every finished run so the margin under the limit can be read.
    print(
      'diagnostic: $label '
      '${durations.map((d) => d.inMilliseconds).join(', ')} ms',
    );
  }

  try {
    for (var i = 0; i < runs; i++) {
      durations.add(run());
    }
  } catch (_) {
    report();
    rethrow;
  }
  report();
  return durations.reduce((a, b) => a < b ? a : b);
}
