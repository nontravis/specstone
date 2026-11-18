import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart'
    show isFingerprint, withoutSection;
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/index_query/models/matrix_line.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

const _skipMark = ' skipped: ';

/// Returns the line [text], file line [line] of a record, as a row, or as a
/// [MalformedRow] when it is neither shape.
///
/// A test row is ``- <item> <edge case>: `<literal>`[ <fingerprint>]``; a
/// skip row is `- <item> <edge case> skipped: <reason>[ <fingerprint>]`. A
/// fingerprint is 12 lowercase hex characters. A skip row with no reason is
/// malformed. Trailing whitespace after a row is no part of it.
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
  final rest = head.rest.substring(2).trimRight();
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
    written: _writtenOf(text, fingerprint),
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
    written: _writtenOf(text, fingerprint),
  );
}

/// Returns the row [text] less its leading `- `, its trailing whitespace, and
/// [fingerprint] with the spaces before it.
String _writtenOf(String text, String? fingerprint) {
  final body = text.trimRight().substring(2);
  return fingerprint == null
      ? body
      : body.substring(0, body.length - fingerprint.length).trimRight();
}

/// Returns the index of the Verification matrix section of [doc], a doc of
/// [recordType]; null when [recordType] has no enabled matrix section or [doc]
/// holds none.
///
/// The one finder of the section: the rows read, the rows added, the size
/// counts, and the approval hash all go through it.
int? matrixSectionIndexOf(Doc doc, MergedDocType recordType) =>
    verificationMatrixOf(recordType) == null
    ? null
    : sectionIndexOf(doc, recordType, verificationMatrixKey);

/// Returns the text of [doc], a doc of [recordType], less its Verification
/// matrix section: the one [matrixLinesOfDoc] reads.
///
/// The cut is [withoutSection]; the text as it is when [recordType] has no
/// enabled matrix section or [doc] holds none.
String withoutMatrixSection(Doc doc, MergedDocType recordType) {
  final at = matrixSectionIndexOf(doc, recordType);
  return at == null ? doc.text : withoutSection(doc.text, at);
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
  final at = matrixSectionIndexOf(doc, recordType);
  if (at == null) return const [];
  final headerLine =
      linesBeforeBodyOf(doc, lfText) + doc.sectionLineIndexes[at] + 1;
  final bodyLines = doc.sections[at].body.split('\n');
  return [
    for (final (i, text) in bodyLines.indexed)
      if (text.trim().isNotEmpty) parseMatrixLine(text, headerLine + 1 + i),
  ];
}
