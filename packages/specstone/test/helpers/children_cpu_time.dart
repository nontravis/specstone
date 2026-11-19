import 'dart:ffi';

import 'package:ffi/ffi.dart';

const _rusageChildren = -1;
const _restLongCount = 14;

/// The platform's `suseconds_t`: 32-bit on macOS, 64-bit on 64-bit Linux.
///
/// The other ABIs are listed so the file compiles everywhere; `getrusage` is
/// never called on them.
@AbiSpecificIntegerMapping({
  Abi.androidArm: Int32(),
  Abi.androidArm64: Int64(),
  Abi.androidIA32: Int32(),
  Abi.androidX64: Int64(),
  Abi.androidRiscv64: Int64(),
  Abi.fuchsiaArm64: Int64(),
  Abi.fuchsiaRiscv64: Int64(),
  Abi.fuchsiaX64: Int64(),
  Abi.iosArm: Int32(),
  Abi.iosArm64: Int32(),
  Abi.iosX64: Int32(),
  Abi.linuxArm: Int32(),
  Abi.linuxArm64: Int64(),
  Abi.linuxIA32: Int32(),
  Abi.linuxRiscv32: Int32(),
  Abi.linuxRiscv64: Int64(),
  Abi.linuxX64: Int64(),
  Abi.macosArm64: Int32(),
  Abi.macosX64: Int32(),
  Abi.windowsArm64: Int32(),
  Abi.windowsIA32: Int32(),
  Abi.windowsX64: Int32(),
})
final class _Suseconds extends AbiSpecificInteger {
  const new();
}

final class _Timeval extends Struct {
  @Long()
  external int tvSec;

  @_Suseconds()
  external int tvUsec;

  Duration get duration => Duration(seconds: tvSec, microseconds: tvUsec);
}

final class _Rusage extends Struct {
  external _Timeval utime;
  external _Timeval stime;

  @Array(_restLongCount)
  external Array<Long> rest;
}

final int Function(int, Pointer<_Rusage>) _getrusage = DynamicLibrary.process()
    .lookupFunction<
      Int Function(Int, Pointer<_Rusage>),
      int Function(int, Pointer<_Rusage>)
    >('getrusage');

/// Returns the user plus system CPU time of every child this process has
/// waited for.
///
/// A child counts only once it is reaped, so time a synchronous run to
/// completion. Sibling test suites in one VM share the total.
Duration childrenCpuTime() {
  final usage = calloc<_Rusage>();
  try {
    if (_getrusage(_rusageChildren, usage) != 0) {
      throw StateError('getrusage(RUSAGE_CHILDREN) failed');
    }
    return usage.ref.utime.duration + usage.ref.stime.duration;
  } finally {
    calloc.free(usage);
  }
}
