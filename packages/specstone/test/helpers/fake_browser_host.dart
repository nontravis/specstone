import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/specstone_core.dart';

/// The bytes the fake browser writes as its pdf.
const fakePdf = '%PDF-1.4 fake';

const _printFlag = '--print-to-pdf=';

/// A [BrowserHost] that records its calls and prints a fake pdf.
///
/// It runs on Linux with `/bin` as the only `PATH` entry, so a runnable
/// `/bin/google-chrome` is the standard Chrome.
final class FakeBrowserHost {
  new({
    Set<String> runnable = const {},
    Map<String, String> environment = const {},
    this.exitCode = 0,
  }) : _runnable = runnable {
    host = BrowserHost(
      environment: {'PATH': '/bin', ...environment},
      os: HostOs.linux,
      isRunnable: (path) {
        isRunnableCalls++;
        return _runnable.contains(path);
      },
      runProcess: (executable, arguments, {required timeout}) async {
        executables.add(executable);
        final target = arguments.firstWhere(
          (argument) => argument.startsWith(_printFlag),
        );
        File(target.substring(_printFlag.length))
            .writeAsBytesSync(utf8.encode(fakePdf));
        return exitCode;
      },
    );
  }

  /// A host where Chrome at the standard path is runnable.
  new withChrome({Map<String, String> environment = const {}, int exitCode = 0})
    : this(
        runnable: const {chromePath},
        environment: environment,
        exitCode: exitCode,
      );

  /// The standard Chrome install path on the fake Linux host.
  static const chromePath = '/bin/google-chrome';

  final Set<String> _runnable;

  /// What the fake browser exits with after it writes the pdf.
  final int exitCode;

  /// The host to hand to the runner.
  late final BrowserHost host;

  /// How often the lookup asked whether a path is runnable.
  int isRunnableCalls = 0;

  /// The program of each browser run, in order.
  final List<String> executables = [];

  /// Whether the lookup or the print touched the host.
  bool get wasUsed => isRunnableCalls > 0 || executables.isNotEmpty;
}
