import 'dart:async';
import 'dart:io';
import 'dart:isolate';

/// Opens the path for the duration, signalling `open` then `closed`.
Future<void> holdOpen((String, Duration, SendPort) args) async {
  final (path, hold, port) = args;
  final handle = File(path).openSync();
  port.send('open');
  await Future<void>.delayed(hold);
  handle.closeSync();
  port.send('closed');
}

/// Runs [act] while another isolate holds [path] open for [hold].
///
/// Fails at once with the holder's error when the holder cannot open [path];
/// otherwise waits for the holder to close before it returns.
Future<void> whileHeld(String path, Duration hold, void Function() act) async {
  final signal = ReceivePort();
  final opened = Completer<void>()..future.ignore();
  final closed = Completer<void>()..future.ignore();
  signal.listen((message) {
    if (message is List) {
      final failure = StateError('the holder isolate failed: ${message.first}');
      if (!opened.isCompleted) opened.completeError(failure);
      if (!closed.isCompleted) closed.completeError(failure);
    }
    if (message == 'open') opened.complete();
    if (message == 'closed') closed.complete();
  });
  final holder = await Isolate.spawn(holdOpen, (
    path,
    hold,
    signal.sendPort,
  ), onError: signal.sendPort);
  try {
    await opened.future;
    act();
    await closed.future;
  } finally {
    signal.close();
    holder.kill();
  }
}
