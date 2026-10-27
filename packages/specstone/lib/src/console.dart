import 'dart:convert';
import 'dart:io';

/// The terminal facts and input a write command reads.
///
/// Tests replace it; [SystemConsole] is the process's own.
abstract interface class Console {
  /// Whether stdin is an interactive terminal.
  bool get stdinIsTerminal;

  /// Whether stdout is an interactive terminal.
  bool get stdoutIsTerminal;

  /// Reads stdin to its end as UTF-8 text.
  Future<String> readAll();

  /// Reads one line from stdin, or null at the end of input.
  String? readLine();
}

/// The [Console] of the running process.
final class SystemConsole implements Console {
  @override
  bool get stdinIsTerminal => stdin.hasTerminal;

  @override
  bool get stdoutIsTerminal => stdout.hasTerminal;

  @override
  Future<String> readAll() => stdin.transform(utf8.decoder).join();

  @override
  String? readLine() => stdin.readLineSync();
}
