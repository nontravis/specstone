import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/task_ref.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/fault.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/sync_prefill.dart'
    show syncVerdictMarker;

const _byteOrderMark = '\uFEFF';
const _addSign = '+';
const _removeSign = '-';
final _blankLine = RegExp(r'^[ \t]*$');
final _fingerprint = RegExp(r'^[0-9a-f]{12}$');

/// `<doc> <entry> <last part>`: the form of a fingerprinted and a `repoint`
/// line after its kind.
final _docEntryLast = RegExp(r'^(\S+) (\S(?:.*\S)?) (\S+)$');
final _mismatch = RegExp(r'^(\S+) (\S(?:.*?\S)?): (\S.*)$');
final _removeTask = RegExp(r'^(\S+) (\S+) (\S.*)$');
final _testFile = RegExp(r'^([+-])(\S+)$');

const _forms = {
  '?': '? <doc> <entry> <fingerprint>',
  'match': 'match <doc> <entry> <fingerprint>',
  'planned': 'planned <doc> <entry> <fingerprint>',
  'mismatch': 'mismatch <doc> <entry>: <point>',
  'repoint': 'repoint <doc> <entry> <new path>[:<new symbol>]',
  'row':
      'row <record> <item>[ <edge case>]: <sign><literal>[ <sign><literal>]…',
  'tests': 'tests <record> <item>: <sign><test file>',
  'remove-task': 'remove-task <task> <doc> <entry>',
};

/// One line of a sync file's verdict part, read as one kind.
sealed class SyncLine {
  const new(this.lineNumber);

  /// The 1-based line number in the file, the part above the marking line
  /// counted.
  final int lineNumber;
}

/// A verdict line: a judgment, or the lack of one, on one entry of one doc.
sealed class VerdictLine extends SyncLine {
  const new({required int lineNumber, required this.doc, required this.entry})
    : super(lineNumber);

  /// The doc address of the line.
  final String doc;

  /// The entry as its doc holds it, before any fingerprint.
  final String entry;
}

/// A verdict line that ends with the 12-hex fingerprint it judges.
sealed class FingerprintedLine extends VerdictLine {
  const new({
    required super.lineNumber,
    required super.doc,
    required super.entry,
    required this.fingerprint,
  });

  /// The 12 lowercase hex characters the verdict is about.
  final String fingerprint;
}

/// A `?` line: no verdict yet.
final class UnjudgedLine extends FingerprintedLine {
  const new({
    required super.lineNumber,
    required super.doc,
    required super.entry,
    required super.fingerprint,
  });
}

/// A `match` line: the code still matches the entry.
final class MatchLine extends FingerprintedLine {
  const new({
    required super.lineNumber,
    required super.doc,
    required super.entry,
    required super.fingerprint,
  });
}

/// A `planned` line: the entry stays planned at the fingerprint.
final class PlannedLine extends FingerprintedLine {
  const new({
    required super.lineNumber,
    required super.doc,
    required super.entry,
    required super.fingerprint,
  });
}

/// A `mismatch` line: one point where the code differs from the entry.
final class MismatchLine extends VerdictLine {
  const new({
    required super.lineNumber,
    required super.doc,
    required super.entry,
    required this.point,
  });

  /// The point listed under `Mismatches:`.
  final String point;
}

/// A `repoint` line: a code path, `covers`, or `tests` entry moves.
final class RepointLine extends SyncLine {
  const new({
    required int lineNumber,
    required this.doc,
    required this.entry,
    required this.newPath,
  }) : super(lineNumber);

  /// The doc address of the line.
  final String doc;

  /// The entry as its doc holds it.
  final String entry;

  /// The path the entry's path becomes, with `:<symbol>` after it when the
  /// entry's symbol changes too.
  final String newPath;
}

/// A `row` line: literals added to or removed from a matrix row.
final class RowLine extends SyncLine {
  const new({
    required int lineNumber,
    required this.record,
    required this.item,
    required this.edgeCase,
    required this.added,
    required this.removed,
  }) : super(lineNumber);

  /// The record address of the line.
  final String record;

  /// The story or FR the row maps.
  final String item;

  /// The edge case of a per-edge-case row; null for a per-FR row.
  final String? edgeCase;

  /// The `+` literals in line order.
  final List<String> added;

  /// The `-` literals in line order.
  final List<String> removed;
}

/// A `tests` line: a test file added to or removed from a record's `tests`.
final class TestsLine extends SyncLine {
  const new({
    required int lineNumber,
    required this.record,
    required this.item,
    required this.testFile,
    required this.adds,
  }) : super(lineNumber);

  /// The record address of the line.
  final String record;

  /// The story or FR the test file covers.
  final String item;

  /// The test file path.
  final String testFile;

  /// Whether the sign is `+`; `-` removes the line.
  final bool adds;
}

/// A `remove-task` line: a closed task's refs go.
final class RemoveTaskLine extends SyncLine {
  const new({
    required int lineNumber,
    required this.task,
    required this.doc,
    required this.entry,
  }) : super(lineNumber);

  /// The task id.
  final String task;

  /// The doc of the link whose commit closed the task.
  final String doc;

  /// The entry of that link.
  final String entry;
}

/// The lines of a sync file's verdict part, in file order.
final class ParsedSync {
  const new({required this.path, required this.lines});

  /// The `--sync` path as given.
  final String path;

  /// Every non-blank line of the verdict part.
  final List<SyncLine> lines;
}

/// One refused line of a `set --sync` file.
final class SyncRefusal {
  const new({
    required this.line,
    required this.code,
    required this.exitStatus,
    required this.message,
  });

  /// Returns the `argument_invalid` refusal of line [line].
  new invalid(int line, String message)
    : this(
        line: line,
        code: IndexFaultCode.argumentInvalid.wire,
        exitStatus: IndexFaultCode.argumentInvalid.exitStatus,
        message: message,
      );

  /// The 1-based line number in the `--sync` file.
  final int line;

  /// The snake_case catalog code.
  final String code;

  /// The process exit status of [code].
  final int exitStatus;

  /// Plain human text with no location prefix.
  final String message;
}

/// The one fault a refused `set --sync` raises, holding every refused line.
final class SyncFault implements SpecstoneFault {
  /// Returns the fault of the file at [path] whose [refusals], at least one,
  /// were refused.
  new(this.path, this.refusals)
    : assert(refusals.isNotEmpty, 'a refused sync names at least one line');

  static final int _clientStatus = IndexFaultCode.argumentInvalid.exitStatus;
  static final int _conflictStatus = WriteFaultCode.stampStale.exitStatus;

  /// The `--sync` path as given.
  final String path;

  /// The refused lines in file order.
  final List<SyncRefusal> refusals;

  /// 64 when any refusal exits 64, else 75.
  @override
  int get exitStatus =>
      refusals.any((refusal) => refusal.exitStatus == _clientStatus)
      ? _clientStatus
      : _conflictStatus;

  /// Returns the envelope `{'error': {...}}`.
  ///
  /// The envelope's own keys are the first refusal's `code`, `message`,
  /// `file`, and `line`; `lines` holds one such entry per refusal.
  @override
  Map<String, Object> toJson() => {
    'error': {
      ..._entryOf(refusals.first),
      'lines': refusals.map(_entryOf).toList(),
    },
  };

  Map<String, Object> _entryOf(SyncRefusal refusal) => {
    'code': refusal.code,
    'message': refusal.message,
    'file': path,
    'line': refusal.line,
  };

  /// Returns one `<path>:<line>: <code>: <message>` line per refusal.
  @override
  String toText() => [
    for (final SyncRefusal(:line, :code, :message) in refusals)
      '$path:$line: $code: $message',
  ].join('\n');

  @override
  String toString() => toText();
}

/// Returns the lines of the verdict part of [text], the sync file at [path]:
/// every line after the last `==> verdicts <==` line, or the whole file, less
/// a BOM, CRLF ends, and blank lines. Throws a [SyncFault] of
/// `argument_invalid` refusals: one per malformed line, and one per `match`
/// or `planned` line beside another verdict line of its entry.
ParsedSync parseSyncFile(String path, String text) {
  final lines = _linesOf(text);
  final marker = lines.lastIndexWhere(
    (line) => line.trimRight() == syncVerdictMarker,
  );
  final parsed = <SyncLine>[];
  final refusals = <SyncRefusal>[];
  for (var i = marker + 1; i < lines.length; i++) {
    if (_blankLine.hasMatch(lines[i])) continue;
    try {
      parsed.add(_readLine(i + 1, lines[i].trimRight()));
    } on _Malformed catch (malformed) {
      refusals.add(SyncRefusal.invalid(i + 1, malformed.message));
    }
  }
  refusals
    ..addAll(_doubleVerdicts(parsed))
    ..sort((a, b) => a.line.compareTo(b.line));
  if (refusals.isNotEmpty) throw SyncFault(path, refusals);
  return ParsedSync(path: path, lines: parsed);
}

List<String> _linesOf(String text) {
  final withoutMark = text.startsWith(_byteOrderMark)
      ? text.substring(_byteOrderMark.length)
      : text;
  return withoutMark.replaceAll('\r\n', '\n').split('\n');
}

/// Reads [line], numbered [number], as one kind.
SyncLine _readLine(int number, String line) {
  final space = line.indexOf(' ');
  final kind = space < 0 ? line : line.substring(0, space);
  final rest = space < 0 ? '' : line.substring(space + 1);
  final form = _forms[kind];
  if (form == null) {
    throw _Malformed(
      'the line reads as no kind; it starts with one of '
      '${_forms.keys.join(', ')}',
    );
  }
  final read = switch (kind) {
    '?' || 'match' || 'planned' => _readFingerprinted(number, kind, rest),
    'mismatch' => _readMismatch(number, rest),
    'repoint' => _readRepoint(number, rest),
    'row' => _readRow(number, rest),
    'tests' => _readTests(number, rest),
    _ => _readRemoveTask(number, rest),
  };
  return read ?? (throw _Malformed('$kind line must read: $form'));
}

SyncLine? _readFingerprinted(int number, String kind, String rest) {
  final match = _docEntryLast.firstMatch(rest);
  if (match == null || !_fingerprint.hasMatch(match[3]!)) return null;
  final (doc, entry, fingerprint) = (match[1]!, match[2]!, match[3]!);
  return switch (kind) {
    '?' => UnjudgedLine(
      lineNumber: number,
      doc: doc,
      entry: entry,
      fingerprint: fingerprint,
    ),
    'match' => MatchLine(
      lineNumber: number,
      doc: doc,
      entry: entry,
      fingerprint: fingerprint,
    ),
    _ => PlannedLine(
      lineNumber: number,
      doc: doc,
      entry: entry,
      fingerprint: fingerprint,
    ),
  };
}

SyncLine? _readMismatch(int number, String rest) {
  final match = _mismatch.firstMatch(rest);
  if (match == null) return null;
  return MismatchLine(
    lineNumber: number,
    doc: match[1]!,
    entry: match[2]!,
    point: match[3]!,
  );
}

SyncLine? _readRepoint(int number, String rest) {
  final match = _docEntryLast.firstMatch(rest);
  if (match == null) return null;
  return RepointLine(
    lineNumber: number,
    doc: match[1]!,
    entry: match[2]!,
    newPath: match[3]!,
  );
}

SyncLine? _readRemoveTask(int number, String rest) {
  final match = _removeTask.firstMatch(rest);
  if (match == null) return null;
  if (!TaskRef.isTaskId(match[1]!)) {
    throw _Malformed(
      'remove-task takes a task id that holds no ":"; got "${match[1]}"',
    );
  }
  return RemoveTaskLine(
    lineNumber: number,
    task: match[1]!,
    doc: match[2]!,
    entry: match[3]!,
  );
}

SyncLine? _readTests(int number, String rest) {
  final split = rest.indexOf(': ');
  if (split < 0) return null;
  final head = rest.substring(0, split).split(' ');
  final file = _testFile.firstMatch(rest.substring(split + 2));
  if (head.length != 2 || head.contains('') || file == null) return null;
  return TestsLine(
    lineNumber: number,
    record: head[0],
    item: head[1],
    testFile: file[2]!,
    adds: file[1] == _addSign,
  );
}

SyncLine? _readRow(int number, String rest) {
  final split = rest.indexOf(': ');
  if (split < 0) return null;
  final head = rest.substring(0, split).split(' ');
  if (head.length < 2 || head.length > 3 || head.contains('')) return null;
  final literals = _signedLiteralsOf(rest.substring(split + 2));
  if (literals == null || literals.isEmpty) return null;
  return RowLine(
    lineNumber: number,
    record: head[0],
    item: head[1],
    edgeCase: head.length == 3 ? head[2] : null,
    added: [
      for (final literal in literals)
        if (literal.isAdded) literal.text,
    ],
    removed: [
      for (final literal in literals)
        if (!literal.isAdded) literal.text,
    ],
  );
}

/// Returns the `<sign><code span>` literals of [tail], one space apart, each
/// read as a matrix row reads a code span; null when [tail] breaks that form.
List<_SignedLiteral>? _signedLiteralsOf(String tail) {
  final spans = {for (final span in codeSpansOf(tail)) span.start: span};
  final literals = <_SignedLiteral>[];
  var at = 0;
  while (at < tail.length) {
    final sign = tail[at];
    final span = spans[at + 1];
    if ((sign != _addSign && sign != _removeSign) || span == null) return null;
    final content = tail.substring(
      span.start + span.ticks,
      span.end - span.ticks,
    );
    literals.add(
      _SignedLiteral(
        isAdded: sign == _addSign,
        text: codeSpanContentOf(content),
      ),
    );
    at = span.end;
    if (at == tail.length) break;
    if (tail[at] != ' ') return null;
    at++;
  }
  return literals;
}

/// Returns a refusal for each `match` or `planned` line that shares its
/// entry with an earlier verdict line, and for each verdict line that shares
/// it with an earlier `match` or `planned` line, naming the first such line.
List<SyncRefusal> _doubleVerdicts(List<SyncLine> lines) {
  final seen = <String, List<VerdictLine>>{};
  final refusals = <SyncRefusal>[];
  for (final line in lines.whereType<VerdictLine>()) {
    final earlier = seen.putIfAbsent(
      '${line.doc}\u0000${line.entry}',
      () => [],
    );
    final clash = earlier
        .where((other) => _stamps(line) || _stamps(other))
        .firstOrNull;
    if (clash != null) {
      refusals.add(
        SyncRefusal.invalid(
          line.lineNumber,
          '${line.entry} already holds the verdict of line '
          '${clash.lineNumber}; a match or planned line stands alone',
        ),
      );
    }
    earlier.add(line);
  }
  return refusals;
}

bool _stamps(VerdictLine line) => line is MatchLine || line is PlannedLine;

/// One literal of a `row` line and its sign.
final class _SignedLiteral {
  const new({required this.isAdded, required this.text});

  /// Whether the sign is `+`; `-` removes the literal.
  final bool isAdded;
  final String text;
}

/// A line that breaks its kind's form, or reads as no kind.
final class _Malformed implements Exception {
  const new(this.message);

  final String message;
}
