import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:specstone/src/output_guard.dart';
import 'package:test/test.dart';

/// The OS error a write meets once the pipe's reader has gone: `EPIPE` on
/// POSIX, `ERROR_NO_DATA` on Windows.
final _readerGone = Platform.isWindows
    ? const OSError('The pipe is being closed.', 232)
    : const OSError('Broken pipe', 32);

const _diskFull = OSError('No space left on device', 28);

/// A stdio stand-in: keeps what it receives, or fails its first write with
/// [failure] the way the process's own stdout does.
final class _Consumer implements StreamConsumer<List<int>> {
  new([this.failure]);

  final OSError? failure;
  final _received = BytesBuilder();
  bool closed = false;

  String get text => utf8.decode(_received.toBytes());

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    final added = Completer<void>();
    late final StreamSubscription<List<int>> subscription;
    subscription = stream.listen((data) {
      final failure = this.failure;
      if (failure == null) {
        _received.add(data);
        return;
      }
      unawaited(subscription.cancel());
      added.completeError(FileSystemException('writeFrom failed', '', failure));
    }, onDone: added.complete);
    return added.future;
  }

  @override
  Future<void> close() async => closed = true;
}

void main() {
  group('guardOutput', () {
    test('returns the command status and closes both sinks when every write '
        'lands', () async {
      final out = _Consumer();
      final err = _Consumer();
      final outSink = IOSink(out);

      final status = await guardOutput(
        () async {
          outSink.write('result\n');
          return 3;
        },
        out: outSink,
        err: IOSink(err),
      );

      expect(status, 3);
      expect(out.text, 'result\n');
      expect(err.text, isEmpty);
      expect([out.closed, err.closed], [isTrue, isTrue]);
    });

    test('returns $readerGoneExitCode and prints nothing when the reader of '
        'stdout has gone, dropping later writes', () async {
      final err = _Consumer();
      final outSink = IOSink(_Consumer(_readerGone));

      final status = await guardOutput(
        () async {
          outSink.write('first\n');
          await Future<void>.delayed(Duration.zero);
          outSink.write('second\n');
          return 0;
        },
        out: outSink,
        err: IOSink(err),
      );

      expect(status, readerGoneExitCode);
      expect(err.text, isEmpty);
    });

    test('returns $readerGoneExitCode when the reader of stderr has '
        'gone', () async {
      final errSink = IOSink(_Consumer(_readerGone));

      final status = await guardOutput(
        () async {
          errSink.writeln('a fault');
          return 64;
        },
        out: IOSink(_Consumer()),
        err: errSink,
      );

      expect(status, readerGoneExitCode);
    });

    test('returns $outputFailedExitCode and names the OS error on stderr when '
        'a stdout write fails another way', () async {
      final err = _Consumer();
      final outSink = IOSink(_Consumer(_diskFull));

      final status = await guardOutput(
        () async {
          outSink.write('result\n');
          return 0;
        },
        out: outSink,
        err: IOSink(err),
      );

      expect(status, outputFailedExitCode);
      expect(err.text, 'could not write to stdout: No space left on device\n');
    });

    test('returns $outputFailedExitCode and prints nothing on stdout when a '
        'stderr write fails another way', () async {
      final out = _Consumer();
      final errSink = IOSink(_Consumer(_diskFull));

      final status = await guardOutput(
        () async {
          errSink.writeln('a warning');
          return 0;
        },
        out: IOSink(out),
        err: errSink,
      );

      expect(status, outputFailedExitCode);
      expect(out.text, isEmpty);
    });
  });
}
