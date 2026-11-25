import 'package:specstone_core/src/doc_model/models/section_item.dart';
import 'package:specstone_core/src/doc_model/sentences.dart'
    show collapseWhitespace;
import 'package:specstone_core/src/document_writing/approval_view.dart'
    show comparableTextOf;
import 'package:specstone_core/src/index_query/held_sections.dart'
    show sectionBodyLines;
import 'package:specstone_core/src/index_query/indexed_doc.dart'
    show docStructureOf;
import 'package:specstone_core/src/index_query/item_facts.dart'
    show sectionItemsAt;
import 'package:specstone_core/src/index_query/models/doc_content.dart';
import 'package:specstone_core/src/index_query/models/indexed_section.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

final _quoteMarks = RegExp(r'^[ \t]*(?:>[ \t]?)+');

/// Where a draft differs from its audited copy.
final class DraftDelta {
  const new({
    required this.changedSections,
    required this.changesOutsideSections,
  });

  /// The keys of the sections whose text differs, in doc order.
  final List<String> changedSections;

  /// Whether the title, the frontmatter, the head, a section heading, or the
  /// section order differs, or either side repeats a section key.
  final bool changesOutsideSections;
}

/// Returns where [currentLf] differs from [auditedLf], both laid out as the
/// approval view lays them out, so a layout-only change is no change.
///
/// A null [auditedLf] lists every section and marks a change outside them.
DraftDelta draftDeltaOf(
  String currentLf,
  String? auditedLf,
  MergedDocType? type,
) {
  final current = _structureOf(currentLf, type);
  if (auditedLf == null) {
    return DraftDelta(
      changedSections: _keysOf(current.sections).toList(),
      changesOutsideSections: true,
    );
  }
  final audited = _structureOf(auditedLf, type);
  final unpaired = <String, List<IndexedSection>>{};
  for (final section in audited.sections) {
    (unpaired[section.key] ??= []).add(section);
  }
  final changed = <String>{};
  var isHeadingChanged = false;
  for (final section in current.sections) {
    final twins = unpaired[section.key];
    final twin = twins == null || twins.isEmpty ? null : twins.removeAt(0);
    if (twin == null || twin.body != section.body) changed.add(section.key);
    if (twin != null && twin.headerLine != section.headerLine) {
      isHeadingChanged = true;
    }
  }
  for (final MapEntry(:key, :value) in unpaired.entries) {
    if (value.isNotEmpty) changed.add(key);
  }
  return DraftDelta(
    changedSections: changed.toList(),
    changesOutsideSections:
        isHeadingChanged ||
        _hasRepeatedKey(current.sections) ||
        _hasRepeatedKey(audited.sections) ||
        _outsideOf(current) != _outsideOf(audited) ||
        !_sameOrder(current.sections, audited.sections),
  );
}

/// Returns the body of the first section of [lf] keyed [sectionKey], or null
/// when the doc has none.
String? sectionBodyOf(String lf, MergedDocType? type, String sectionKey) {
  for (final section in docStructureOf(lf, type).sections) {
    if (section.key == sectionKey) return section.body;
  }
  return null;
}

/// Returns whether section bodies [a] and [b] hold the same items, compared
/// item by item as [comparableItemTextOf] reads them.
///
/// Whitespace runs, the `>` marks that open lines, and list markers and
/// numbers do not count. A body with a line no item holds, such as a fence or
/// a table header, compares whole, only whitespace runs not counting.
bool sameByEqualText(String a, String b) {
  final leftItems = _itemsOf(a);
  final rightItems = _itemsOf(b);
  if (leftItems == null || rightItems == null) {
    return collapseWhitespace(a).trim() == collapseWhitespace(b).trim();
  }
  if (leftItems.length != rightItems.length) return false;
  for (var i = 0; i < leftItems.length; i++) {
    if (comparableItemTextOf(leftItems[i]) !=
        comparableItemTextOf(rightItems[i])) {
      return false;
    }
  }
  return true;
}

/// Returns the text of [item] to compare: whitespace collapsed, each opening
/// `>` mark and the list marker dropped, so a rewrap or a renumber is no
/// change.
String comparableItemTextOf(SectionItem item) => collapseWhitespace(
  [
    item.head,
    for (final line in item.text.split('\n').skip(1))
      line.replaceFirst(_quoteMarks, ''),
  ].join(' '),
).trim();

DocContent _structureOf(String lf, MergedDocType? type) =>
    docStructureOf(comparableTextOf(lf, type), type);

Iterable<String> _keysOf(List<IndexedSection> sections) => {
  for (final section in sections) section.key,
};

String _outsideOf(DocContent content) =>
    '${content.frontmatterText ?? ''}\u0000${content.head}';

bool _sameOrder(List<IndexedSection> a, List<IndexedSection> b) {
  final inA = {for (final section in a) section.key};
  final inB = {for (final section in b) section.key};
  final left = [
    for (final section in a)
      if (inB.contains(section.key)) section.key,
  ];
  final right = [
    for (final section in b)
      if (inA.contains(section.key)) section.key,
  ];
  return left.length == right.length &&
      Iterable<int>.generate(left.length).every((i) => left[i] == right[i]);
}

bool _hasRepeatedKey(List<IndexedSection> sections) =>
    _keysOf(sections).length != sections.length;

/// Returns the items of [body] read as the one section of a doc, or null when
/// it holds a `##` line that opens a second one or a text line no item holds:
/// a fence, a table's header or delimiter row, or a thematic break.
List<SectionItem>? _itemsOf(String body) {
  final content = docStructureOf('## s\n$body\n', null);
  if (content.sections.length != 1) return null;
  final items = sectionItemsAt(content, 0, null);
  final held = {
    for (final item in items)
      for (var k = 0; k < item.text.split('\n').length; k++) item.line + k,
  };
  final isWhole = sectionBodyLines(
    content.sections,
    content.lineFacts,
    0,
  ).every((line) => held.contains(line.line) || _isBlank(line.text));
  return isWhole ? items : null;
}

/// Whether [line] holds no text after its `>` marks.
bool _isBlank(String line) => line.replaceFirst(_quoteMarks, '').trim().isEmpty;
