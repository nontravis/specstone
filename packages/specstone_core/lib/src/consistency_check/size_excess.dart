import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/required_sections.dart';
import 'package:specstone_core/src/doc_model/models/section_item.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_facts.dart'
    show sectionItemsAt;
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// One size of a doc, a section, or a `###` subsection past its bound: over
/// a limit, or, for an item count, under its minimum.
final class SizeExcess {
  const new({
    required this.kind,
    required this.line,
    required this.limit,
    required this.actual,
    this.sectionKey,
    this.isFloor = false,
  });

  /// `lines_over_limit`, `chars_over_limit`, or `item_count_out_of_range`.
  final FindingKind kind;

  /// The 1-based file line the finding sits on.
  final int line;

  /// The bound [actual] passes.
  final int limit;
  final int actual;

  /// The key the section maps to, else its own key; null for the whole doc.
  final String? sectionKey;

  /// Whether [limit] is the fewest items and [actual] lies under it.
  final bool isFloor;

  /// How far [actual] lies past [limit].
  int get excess => isFloor ? limit - actual : actual - limit;
}

/// Returns the sizes of [content], a doc of [type], past a bound, in doc order:
/// the doc's lines and characters, then for each held section its lines,
/// characters, and item count.
///
/// A section with no template of its own takes the doc's caps, bar the
/// verification matrix, which answers to its own. An item count is read per
/// `###` subsection when its lint says so; a floor is read as the count gives
/// it, except at a blank required section, where none is read. [content] must
/// carry the section counts of a full index read.
List<SizeExcess> sizeExcessesOf(
  IndexedDoc doc,
  DocContent content,
  MergedDocType type,
) => _read[content] ??= _excessesIn(doc, content, type);

/// The reads [sizeExcessesOf] made, so a doc read by two rules is counted once.
final _read = Expando<List<SizeExcess>>();

List<SizeExcess> _excessesIn(
  IndexedDoc doc,
  DocContent content,
  MergedDocType type,
) {
  final facts = content.lineFacts;
  final docMaxLines = type.lint.maxLines;
  final docMaxChars = type.lint.maxChars;
  final docChars = facts.charCount - facts.approvalMarkChars;
  final templates = heldTemplatesOf(content.sections, type);
  final matrixId = verificationMatrixOf(type)?.id;
  final found = <SizeExcess>[
    if (docMaxLines != null && facts.lineCount > docMaxLines)
      SizeExcess(
        kind: FindingKind.linesOverLimit,
        line: 1,
        limit: docMaxLines,
        actual: facts.lineCount,
      ),
    if (docMaxChars != null && docChars > docMaxChars)
      SizeExcess(
        kind: FindingKind.charsOverLimit,
        line: 1,
        limit: docMaxChars,
        actual: docChars,
      ),
  ];
  for (final (i, held) in content.sections.indexed) {
    final template = templates[i];
    final sectionKey = template?.id ?? held.key;
    final headerLine = facts.sectionLines[i];
    final isMatrix = matrixId != null && template?.id == matrixId;
    final maxLines = template?.maxLines ?? (isMatrix ? null : docMaxLines);
    final maxChars = template?.maxChars ?? (isMatrix ? null : docMaxChars);
    final counts = facts.sectionCounts[i];
    if (maxLines != null && counts.lines > maxLines) {
      found.add(
        SizeExcess(
          kind: FindingKind.linesOverLimit,
          line: headerLine,
          limit: maxLines,
          actual: counts.lines,
          sectionKey: sectionKey,
        ),
      );
    }
    if (maxChars != null && counts.chars > maxChars) {
      found.add(
        SizeExcess(
          kind: FindingKind.charsOverLimit,
          line: headerLine,
          limit: maxChars,
          actual: counts.chars,
          sectionKey: sectionKey,
        ),
      );
    }
    final count = template?.itemCount;
    if (count == null) continue;
    found.addAll(
      _countExcesses(
        sectionKey: sectionKey,
        headerLine: headerLine,
        lint: count,
        skipFloor:
            isBlankIn(content, i) &&
            template != null &&
            isRequiredIn(doc, content, type, template),
        items: sectionItemsAt(content, i, type),
      ),
    );
  }
  return List.unmodifiable(found);
}

/// Returns the item-count excesses of one section's [items], counting the top
/// level list items, table rows, and paragraphs.
Iterable<SizeExcess> _countExcesses({
  required String sectionKey,
  required int headerLine,
  required ItemCountLint lint,
  required bool skipFloor,
  required List<SectionItem> items,
}) sync* {
  final topLevel = [
    for (final item in items)
      if (!item.nested) item,
  ];
  if (!lint.perSubsection) {
    yield* _countExcessIn(
      lint,
      skipFloor: skipFloor,
      actual: _countedIn(topLevel),
      line: headerLine,
      sectionKey: sectionKey,
    );
    return;
  }
  for (final _Subsection(:heading, :under) in _subsectionsOf(topLevel)) {
    yield* _countExcessIn(
      lint,
      skipFloor: skipFloor,
      actual: _countedIn(under),
      line: heading.line,
      sectionKey: sectionKey,
    );
  }
}

/// Returns the excess of a count of [actual] items, when it lies under the
/// fewest or over the most [lint] allows.
Iterable<SizeExcess> _countExcessIn(
  ItemCountLint lint, {
  required bool skipFloor,
  required int actual,
  required int line,
  required String sectionKey,
}) sync* {
  final (min, max) = (lint.min, lint.max);
  final isFloor = !skipFloor && min != null && actual < min;
  final bound = isFloor ? min : max;
  if (bound == null || (!isFloor && actual <= bound)) return;
  yield SizeExcess(
    kind: FindingKind.itemCountOutOfRange,
    line: line,
    limit: bound,
    actual: actual,
    sectionKey: sectionKey,
    isFloor: isFloor,
  );
}

int _countedIn(List<SectionItem> items) =>
    items.where((item) => item.kind != SectionItemKind.heading).length;

/// A `###` heading item and the items under it.
final class _Subsection {
  new(this.heading);

  final SectionItem heading;
  final List<SectionItem> under = [];
}

/// Returns each `###` heading item of [items] with the items under it.
List<_Subsection> _subsectionsOf(List<SectionItem> items) {
  final subsections = <_Subsection>[];
  for (final item in items) {
    if (item.kind == SectionItemKind.heading) {
      subsections.add(_Subsection(item));
    } else if (subsections.isNotEmpty) {
      subsections.last.under.add(item);
    }
  }
  return subsections;
}
