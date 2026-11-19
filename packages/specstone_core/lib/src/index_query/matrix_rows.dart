import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart'
    show isFingerprint, withoutSection;
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/index_query/models/matrix_line.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

const _skipMark = ' skipped: ';
const _literalSeparator = ', ';

/// Returns the line [text], file line [line] of a record, as a row, or as a
/// [MalformedRow] when it is neither shape.
///
/// A per-FR test row is one or more code spans, each set off by exactly `, `
/// and none written twice, after `- item: `; a per-edge-case test row is one
/// span after `- item E01: `. A skip row is `- item skipped: reason` or
/// `- item E01 skipped: reason`. Each row may end in a space and a fingerprint
/// of 12 lowercase hex characters. A skip row with no reason is malformed.
/// Trailing whitespace after a row is no part of it.
///
/// The form is read from the line alone, never from a mode.
MatrixLine parseMatrixLine(String text, int line) =>
    _testRowOf(text, line) ??
    _skipRowOf(text, line) ??
    MalformedRow(line: line, text: text);

/// The item, and the edge case when the row names one, that open a row, and
/// the text after them.
final class _RowHead {
  const new(this.item, this.edgeCase, this.rest);

  final String item;
  final String? edgeCase;
  final String rest;
}

/// Returns the `- <item> <edge case>` or `- <item>` that opens [text] and what
/// follows it, or null when [text] does not open so. The item holds no space;
/// the edge case is `E` and digits, and is tried first, so an item followed by
/// one keeps the per-edge-case reading.
_RowHead? _headOf(String text) {
  if (!text.startsWith('- ')) return null;
  return _edgeCaseHeadOf(text) ?? _frHeadOf(text);
}

_RowHead? _edgeCaseHeadOf(String text) {
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

_RowHead? _frHeadOf(String text) {
  var itemEnd = 2;
  while (itemEnd < text.length &&
      text[itemEnd] != ' ' &&
      text[itemEnd] != ':') {
    itemEnd++;
  }
  if (itemEnd == 2) return null;
  return _RowHead(text.substring(2, itemEnd), null, text.substring(itemEnd));
}

bool _isEdgeCase(String text) =>
    text.length > 1 &&
    text.startsWith('E') &&
    text.codeUnits.skip(1).every((unit) => unit >= 0x30 && unit <= 0x39);

TestRow? _testRowOf(String text, int line) {
  final head = _headOf(text);
  if (head == null || !head.rest.startsWith(': ')) return null;
  final rest = head.rest.substring(2).trimRight();
  final literals = <String>[];
  var at = 0;
  for (final span in codeSpansOf(rest)) {
    if (span.start != at) break;
    literals.add(
      _spanContentOf(
        rest.substring(span.start + span.ticks, span.end - span.ticks),
      ),
    );
    at = span.end;
    if (!rest.startsWith(_literalSeparator, at)) break;
    at += _literalSeparator.length;
  }
  if (literals.isEmpty || literals.toSet().length != literals.length) {
    return null;
  }
  if (head.edgeCase != null && literals.length > 1) return null;
  final tail = rest.substring(at);
  if (tail.isNotEmpty && !tail.startsWith(' ')) return null;
  final fingerprint = tail.isEmpty ? null : tail.substring(1);
  if (fingerprint != null && !isFingerprint(fingerprint)) return null;
  return TestRow(
    item: head.item,
    edgeCase: head.edgeCase,
    literals: literals,
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
