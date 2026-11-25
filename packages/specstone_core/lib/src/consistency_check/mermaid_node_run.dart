import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/mermaid_parser.dart';
import 'package:specstone_core/src/index_query/diagram_parse.dart';

const _defaultTimeout = Duration(seconds: 10);
const _fileNotFoundCode = 2;
const _unreadableOutputReason = 'node wrote output that is not a parse result';

/// One Mermaid block with no stored result, to hand to Node.
final class PendingBlock {
  const new({required this.hash, required this.text});

  /// The content hash of [text].
  final String hash;

  /// The block's text, without its fences.
  final String text;
}

/// What one Node run answered, and why it could not answer the rest.
final class NodeParseOutcome {
  const new({required this.answered, this.skipReason});

  /// The parse result of each answered block, keyed by block hash.
  final Map<String, DiagramParse> answered;

  /// One line saying why Node did not answer every block; null when it did.
  final String? skipReason;
}

/// Parses Mermaid blocks in one `node` child, bounded by a timeout.
final class MermaidNodeRun {
  new({
    Future<Process> Function(List<String> arguments)? start,
    Duration? timeout,
  }) : _start = start ?? _startNode,
       _timeout = timeout ?? defaultTimeout;

  /// The timeout of a runner built with none; tests raise it for a cold host.
  // Mutable so a suite reaches the runners that code paths build for it.
  static Duration defaultTimeout = _defaultTimeout;

  final Future<Process> Function(List<String> arguments) _start;
  final Duration _timeout;

  /// Parses [pending] in one child process; never throws for a Node failure.
  ///
  /// Blocks sharing a hash go in once. A timeout keeps the results read before
  /// the kill; any other failure answers no block. No block starts no process.
  Future<NodeParseOutcome> parse(List<PendingBlock> pending) async {
    final blocks = _distinctByHash(pending);
    if (blocks.isEmpty) return const NodeParseOutcome(answered: {});
    final Process process;
    try {
      process = await _start(['-e', mermaidParseScript]);
    } on ProcessException catch (error) {
      return NodeParseOutcome(
        answered: const {},
        skipReason: _startFailureReason(error),
      );
    }
    final run = await _drive(process, blocks);
    return _outcome(blocks, run);
  }

  Future<_ChildRun> _drive(Process process, List<PendingBlock> blocks) async {
    final lines = <String>[];
    final stdoutReadable = _readLines(process.stdout, lines);
    final stderrLine = _firstLine(process.stderr);
    final fed = _feed(process.stdin, blocks);
    var timedOut = false;
    final exitCode = await process.exitCode.timeout(
      _timeout,
      onTimeout: () {
        timedOut = true;
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    await fed;
    return _ChildRun(
      lines: lines,
      stdoutReadable: await stdoutReadable,
      stderrLine: await stderrLine,
      exitCode: exitCode,
      timedOut: timedOut,
    );
  }

  NodeParseOutcome _outcome(List<PendingBlock> blocks, _ChildRun run) {
    final answered = _decodeLines(blocks, run.lines);
    if (run.timedOut) {
      return NodeParseOutcome(
        answered: answered,
        skipReason: 'node timed out after ${_timeout.inSeconds} s',
      );
    }
    if (run.exitCode != 0) {
      final detail = run.stderrLine.isEmpty ? '' : ': ${run.stderrLine}';
      return NodeParseOutcome(
        answered: const {},
        skipReason: 'node exited with status ${run.exitCode}$detail',
      );
    }
    final complete =
        run.stdoutReadable &&
        answered.length == run.lines.length &&
        answered.length == blocks.length;
    if (!complete) {
      return const NodeParseOutcome(
        answered: {},
        skipReason: _unreadableOutputReason,
      );
    }
    return NodeParseOutcome(answered: answered);
  }
}

/// What the child wrote and how it ended.
final class _ChildRun {
  const new({
    required this.lines,
    required this.stdoutReadable,
    required this.stderrLine,
    required this.exitCode,
    required this.timedOut,
  });

  final List<String> lines;
  final bool stdoutReadable;
  final String stderrLine;
  final int exitCode;
  final bool timedOut;
}

/// Keeps the first block of each hash, in order.
List<PendingBlock> _distinctByHash(List<PendingBlock> blocks) {
  final seen = <String>{};
  return [
    for (final block in blocks)
      if (seen.add(block.hash)) block,
  ];
}

Future<Process> _startNode(List<String> arguments) =>
    Process.start('node', arguments);

String _startFailureReason(ProcessException error) {
  if (error.errorCode == _fileNotFoundCode) return 'node not found';
  return 'node failed to start: ${_oneLine(error.message)}';
}

String _oneLine(String text) => text.trim().split(RegExp(r'\s+')).join(' ');

/// Writes the bundle, a newline, and the blocks as JSON, then closes stdin.
///
/// A child that exits early breaks the pipe; its exit status explains it.
Future<void> _feed(IOSink stdin, List<PendingBlock> blocks) async {
  final payload = jsonEncode([
    for (var i = 0; i < blocks.length; i++) {'i': i, 'text': blocks[i].text},
  ]);
  try {
    stdin
      ..write(patchedMermaidBundle())
      ..write('\n')
      ..write(payload);
    await stdin.close();
  } on IOException {
    return;
  }
}

/// Collects each stdout line as it arrives; false when the bytes are not UTF-8.
Future<bool> _readLines(Stream<List<int>> stdout, List<String> lines) async {
  try {
    await stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach(lines.add);
    return true;
  } on FormatException {
    return false;
  }
}

/// Returns the first non-blank stderr line, reading the rest so the child
/// never blocks on a full pipe.
Future<String> _firstLine(Stream<List<int>> stderr) async {
  var first = '';
  await stderr
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter())
      .forEach((line) {
        if (first.isEmpty) first = line.trim();
      });
  return first;
}

/// Decodes result lines in order, stopping at the first unreadable one.
Map<String, DiagramParse> _decodeLines(
  List<PendingBlock> blocks,
  List<String> lines,
) {
  final answered = <String, DiagramParse>{};
  for (final line in lines) {
    final parse = _decodeLine(blocks, line);
    if (parse == null) break;
    answered[parse.blockHash] = parse;
  }
  return answered;
}

DiagramParse? _decodeLine(List<PendingBlock> blocks, String line) {
  final Object? json;
  try {
    json = jsonDecode(line);
  } on FormatException {
    return null;
  }
  if (json is! Map<String, Object?>) return null;
  final index = json['i'];
  final parses = json['parses'];
  if (index is! int || parses is! bool) return null;
  if (index < 0 || index >= blocks.length) return null;
  final diagram = json['diagram'];
  final message = json['message'];
  final blockLine = json['line'];
  return DiagramParse(
    blockHash: blocks[index].hash,
    diagram: diagram is String ? diagram : null,
    parses: parses,
    message: message is String ? message : null,
    blockLine: blockLine is int ? blockLine : null,
  );
}
