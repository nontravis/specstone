import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Returns the CPU time the calling thread has used, user and kernel.
///
/// A reading is valid only across one synchronous span: after an `await` the
/// isolate may resume on another thread.
Duration threadCpuTime() =>
    Platform.isWindows ? _windowsThreadTime() : _posixThreadTime();

/// Returns the time one synchronous call of [body] takes by the bound clock.
///
/// The bound clock is [threadCpuTime] on Linux and macOS and the wall clock
/// on Windows.
Duration cpuTimeOf(void Function() body) {
  if (Platform.isWindows) {
    // WORKAROUND: GetThreadTimes is unproven on windows-latest; remove when the
    // release CI runs thread_cpu_time_test.dart green on Windows.
    final wall = Stopwatch()..start();
    body();
    return wall.elapsed;
  }
  final start = threadCpuTime();
  body();
  return threadCpuTime() - start;
}

/// `CLOCK_THREAD_CPUTIME_ID` in Linux's `<time.h>`.
const _linuxThreadClock = 3;

/// `CLOCK_THREAD_CPUTIME_ID` in macOS's `<time.h>`.
const _macosThreadClock = 16;

const _nanosecondsPerMicrosecond = 1000;

/// `FILETIME` counts 100-ns units.
const _fileTimeUnitsPerMicrosecond = 10;

final class _Timespec extends Struct {
  @Long()
  external int seconds;

  @Long()
  external int nanoseconds;
}

final class _FileTime extends Struct {
  @Uint32()
  external int low;

  @Uint32()
  external int high;

  int get units => high << 32 | low;
}

final int Function(int, Pointer<_Timespec>) _clockGettime =
    DynamicLibrary.process().lookupFunction<
      Int Function(Int, Pointer<_Timespec>),
      int Function(int, Pointer<_Timespec>)
    >('clock_gettime');

final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

final Pointer<Void> Function() _getCurrentThread = _kernel32
    .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
      'GetCurrentThread',
    );

typedef _GetThreadTimesNative = Int32 Function(
  Pointer<Void> thread,
  Pointer<_FileTime> creation,
  Pointer<_FileTime> exit,
  Pointer<_FileTime> kernel,
  Pointer<_FileTime> user,
);

typedef _GetThreadTimes = int Function(
  Pointer<Void> thread,
  Pointer<_FileTime> creation,
  Pointer<_FileTime> exit,
  Pointer<_FileTime> kernel,
  Pointer<_FileTime> user,
);

final _GetThreadTimes _getThreadTimes = _kernel32
    .lookupFunction<_GetThreadTimesNative, _GetThreadTimes>('GetThreadTimes');

Duration _posixThreadTime() {
  final clock = Platform.isMacOS ? _macosThreadClock : _linuxThreadClock;
  final time = calloc<_Timespec>();
  try {
    if (_clockGettime(clock, time) != 0) {
      throw StateError('clock_gettime($clock) failed');
    }
    return Duration(
      seconds: time.ref.seconds,
      microseconds: time.ref.nanoseconds ~/ _nanosecondsPerMicrosecond,
    );
  } finally {
    calloc.free(time);
  }
}

Duration _windowsThreadTime() {
  final times = calloc<_FileTime>(4);
  try {
    final kernel = times + 2;
    final user = times + 3;
    if (_getThreadTimes(_getCurrentThread(), times, times + 1, kernel, user) ==
        0) {
      throw StateError('GetThreadTimes failed');
    }
    return Duration(
      microseconds:
          (kernel.ref.units + user.ref.units) ~/ _fileTimeUnitsPerMicrosecond,
    );
  } finally {
    calloc.free(times);
  }
}
