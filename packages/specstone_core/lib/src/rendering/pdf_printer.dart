import 'dart:io';
import 'dart:typed_data';

import 'package:specstone_core/src/rendering/browser_host.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';

/// How long the browser may run before it is killed.
const Duration browserTimeout = Duration(seconds: 120);

/// Lets mermaid finish rendering before the print, in milliseconds.
const _virtualTimeBudgetMs = 30000;

/// Prints [html] to a pdf with the [browser] program and returns the bytes.
///
/// The page and the pdf live in a temp folder that is deleted in every case.
/// Throws a [RenderFault] with `browser_print_failed` when the browser cannot
/// start, outlives [browserTimeout], exits non-zero, or writes no pdf.
Future<Uint8List> printPdf(
  String html, {
  required String browser,
  required BrowserHost host,
}) async {
  final folder = Directory.systemTemp.createTempSync('specstone_pdf_');
  try {
    final page = File('${folder.path}${Platform.pathSeparator}page.html')
      ..writeAsStringSync(html);
    final pdf = File('${folder.path}${Platform.pathSeparator}out.pdf');
    final profile = '${folder.path}${Platform.pathSeparator}profile';
    final int exitCode;
    try {
      exitCode = await host.runProcess(browser, [
        '--headless',
        '--disable-gpu',
        '--disable-background-networking',
        '--no-first-run',
        '--no-default-browser-check',
        '--user-data-dir=$profile',
        '--no-pdf-header-footer',
        '--virtual-time-budget=$_virtualTimeBudgetMs',
        '--print-to-pdf=${pdf.path}',
        page.uri.toString(),
      ], timeout: browserTimeout);
    } on ProcessException {
      throw _printFailed();
    }
    if (exitCode != 0 || !pdf.existsSync()) throw _printFailed();
    final bytes = pdf.readAsBytesSync();
    if (bytes.isEmpty) throw _printFailed();
    return bytes;
  } finally {
    folder.deleteSync(recursive: true);
  }
}

RenderFault _printFailed() => RenderFault(
  RenderFaultCode.browserPrintFailed,
  'the browser stopped before it printed the pdf',
);
