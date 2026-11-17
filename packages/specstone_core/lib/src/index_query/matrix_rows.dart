import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// One non-blank line of a record's Verification matrix section: a row, or a
/// line that is no row.
sealed class MatrixLine {
  const new({required this.line});

  /// Reads the line [toJson] wrote.
  ///
  /// Throws a [FormatException] for a `kind` that names no line.
  factory fromJson(Map<String, Object?> json) {
    final line = json['line']! as int;
    return switch (json['kind']) {
      'test' => TestRow(
        item: json['item']! as String,
        edgeCase: json['edgeCase']! as String,
        literal: json['literal']! as String,
        fingerprint: json['fingerprint'] as String?,
        line: line,
      ),
      'skip' => SkipRow(
        item: json['item']! as String,
        edgeCase: json['edgeCase']! as String,
        reason: json['reason']! as String,
        fingerprint: json['fingerprint'] as String?,
        line: line,
      ),
      'malformed' => MalformedRow(line: line, text: json['text']! as String),
      final kind => throw FormatException('no matrix line of kind $kind'),
    };
  }

  /// The 1-based file line.
  final int line;

  /// The line as the index stores it.
  Map<String, Object?> toJson();
}

/// A section line that is neither a test row nor a skip row.
final class MalformedRow extends MatrixLine {
  const new({required super.line, required this.text});

  /// The line as written.
  final String text;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is MalformedRow && other.line == line && other.text == text;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(line, text);

  @override
  Map<String, Object?> toJson() => {
    'kind': 'malformed',
    'line': line,
    'text': text,
  };

  @override
  String toString() => 'MalformedRow(line: $line, text: $text)';
}

/// A row of the Verification matrix: the FR edge case it names, a test or a
/// skip.
sealed class MatrixRow extends MatrixLine {
  const new({
    required this.item,
    required this.edgeCase,
    required super.line,
    this.fingerprint,
  });

  /// The FR the row names, relative to the record's feature.
  final String item;

  /// The edge case ID the row names, as the FR writes it.
  final String edgeCase;

  /// The 12 lowercase hex characters that end the row; null with none.
  final String? fingerprint;

  /// The row's link label: the item, `#`, and the edge case.
  String get label => '$item#$edgeCase';
}

/// A row that names one string literal of a test's name.
final class TestRow extends MatrixRow {
  const new({
    required super.item,
    required super.edgeCase,
    required this.literal,
    required super.line,
    super.fingerprint,
  });

  /// The content of the row's code span, as the test file writes the name.
  final String literal;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is TestRow &&
      other.item == item &&
      other.edgeCase == edgeCase &&
      other.literal == literal &&
      other.fingerprint == fingerprint &&
      other.line == line;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(item, edgeCase, literal, fingerprint, line);

  @override
  Map<String, Object?> toJson() => {
    'kind': 'test',
    'item': item,
    'edgeCase': edgeCase,
    'literal': literal,
    'fingerprint': fingerprint,
    'line': line,
  };

  @override
  String toString() =>
      'TestRow(item: $item, edgeCase: $edgeCase, literal: $literal, '
      'fingerprint: $fingerprint, line: $line)';
}

/// A row that gives the reason no test proves its edge case.
final class SkipRow extends MatrixRow {
  const new({
    required super.item,
    required super.edgeCase,
    required this.reason,
    required super.line,
    super.fingerprint,
  });

  /// The text after `skipped: `, its fingerprint left off.
  final String reason;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is SkipRow &&
      other.item == item &&
      other.edgeCase == edgeCase &&
      other.reason == reason &&
      other.fingerprint == fingerprint &&
      other.line == line;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(item, edgeCase, reason, fingerprint, line);

  @override
  Map<String, Object?> toJson() => {
    'kind': 'skip',
    'item': item,
    'edgeCase': edgeCase,
    'reason': reason,
    'fingerprint': fingerprint,
    'line': line,
  };

  @override
  String toString() =>
      'SkipRow(item: $item, edgeCase: $edgeCase, reason: $reason, '
      'fingerprint: $fingerprint, line: $line)';
}

const _skipMark = ' skipped: ';

/// Returns the line [text], file line [line] of a record, as a row, or as a
/// [MalformedRow] when it is neither shape.
///
/// A test row is ``- <item> <edge case>: `<literal>`[ <fingerprint>]``; a
/// skip row is `- <item> <edge case> skipped: <reason>[ <fingerprint>]`. A
/// fingerprint is 12 lowercase hex characters.
MatrixLine parseMatrixLine(String text, int line) =>
    _testRowOf(text, line) ??
    _skipRowOf(text, line) ??
    MalformedRow(line: line, text: text);

/// The item and edge case that open a row, and the text after them.
final class _RowHead {
  const new(this.item, this.edgeCase, this.rest);

  final String item;
  final String edgeCase;
  final String rest;
}

/// Returns the `- <item> <edge case>` that opens [text] and what follows it,
/// or null when [text] does not open so. The item holds no space; the edge
/// case is `E` and digits.
_RowHead? _headOf(String text) {
  if (!text.startsWith('- ')) return null;
  final itemEnd = text.indexOf(' ', 2);
  if (itemEnd <= 2) return null;
  var edgeEnd = itemEnd + 1;
  while (edgeEnd < text.length &&
      text[edgeEnd] != ' ' &&
      text[edgeEnd] != ':') {
    edgeEnd++;
  }
  final edgeCase = text.substring(itemEnd + 1, edgeEnd);
  if (!_isEdgeCase(edgeCase)) return null;
  return _RowHead(
    text.substring(2, itemEnd),
    edgeCase,
    text.substring(edgeEnd),
  );
}

bool _isEdgeCase(String text) =>
    text.length > 1 &&
    text.startsWith('E') &&
    text.codeUnits.skip(1).every((unit) => unit >= 0x30 && unit <= 0x39);

TestRow? _testRowOf(String text, int line) {
  final head = _headOf(text);
  if (head == null || !head.rest.startsWith(': ')) return null;
  final rest = head.rest.substring(2);
  final span = codeSpansOf(rest).firstOrNull;
  if (span == null || span.start != 0) return null;
  final tail = rest.substring(span.end);
  if (tail.isNotEmpty && !tail.startsWith(' ')) return null;
  final fingerprint = tail.isEmpty ? null : tail.substring(1);
  if (fingerprint != null && !isFingerprint(fingerprint)) return null;
  return TestRow(
    item: head.item,
    edgeCase: head.edgeCase,
    literal: _spanContentOf(rest.substring(span.ticks, span.end - span.ticks)),
    fingerprint: fingerprint,
    line: line,
  );
}

/// Returns [content], a code span's text, as CommonMark reads it: one space
/// off each end when both ends hold one and the content is not all spaces.
String _spanContentOf(String content) {
  final padded =
      content.length > 1 &&
      content.startsWith(' ') &&
      content.endsWith(' ') &&
      content.trim().isNotEmpty;
  return padded ? content.substring(1, content.length - 1) : content;
}

SkipRow? _skipRowOf(String text, int line) {
  final head = _headOf(text);
  if (head == null || !head.rest.startsWith(_skipMark)) return null;
  final written = head.rest.substring(_skipMark.length).trimRight();
  if (written.startsWith(' ')) return null;
  final split = written.lastIndexOf(' ');
  final tail = written.substring(split + 1);
  final fingerprint = isFingerprint(tail) ? tail : null;
  final reason = switch ((fingerprint, split)) {
    (null, _) => written,
    (_, < 0) => '',
    _ => written.substring(0, split).trimRight(),
  };
  if (reason.isEmpty) return null;
  return SkipRow(
    item: head.item,
    edgeCase: head.edgeCase,
    reason: reason,
    fingerprint: fingerprint,
    line: line,
  );
}

/// Returns each non-blank line of the Verification matrix section of
/// [lfText], a doc of [recordType], through [parseMatrixLine], in file order.
///
/// The section is the one whose header is the header of the matrix section of
/// [recordType] ([verificationMatrixOf]). Empty when [recordType] has no
/// enabled matrix section or [lfText] holds none.
List<MatrixLine> matrixLinesIn(String lfText, MergedDocType recordType) =>
    matrixLinesOfDoc(Doc.parse(lfText), lfText, recordType);

/// Returns the lines [matrixLinesIn] gives for [lfText], already parsed as
/// [doc], so a caller that holds the parse reads it once.
List<MatrixLine> matrixLinesOfDoc(
  Doc doc,
  String lfText,
  MergedDocType recordType,
) {
  if (verificationMatrixOf(recordType) == null) return const [];
  final at = sectionIndexOf(doc, recordType, verificationMatrixKey);
  if (at == null) return const [];
  final headerLine =
      linesBeforeBodyOf(doc, lfText) + doc.sectionLineIndexes[at] + 1;
  final bodyLines = doc.sections[at].body.split('\n');
  return [
    for (final (i, text) in bodyLines.indexed)
      if (text.trim().isNotEmpty) parseMatrixLine(text, headerLine + 1 + i),
  ];
}
