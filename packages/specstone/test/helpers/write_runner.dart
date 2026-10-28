import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone/src/console.dart';
import 'package:specstone_core/specstone_core.dart';

/// A [Console] with scripted input and terminal facts.
final class FakeConsole implements Console {
  /// Creates a console that reads [input] whole and answers each
  /// [readLine] from [answers] in turn, then with the end of input.
  ///
  /// [onReadLine] runs at the start of each `readLine` with its zero-based
  /// call number.
  new({
    this.input = '',
    this.stdinIsTerminal = false,
    this.stdoutIsTerminal = false,
    this.answers = const [],
    this.onReadLine,
  });

  /// What [readAll] returns.
  final String input;

  @override
  final bool stdinIsTerminal;

  @override
  final bool stdoutIsTerminal;

  /// What [readLine] returns, one entry per call.
  final List<String?> answers;

  /// Runs at the start of each [readLine] with the call number.
  final void Function(int call)? onReadLine;

  var _calls = 0;

  @override
  Future<String> readAll() async => input;

  @override
  String? readLine() {
    final call = _calls++;
    onReadLine?.call(call);
    return call < answers.length ? answers[call] : null;
  }
}

/// Returns a runner on [root] with [console] and the sinks it prints to.
///
/// The runner reads the built-in doc types and no user-level ones.
({SpecstoneCommandRunner runner, StringBuffer out, StringBuffer err})
writeRunner(Directory root, {FakeConsole? console}) {
  final out = StringBuffer();
  final err = StringBuffer();
  final runner = SpecstoneCommandRunner(
    out: out,
    err: err,
    templates: TemplateResolver(),
    workingDirectory: root,
    homeDirectory: null,
    console: console ?? FakeConsole(),
  );
  return (runner: runner, out: out, err: err);
}
