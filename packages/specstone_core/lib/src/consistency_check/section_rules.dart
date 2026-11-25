import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/move_hints.dart';
import 'package:specstone_core/src/consistency_check/required_sections.dart';
import 'package:specstone_core/src/consistency_check/size_excess.dart';
import 'package:specstone_core/src/doc_model/doc_items.dart'
    show headingItemTextOf, opensHeadingItem;
import 'package:specstone_core/src/doc_model/models/body_line.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/models/item_fact.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart'
    show verificationMatrixOf;

const _projectType = 'project';
const _visionSection = 'vision';
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
  if (!doc.hasTitle) {
    yield context.finding(
      doc,
      FindingKind.titleMissing,
      line: 1,
      message: 'the doc has no # title',
    );
  }
  yield* _titleNumberFinding(context, doc, type.lint.titleNoNumber ?? false);
  yield* _titleFixedFinding(context, doc, type.title);
  for (final section in type.sections) {
    if (!section.required || !appliesTo(doc, section.whenField)) continue;
    final index = context.heldIndexOf(doc, section.id);
    if (index == null) {
      yield requiredSectionFinding(context, doc, section.id);
    } else if (isBlankAt(context, doc, index)) {
      yield requiredSectionFinding(
        context,
        doc,
        section.id,
        headerLine: lines.sectionLines[index],
      );
    }
  }
  final excesses = sizeExcessesOf(doc, context.contentOf(doc), type);
  // Read only once a doc-level cap fires: a doc under its caps costs nothing.
  late final hint = moveHintsOf(context, doc);
  for (final excess in excesses) {
    if (excess.sectionKey != null) continue;
    final SizeExcess(:kind, :limit, :actual) = excess;
    yield context.finding(
      doc,
      kind,
      line: 1,
      message:
          'the doc has $actual ${_unitOf(kind)}; the limit is '
          '$limit${hint?.suffix ?? ''}',
      keys: {'limit': limit, 'actual': actual, ...?hint?.keys},
    );
  }
  final itemFacts = context.contentOf(doc).itemFacts;
  final itemLimit = type.lint.itemCharLimit;
  // The matrix section answers to its own limits, never to the doc's or the
  // item cap.
  final matrixId = verificationMatrixOf(type)?.id;
  yield* _itemFindings(context, doc, leadKey, itemFacts.leadItems, itemLimit);
  for (var i = 0; i < held.length; i++) {
    final section = held[i];
    final headerLine = lines.sectionLines[i];
    final template = context.templateSectionAt(doc, i);
    final sectionKey = template?.id ?? section.key;
    if (template == null) {
      final header = section.headerLine.trimLeft().substring(2).trim();
      final fix = context.index.set.leftoverForSection(type.id, header)?.home;
      yield context.finding(
        doc,
        FindingKind.sectionUndeclared,
        line: headerLine,
        message:
            'section $header is not declared'
            '${fix == null ? '' : '; $fix'}',
        keys: {'header': header, 'fix': ?fix},
      );
    }
    if (template?.whenField case final whenField?
        when !appliesTo(doc, whenField)) {
      yield context.finding(
        doc,
        FindingKind.sectionOutsideFieldValue,
        line: headerLine,
        message:
            'section $sectionKey is held only when ${whenField.field} is '
            '${whenField.values.join(' or ')}',
        keys: {'section': sectionKey},
      );
    }
    for (final excess in excesses) {
      if (excess.sectionKey == null || excess.line != headerLine) continue;
      if (!_isLineOrCharCap(excess.kind)) continue;
      final SizeExcess(:kind, :limit, :actual) = excess;
      yield context.finding(
        doc,
        kind,
        line: headerLine,
        message:
            'section $sectionKey has $actual ${_unitOf(kind)}; the limit '
            'is $limit',
        keys: {'section': sectionKey, 'limit': limit, 'actual': actual},
      );
    }
    if (matrixId == null || template?.id != matrixId) {
      yield* _itemFindings(
        context,
        doc,
        sectionKey,
        itemFacts.sectionItems[i],
        itemLimit,
      );
    }
    if (type.id == _projectType && template?.id == _visionSection) {
      yield* _visionQuoteFindings(context, doc, context.bodyLinesOf(doc, i));
    }
  }
}

bool _isLineOrCharCap(FindingKind kind) =>
    kind == FindingKind.linesOverLimit || kind == FindingKind.charsOverLimit;

String _unitOf(FindingKind kind) =>
    kind == FindingKind.linesOverLimit ? 'lines' : 'characters';

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
    line: titleLineOf(context, doc),
    message: 'the title holds a digit',
  );
}

Iterable<Finding> _titleFixedFinding(
  CheckContext context,
  IndexedDoc doc,
  String? fixedTitle,
) sync* {
  final title = doc.title;
  if (fixedTitle == null || title == null || title.trim() == fixedTitle) return;
  yield context.finding(
    doc,
    FindingKind.titleFixedMismatch,
    line: titleLineOf(context, doc),
    message: 'the title differs from the fixed title $fixedTitle',
  );
}

/// Returns the file line of the first `# ` line below the frontmatter, or 1
/// when the doc holds none.
int titleLineOf(CheckContext context, IndexedDoc doc) {
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
    if (item.visibleChars <= limit) continue;
    final name = switch (item.id) {
      final id? => 'item $id',
      null => 'the item at line ${item.line}',
    };
    yield context.finding(
      doc,
      FindingKind.itemOverLimit,
      line: item.line,
      message:
          '$name of section $sectionKey has ${item.visibleChars} characters; '
          'the limit is $limit',
      keys: {
        'section': sectionKey,
        'id': ?item.id,
        'limit': limit,
        'actual': item.visibleChars,
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
    final entry = body[i].fenced ? null : headingItemTextOf(body[i].text);
    if (entry == null) continue;
    var quoted = false;
    for (var j = i + 1; j < body.length; j++) {
      if (body[j].fenced) continue;
      if (_headingLine.hasMatch(body[j].text) ||
          opensHeadingItem(body[j].text)) {
        break;
      }
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
      message: 'vision entry $entry has no quote line',
    );
  }
}
