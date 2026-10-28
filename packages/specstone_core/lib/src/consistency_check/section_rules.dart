import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';

const _projectType = 'project';
const _visionSection = 'vision';
const _visionEntryPrefix = '### ';
final _headingLine = RegExp('^#{1,6} ');
final _quoteLine = RegExp('^> [A-Za-z-]+: ');

/// Returns the title, section, and size findings of a typed [doc]; an untyped
/// doc has none.
Iterable<Finding> checkSections(CheckContext context, IndexedDoc doc) sync* {
  final type = context.typeOf(doc);
  if (type == null) return;
  final lines = context.linesOf(doc);
  final held = context.contentOf(doc).sections;
  if (doc.title?.trim().isEmpty ?? true) {
    yield context.finding(
      doc,
      FindingKind.titleMissing,
      line: 1,
      message: 'the doc has no # title',
    );
  }
  for (final section in type.sections) {
    if (section.required && context.heldSection(doc, section.id) == null) {
      yield context.finding(
        doc,
        FindingKind.requiredSectionMissing,
        line: 1,
        message: 'required section ${section.id} is missing',
        keys: {'section': section.id},
      );
    }
  }
  final docMaxLines = type.lint.maxLines;
  final docMaxChars = type.lint.maxChars;
  if (docMaxLines != null && lines.lineCount > docMaxLines) {
    yield context.finding(
      doc,
      FindingKind.linesOverLimit,
      line: 1,
      message:
          'the doc has ${lines.lineCount} lines; the limit is '
          '$docMaxLines',
      keys: {'limit': docMaxLines, 'actual': lines.lineCount},
    );
  }
  if (docMaxChars != null && lines.charCount > docMaxChars) {
    yield context.finding(
      doc,
      FindingKind.charsOverLimit,
      line: 1,
      message:
          'the doc has ${lines.charCount} characters; the limit is '
          '$docMaxChars',
      keys: {'limit': docMaxChars, 'actual': lines.charCount},
    );
  }
  for (var i = 0; i < held.length; i++) {
    final section = held[i];
    final headerLine = lines.sectionLines[i];
    final template = context.templateSectionAt(doc, i);
    final sectionKey = template?.id ?? section.key;
    if (template == null) {
      final header = section.headerLine.trimLeft().substring(2).trim();
      yield context.finding(
        doc,
        FindingKind.sectionUndeclared,
        line: headerLine,
        message: 'section $header is not declared',
        keys: {'header': header},
      );
    }
    final maxLines = template?.maxLines ?? docMaxLines;
    final maxChars = template?.maxChars ?? docMaxChars;
    final (lines: actualLines, chars: actualChars) = lines.sectionCounts[i];
    if (maxLines != null && actualLines > maxLines) {
      yield context.finding(
        doc,
        FindingKind.linesOverLimit,
        line: headerLine,
        message:
            'section $sectionKey has $actualLines lines; the limit '
            'is $maxLines',
        keys: {'section': sectionKey, 'limit': maxLines, 'actual': actualLines},
      );
    }
    if (maxChars != null && actualChars > maxChars) {
      yield context.finding(
        doc,
        FindingKind.charsOverLimit,
        line: headerLine,
        message:
            'section $sectionKey has $actualChars characters; the '
            'limit is $maxChars',
        keys: {'section': sectionKey, 'limit': maxChars, 'actual': actualChars},
      );
    }
    if (type.id == _projectType && template?.id == _visionSection) {
      yield* _visionQuoteFindings(context, doc, context.bodyLinesOf(doc, i));
    }
  }
}

Iterable<Finding> _visionQuoteFindings(
  CheckContext context,
  IndexedDoc doc,
  List<BodyLine> body,
) sync* {
  for (var i = 0; i < body.length; i++) {
    if (body[i].fenced || !body[i].text.startsWith(_visionEntryPrefix)) {
      continue;
    }
    var quoted = false;
    for (var j = i + 1; j < body.length; j++) {
      if (body[j].fenced) continue;
      if (_headingLine.hasMatch(body[j].text)) break;
      if (_quoteLine.hasMatch(body[j].text)) {
        quoted = true;
        break;
      }
    }
    if (quoted) continue;
    yield context.finding(
      doc,
      FindingKind.visionQuoteMissing,
      line: body[i].line,
      message:
          'vision entry ${body[i].text.substring(_visionEntryPrefix.length)} '
          'has no quote line',
    );
  }
}
