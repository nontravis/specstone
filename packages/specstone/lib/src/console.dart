import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/specstone_core.dart';

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
  /// Creates the console of the process.
  ///
  /// [input] replaces stdin for [readAll] and makes [stdinIsTerminal] false,
  /// since an injected stream is never a terminal. [readLine] and
  /// [stdoutIsTerminal] still read the process's own stdin and stdout.
  new({Stream<List<int>>? input})
    : _input = input ?? stdin,
      _injected = input != null;

  final Stream<List<int>> _input;
  final bool _injected;

  @override
  bool get stdinIsTerminal => !_injected && stdin.hasTerminal;

  @override
  bool get stdoutIsTerminal => stdout.hasTerminal;

  /// Reads stdin to its end as UTF-8 text.
  ///
  /// Throws [IndexFault] `argument_invalid` when the bytes are not UTF-8.
  @override
  Future<String> readAll() async {
    try {
      return await _input.transform(utf8.decoder).join();
    } on FormatException {
      throw IndexFault(
        IndexFaultCode.argumentInvalid,
        'stdin is not UTF-8 text',
      );
    }
  }

  @override
  String? readLine() => stdin.readLineSync();
}
