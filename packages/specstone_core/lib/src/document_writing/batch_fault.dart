import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/fault.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';

/// One refused block or refused line of a `set --batch` file.
final class BatchEntry {
  const new({
    required this.code,
    required this.message,
    required this.file,
    this.key,
    this.line,
    this.current,
  });

  /// Returns the entry of a block that raised [fault].
  ///
  /// `code` and `message` are the fault's own, and `current` is a
  /// [WriteFault]'s, so a stale block hands back its text.
  factory fromFault(
    SpecstoneFault fault, {
    required String file,
    required String key,
  }) {
    final error = fault.toJson()['error'];
    final (code, message) = switch (error) {
      {'code': final String code, 'message': final String message} => (
        code,
        message,
      ),
      _ => throw StateError('a fault envelope holds a code and a message'),
    };
    return BatchEntry(
      code: code,
      message: message,
      file: file,
      key: key,
      current: fault is WriteFault ? fault.current : null,
    );
  }

  /// The snake_case code of the fault.
  final String code;

  /// Plain human text with no location prefix.
  final String message;

  /// The DocPath of a refused block, or the `--batch` path of a refused line.
  final String file;

  /// The section key, `_lead`, or `doc` of a refused block; null for a line.
  final String? key;

  /// The line number in the `--batch` file of a refused line; null for a block.
  final int? line;

  /// The current text and base of a stale block.
  final CurrentTarget? current;

  /// Returns `<file>[:<line>][: <key>]: <message>`.
  String toText() {
    final located = line == null ? file : '$file:$line';
    return key == null ? '$located: $message' : '$located: $key: $message';
  }

  /// Returns the entry's keys: `code`, `message`, `file`, and each of `key`,
  /// `line`, and `current` that applies.
  Map<String, Object> toJson() => {
    'code': code,
    'message': message,
    'file': file,
    'key': ?key,
    'line': ?line,
    if (current case final current?)
      'current': {'text': current.text, 'base': current.base},
  };
}

/// The one fault a refused `set --batch` raises.
///
/// A file-level fault names the `--batch` file alone; any other holds every
/// refused block and line in file order.
final class BatchFault implements SpecstoneFault {
  /// Returns the fault of a batch whose [entries], at least one, were refused.
  new(this.entries)
    : isFileLevel = false,
      assert(entries.isNotEmpty, 'a refused batch names at least one entry');

  /// Returns the fault of a batch file refused as a whole, naming [path].
  new fileLevel(String path, String message)
    : entries = [
        BatchEntry(
          code: IndexFaultCode.argumentInvalid.wire,
          message: message,
          file: path,
        ),
      ],
      isFileLevel = true;

  /// The refused blocks and lines in file order; a file-level fault holds one.
  final List<BatchEntry> entries;

  /// Whether the fault refuses the file alone, naming no block or line.
  final bool isFileLevel;

  /// 75 when every entry is a stale block, which a retry clears, else 64.
  @override
  int get exitStatus =>
      !isFileLevel &&
          entries.every(
            (entry) => entry.code == WriteFaultCode.baseMismatch.wire,
          )
      ? WriteFaultCode.baseMismatch.exitStatus
      : IndexFaultCode.argumentInvalid.exitStatus;

  /// Returns the envelope `{'error': {...}}`.
  ///
  /// `code`, `message`, and the location keys are the first entry's;
  /// `blocks` holds every entry unless the fault is file-level.
  @override
  Map<String, Object> toJson() {
    final first = entries.first;
    return {
      'error': {
        'code': first.code,
        'message': first.message,
        'file': first.file,
        'key': ?first.key,
        'line': ?first.line,
        if (!isFileLevel) 'blocks': [for (final e in entries) e.toJson()],
      },
    };
  }

  /// Returns one fault line per entry, in file order.
  @override
  String toText() => entries.map((entry) => entry.toText()).join('\n');

  @override
  String toString() => toText();
}
