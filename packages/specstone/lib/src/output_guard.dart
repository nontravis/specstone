import 'dart:async';
import 'dart:io';

// MARK: - Constants

/// Exit status when the reader of stdout or stderr has gone: 128 + `SIGPIPE`
/// (13), the status a shell reports for a tool a broken pipe stops.
const int readerGoneExitCode = 141;

/// Exit status when a write to stdout or stderr fails for another reason
/// (`EX_IOERR` from sysexits).
const int outputFailedExitCode = 74;

/// `EPIPE`, the POSIX error of a write to a pipe whose reader has gone.
const int _posixBrokenPipe = 32;

/// `ERROR_BROKEN_PIPE` and `ERROR_NO_DATA`, the Windows errors of a write to
/// a pipe whose reader has gone.
const Set<int> _windowsBrokenPipe = {109, 232};

// MARK: - guardOutput

/// Runs [command], closes [out] and [err], and returns the exit status.
///
/// Watches both sinks from the start, so a failed write never escapes as an
/// unhandled error; a sink that failed drops every later write. A reader that
/// has gone returns [readerGoneExitCode] with nothing printed. Any other
/// failure returns [outputFailedExitCode], and a failed [out] names its OS
/// error on [err].
Future<int> guardOutput(
  Future<int> Function() command, {
  required IOSink out,
  required IOSink err,
}) async {
  final outFailure = _failureOf(out);
  final errFailure = _failureOf(err);
  final status = await command();
  out.close().ignore();
  final outError = await outFailure;
  if (outError != null && !_isReaderGone(outError)) {
    err.writeln('could not write to stdout: ${_reasonOf(outError)}');
  }
  err.close().ignore();
  final errors = [?outError, ?await errFailure];
  if (errors.isEmpty) return status;
  return errors.every(_isReaderGone)
      ? readerGoneExitCode
      : outputFailedExitCode;
}

// MARK: - Failures

/// Completes with the error [sink] fails with, or null once it closes.
///
/// Listens at once: a `done` error with no listener is an unhandled error.
Future<Object?> _failureOf(IOSink sink) =>
    sink.done.then((_) => null, onError: (Object error) => error);

bool _isReaderGone(Object error) {
  if (error is! FileSystemException) return false;
  final code = error.osError?.errorCode;
  return Platform.isWindows
      ? _windowsBrokenPipe.contains(code)
      : code == _posixBrokenPipe;
}

String _reasonOf(Object error) => switch (error) {
  FileSystemException(osError: OSError(:final message)) => message,
  _ => '$error',
};
