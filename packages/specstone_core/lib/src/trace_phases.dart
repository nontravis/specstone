import 'dart:io';

/// Whether `SPECSTONE_TRACE_PHASES=1` asks for `trace` lines on stderr.
///
/// Trace branch only: it times one write per phase on CI and is never merged.
final bool isTracingPhases =
    Platform.environment['SPECSTONE_TRACE_PHASES'] == '1';

/// Runs [body] and, when [isTracingPhases], prints `trace <phase>: <ms> ms`
/// once it returns or throws.
T tracePhase<T>(String phase, T Function() body) {
  if (!isTracingPhases) return body();
  final watch = Stopwatch()..start();
  try {
    return body();
  } finally {
    printTrace(phase, watch);
  }
}

/// Runs [body], one child process of [executable], and prints
/// `trace spawn <executable>: <ms> ms` as [tracePhase] does.
T traceSpawn<T>(String executable, T Function() body) =>
    tracePhase('spawn $executable', body);

/// Prints `trace <phase>: <ms> ms` for [watch]'s elapsed time when
/// [isTracingPhases].
void printTrace(String phase, Stopwatch watch) {
  if (!isTracingPhases) return;
  final ms = (watch.elapsedMicroseconds / 1000).toStringAsFixed(1);
  stderr.writeln('trace $phase: $ms ms');
}
