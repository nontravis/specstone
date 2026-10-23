import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/rendering/browser_host.dart';
import 'package:specstone_core/src/rendering/pdf_printer.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:test/test.dart';

const _printFlag = '--print-to-pdf=';
const _fakePdf = '%PDF-1.4 fake';
const _failedMessage = 'the browser stopped before it printed the pdf';

/// What one fake browser run saw.
final class _Run {
  String? executable;
  List<String>? arguments;
  Duration? timeout;
  String? htmlRead;
  Directory? folder;
}

/// How a fake browser behaves once it is started.
typedef _Behavior = Future<int> Function(_Run run, File pdf);

Future<int> _printsPdf(_Run run, File pdf) async {
  pdf.writeAsStringSync(_fakePdf);
  return 0;
}

BrowserHost _hostWith(_Run run, [_Behavior behavior = _printsPdf]) {
  return BrowserHost(
    environment: const {},
    os: HostOs.linux,
    isRunnable: (_) => true,
    runProcess: (executable, arguments, {required timeout}) async {
      run
        ..executable = executable
        ..arguments = arguments
        ..timeout = timeout;
      final htmlFile = File.fromUri(Uri.parse(arguments.last));
      run
        ..folder = htmlFile.parent
        ..htmlRead = htmlFile.readAsStringSync();
      final printArgument = arguments.firstWhere(
        (argument) => argument.startsWith(_printFlag),
      );
      final pdf = File(printArgument.substring(_printFlag.length));
      return behavior(run, pdf);
    },
  );
}

void _ignoreWarning(String warning) {}

/// Leaves a folder in the browser's temp folder that `delete` cannot remove.
///
/// Mode 000 on a non-empty folder makes a recursive delete of its parent
/// fail with a permission error on POSIX hosts.
Future<int> _lockedThen(_Run run, File pdf, int exitCode) async {
  final locked = Directory('${pdf.parent.path}/locked')..createSync();
  File('${locked.path}/inner').writeAsStringSync('x');
  Process.runSync('chmod', ['000', locked.path]);
  addTearDown(() {
    Process.runSync('chmod', ['700', locked.path]);
    if (pdf.parent.existsSync()) pdf.parent.deleteSync(recursive: true);
  });
  if (exitCode == 0) pdf.writeAsStringSync(_fakePdf);
  return exitCode;
}

/// Whether a recursive delete ignores file modes, as it does for root.
final bool _modesAreIgnored =
    !Platform.isWindows &&
    Process.runSync('id', ['-u']).stdout.toString().trim() == '0';

Future<RenderFault> _faultOf(Future<Object?> call) async {
  try {
    await call;
  } on RenderFault catch (fault) {
    return fault;
  }
  fail('printPdf returned instead of throwing a RenderFault');
}

void main() {
  test('f05/us03/fr02: returns the pdf the browser wrote, run with the '
      'planned arguments and the 120 s timeout', () async {
    final run = _Run();
    final warnings = <String>[];

    final bytes = await printPdf(
      '<html>x</html>',
      browser: '/opt/chrome',
      host: _hostWith(run),
      onWarning: warnings.add,
    );

    expect(warnings, isEmpty);
    expect(utf8.decode(bytes), _fakePdf);
    expect(run.executable, '/opt/chrome');
    final folder = run.folder!.path;
    final separator = Platform.pathSeparator;
    expect(run.arguments, [
      '--headless',
      '--disable-gpu',
      '--disable-background-networking',
      '--no-first-run',
      '--no-default-browser-check',
      '--user-data-dir=$folder${separator}profile',
      '--no-pdf-header-footer',
      '--virtual-time-budget=30000',
      '$_printFlag$folder${separator}out.pdf',
      File('$folder${separator}page.html').uri.toString(),
    ]);
    expect(run.htmlRead, '<html>x</html>');
    expect(run.timeout, const Duration(seconds: 120));
    expect(browserTimeout, const Duration(seconds: 120));
  });

  test('f05/us03/fr02/e02, doc_model/s03/inv13: the browser is told not to '
      'use the network in the background', () async {
    final run = _Run();

    await printPdf(
      '<html/>',
      browser: '/opt/chrome',
      host: _hostWith(run),
      onWarning: _ignoreWarning,
    );

    expect(run.arguments, contains('--disable-background-networking'));
  });

  group('f05/us03/fr02/e01: browser_print_failed', () {
    Future<RenderFault> failWith(_Behavior behavior) => _faultOf(
      printPdf(
        '<html/>',
        browser: '/opt/chrome',
        host: _hostWith(_Run(), behavior),
        onWarning: _ignoreWarning,
      ),
    );

    void expectPrintFailed(RenderFault fault) {
      expect(fault.code, RenderFaultCode.browserPrintFailed);
      expect(fault.exitStatus, 70);
      expect(fault.message, _failedMessage);
    }

    test('when the browser exits with a non-zero code', () async {
      expectPrintFailed(await failWith((run, pdf) async => 1));
    });

    test('when the browser exits 0 without writing the pdf', () async {
      expectPrintFailed(await failWith((run, pdf) async => 0));
    });

    test('when the browser exits 0 and leaves an empty pdf', () async {
      expectPrintFailed(
        await failWith((run, pdf) async {
          pdf.writeAsBytesSync(const []);
          return 0;
        }),
      );
    });

    test('when the timeout kill yields -1', () async {
      expectPrintFailed(await failWith((run, pdf) async => -1));
    });

    test('when the program cannot start', () async {
      expectPrintFailed(
        await failWith(
          (run, pdf) => throw const ProcessException('/opt/chrome', []),
        ),
      );
    });
  });

  group('doc_model/s03/inv16: the temp folder is gone afterward', () {
    test('after a successful print', () async {
      final run = _Run();

      await printPdf(
        '<html/>',
        browser: '/opt/chrome',
        host: _hostWith(run),
        onWarning: _ignoreWarning,
      );

      expect(run.folder!.existsSync(), isFalse);
    });

    test('after a failed print', () async {
      final run = _Run();

      await _faultOf(
        printPdf(
          '<html/>',
          browser: '/opt/chrome',
          host: _hostWith(run, (run, pdf) async => 1),
          onWarning: _ignoreWarning,
        ),
      );

      expect(run.folder!.existsSync(), isFalse);
    });

    test('after a timeout kill', () async {
      final run = _Run();

      await _faultOf(
        printPdf(
          '<html/>',
          browser: '/opt/chrome',
          host: _hostWith(run, (run, pdf) async => -1),
          onWarning: _ignoreWarning,
        ),
      );

      expect(run.folder!.existsSync(), isFalse);
    });

    test('after the program cannot start', () async {
      final run = _Run();

      await _faultOf(
        printPdf(
          '<html/>',
          browser: '/opt/chrome',
          host: _hostWith(
            run,
            (run, pdf) => throw const ProcessException('/opt/chrome', []),
          ),
          onWarning: _ignoreWarning,
        ),
      );

      expect(run.folder!.existsSync(), isFalse);
    });
  });

  group('a temp folder that cannot be deleted', () {
    final skip = Platform.isWindows
        ? 'POSIX file modes'
        : _modesAreIgnored
        ? 'root ignores file modes'
        : false;

    test(
      'f05/us03/fr02: still returns the pdf and reports one warning',
      () async {
        final run = _Run();
        final warnings = <String>[];

        final bytes = await printPdf(
          '<html/>',
          browser: '/opt/chrome',
          host: _hostWith(run, (run, pdf) => _lockedThen(run, pdf, 0)),
          onWarning: warnings.add,
        );

        expect(utf8.decode(bytes), _fakePdf);
        expect(warnings, [
          'could not delete the temporary folder ${run.folder!.path}',
        ]);
      },
      skip: skip,
    );

    test(
      'f05/us03/fr02/e01: the print fault is still the one thrown',
      () async {
        final run = _Run();
        final warnings = <String>[];

        final fault = await _faultOf(
          printPdf(
            '<html/>',
            browser: '/opt/chrome',
            host: _hostWith(run, (run, pdf) => _lockedThen(run, pdf, 1)),
            onWarning: warnings.add,
          ),
        );

        expect(fault.code, RenderFaultCode.browserPrintFailed);
        expect(fault.message, _failedMessage);
        expect(warnings, [
          'could not delete the temporary folder ${run.folder!.path}',
        ]);
      },
      skip: skip,
    );
  });
}
