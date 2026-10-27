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
  if (doc.title == null) {
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
  if (docMaxLines != null && lines.lines.length > docMaxLines) {
    yield context.finding(
      doc,
      FindingKind.linesOverLimit,
      line: 1,
      message:
          'the doc has ${lines.lines.length} lines; the limit is '
          '$docMaxLines',
      keys: {'limit': docMaxLines, 'actual': lines.lines.length},
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
    final template = context.templateSectionOf(type, section);
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
    final actualLines = section.text.split('\n').length;
    final actualChars = section.text.runes.length;
    if (maxLines != null && actualLines > maxLines) {
      yield context.finding(
        doc,
        FindingKind.linesOverLimit,
        line: headerLine,
        message:
            'section ${section.key} has $actualLines lines; the limit '
            'is $maxLines',
        keys: {
          'section': section.key,
          'limit': maxLines,
          'actual': actualLines,
        },
      );
    }
    if (maxChars != null && actualChars > maxChars) {
      yield context.finding(
        doc,
        FindingKind.charsOverLimit,
        line: headerLine,
        message:
            'section ${section.key} has $actualChars characters; the '
            'limit is $maxChars',
        keys: {
          'section': section.key,
          'limit': maxChars,
          'actual': actualChars,
        },
      );
    }
    if (type.id == _projectType && template?.id == _visionSection) {
      yield* _visionQuoteFindings(context, doc, section, headerLine);
    }
  }
}

Iterable<Finding> _visionQuoteFindings(
  CheckContext context,
  IndexedDoc doc,
  IndexedSection section,
  int headerLine,
) sync* {
  final body = section.body.split('\n');
  for (var i = 0; i < body.length; i++) {
    if (!body[i].startsWith(_visionEntryPrefix)) continue;
    var quoted = false;
    for (
      var j = i + 1;
      j < body.length && !_headingLine.hasMatch(body[j]);
      j++
    ) {
      if (_quoteLine.hasMatch(body[j])) {
        quoted = true;
        break;
      }
    }
    if (quoted) continue;
    yield context.finding(
      doc,
      FindingKind.visionQuoteMissing,
      line: headerLine + 1 + i,
      message:
          'vision entry ${body[i].substring(_visionEntryPrefix.length)} '
          'has no quote line',
    );
  }
}
