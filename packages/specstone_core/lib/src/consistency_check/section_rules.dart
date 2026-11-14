import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_facts.dart';

const _projectType = 'project';
const _visionSection = 'vision';
const _visionEntryPrefix = '### ';
final _headingLine = RegExp('^#{1,6} ');
final _quoteLine = RegExp('^> [A-Za-z-]+: ');
final _digit = RegExp(r'\p{Nd}', unicode: true);

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
  yield* _titleNumberFinding(context, doc, type.lint.titleNoNumber ?? false);
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
  final itemFacts = context.contentOf(doc).itemFacts;
  final itemLimit = type.lint.itemCharLimit;
  yield* _itemFindings(context, doc, leadKey, itemFacts.leadItems, itemLimit);
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
    yield* _itemFindings(
      context,
      doc,
      sectionKey,
      itemFacts.sectionItems[i],
      itemLimit,
    );
    if (type.id == _projectType && template?.id == _visionSection) {
      yield* _visionQuoteFindings(context, doc, context.bodyLinesOf(doc, i));
    }
  }
}

Iterable<Finding> _titleNumberFinding(
  CheckContext context,
  IndexedDoc doc,
  bool titleNoNumber,
) sync* {
  final title = doc.title;
  if (!titleNoNumber || title == null || !_digit.hasMatch(title)) return;
  yield context.finding(
    doc,
    FindingKind.titleNumbered,
    line: _titleLineOf(context, doc),
    message: 'the title holds a digit',
  );
}

/// Returns the file line of the first `# ` line below the frontmatter.
int _titleLineOf(CheckContext context, IndexedDoc doc) {
  final lines = context.linesOf(doc);
  final frontmatter = context.contentOf(doc).frontmatterText ?? '';
  final skip = frontmatter.isEmpty
      ? 0
      : frontmatter.split('\n').length - (frontmatter.endsWith('\n') ? 1 : 0);
  for (var i = skip; i < lines.lines.length; i++) {
    if (lines.lines[i].startsWith('# ') && !lines.isFenced(i + 1)) return i + 1;
  }
  return 1;
}

Iterable<Finding> _itemFindings(
  CheckContext context,
  IndexedDoc doc,
  String sectionKey,
  List<ItemFact> items,
  int limit,
) sync* {
  for (final item in items) {
    if (item.chars <= limit) continue;
    final name = switch (item.id) {
      final id? => 'item $id',
      null => 'the item at line ${item.line}',
    };
    yield context.finding(
      doc,
      FindingKind.itemOverLimit,
      line: item.line,
      message:
          '$name of section $sectionKey has ${item.chars} characters; the '
          'limit is $limit',
      keys: {
        'section': sectionKey,
        'id': ?item.id,
        'limit': limit,
        'actual': item.chars,
      },
    );
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
