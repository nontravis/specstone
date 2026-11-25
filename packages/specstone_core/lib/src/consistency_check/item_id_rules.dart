import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/models/id_at.dart';
import 'package:specstone_core/src/doc_model/doc_items.dart'
    show headingItemTextOf, opensHeadingItem;
import 'package:specstone_core/src/doc_model/models/id_read.dart';
import 'package:specstone_core/src/doc_model/models/section_item.dart'
    show SectionItem, SectionItemKind;
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/doc_model/retired_id_list.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_facts.dart'
    show sectionItemsAt;
import 'package:specstone_core/src/templates/merged_doc_type.dart';

const _notApplicable = 'N/A';
const _itemIdForm = 'item_id';
// Unlike doc_items, an item that carries an ID starts at a top-level marker
// with text after it.
final _listMarker = RegExp(r'^(?:[-*+]|\d+[.)])\s+');
final _listOrdinal = RegExp(r'^(\d+)[.)]\s');

/// An item start: its body index, and its text with the marker stripped.
final class _Start {
  const new({required this.index, required this.text});

  final int index;
  final String text;
}

/// Returns the items of each held section of [content] whose template sets
/// `prefix_id` (a null `id` for an item with no ID), and, for a doc whose
/// type holds `acceptance_criteria`, each `### Scenario` heading there, fenced
/// lines excluded, in file order.
///
/// An item opening with `N/A` is no item.
List<IdAt> idsInDoc(DocContent content, MergedDocType type) {
  final templates = heldTemplatesOf(content.sections, type);
  return [
    for (final (i, template) in templates.indexed)
      if (template != null)
        ..._idsOfSection(
          template,
          sectionBodyLines(content.sections, content.lineFacts, i),
          template.prefixId == null
              ? const []
              : sectionItemsAt(content, i, type),
        ),
  ];
}

/// Returns the ID findings of a typed [doc]; an untyped doc has none.
///
/// A held section whose template writes a `prefix_id` holds items: the `###`
/// headings when it has any, else its top-level list entries and table rows,
/// fenced code excluded and `N/A` entries skipped. An item with no ID of that prefix
/// holds an `item_id_missing`; one repeating an ID already held in the doc,
/// or a scenario repeating a number's value, holds an `item_id_duplicate`;
/// one whose digits a letter follows, as does a story scenario heading,
/// holds an `item_id_lettered` naming the next free number, except an edge
/// case or a scenario, which takes its position. An item whose ID the doc's
/// `retired_ids` lists holds an `item_id_retired`. A section whose edge case
/// or scenario numbers, or list ordinals, are not their positions from 1
/// holds an `item_sequence_gap` at its header.
Iterable<Finding> checkItemIds(CheckContext context, IndexedDoc doc) sync* {
  final type = context.typeOf(doc);
  if (type == null) return;
  final parsed = context.parsedOf(doc);
  final items = idsInDoc(context.contentOf(doc), type);
  final reads = [for (final item in items) ?item.id];
  final retired = retiredIdsIn(parsed);
  final next = nextFreeIds(reads, retired: retired);
  final seen = <String, int>{};
  var readIndex = 0;
  for (final item in items) {
    final id = item.id;
    if (id == null) {
      yield _missing(context, doc, item);
      continue;
    }
    final index = readIndex++;
    if (id is UnreadableId) {
      yield _unreadable(context, doc, item, id);
    } else if (id is LetteredId) {
      yield _lettered(context, doc, item, id, next[index]);
    } else {
      final held = _heldKeyOf(item, id);
      final first = seen[held];
      if (first != null) {
        yield _duplicate(context, doc, item, id, first);
      } else {
        seen[held] = item.line;
        if (!isPositionalPrefix(item.prefix) && retired.contains(id.written)) {
          yield _retired(context, doc, item, id);
        }
      }
    }
  }
  yield* _sequenceGaps(context, doc, items, parsed.text.split('\n'));
}

Iterable<Finding> _sequenceGaps(
  CheckContext context,
  IndexedDoc doc,
  List<IdAt> items,
  List<String> lines,
) sync* {
  final bySection = <String, List<IdAt>>{};
  for (final item in items) {
    if (isPositionalPrefix(item.prefix)) {
      (bySection[item.sectionKey] ??= []).add(item);
    }
  }
  for (final MapEntry(key: sectionKey, value: held) in bySection.entries) {
    if (_isInSequence(held, lines)) continue;
    final index = context.heldIndexOf(doc, sectionKey);
    if (index == null) continue;
    yield context.finding(
      doc,
      FindingKind.itemSequenceGap,
      line: context.linesOf(doc).sectionLines[index],
      message:
          'the numbers or list ordinals of $sectionKey are not their '
          'positions from 1; number them with a keep plan: move --plan-out '
          '<doc>, then move --plan-file',
      keys: {'section': sectionKey},
    );
  }
}

// Each item's number and list ordinal, where it has them, equal its 1-based
// position in the section.
bool _isInSequence(List<IdAt> held, List<String> lines) {
  for (final (i, item) in held.indexed) {
    final position = BigInt.from(i + 1);
    if (item.id case ItemId(:final number) when number != position) {
      return false;
    }
    final ordinal = _listOrdinal.firstMatch(lines[item.line - 1])?.group(1);
    if (ordinal != null && BigInt.parse(ordinal) != position) return false;
  }
  return true;
}

// A scenario is held by its number's value, so `Scenario 01` repeats
// `Scenario 1`; an item ID by its text as written.
String _heldKeyOf(IdAt item, IdRead id) =>
    itemKeyOf(id, isScenario: item.prefix == scenarioIdPrefix);

Finding _missing(CheckContext context, IndexedDoc doc, IdAt item) =>
    context.finding(
      doc,
      FindingKind.itemIdMissing,
      line: item.line,
      message: 'the item opens with no ${item.prefix} ID',
      keys: {'section': item.sectionKey, 'prefix': item.prefix},
    );

Finding _duplicate(
  CheckContext context,
  IndexedDoc doc,
  IdAt item,
  IdRead id,
  int firstLine,
) => context.finding(
  doc,
  FindingKind.itemIdDuplicate,
  line: item.line,
  message: '${id.written} is already held at line $firstLine',
  keys: {'id': id.written, 'section': item.sectionKey},
);

Finding _retired(CheckContext context, IndexedDoc doc, IdAt item, IdRead id) =>
    context.finding(
      doc,
      FindingKind.itemIdRetired,
      line: item.line,
      message: '${id.written} left the doc and is not reused',
      keys: {'id': id.written, 'section': item.sectionKey},
    );

Finding _lettered(
  CheckContext context,
  IndexedDoc doc,
  IdAt item,
  IdRead id,
  String? next,
) => context.finding(
  doc,
  FindingKind.itemIdLettered,
  line: item.line,
  message: next == null
      ? '${id.written} has a letter after its number; it takes its position'
      : '${id.written} has a letter after its number; use $next',
  keys: {'id': id.written, 'section': item.sectionKey, 'next': ?next},
);

Finding _unreadable(
  CheckContext context,
  IndexedDoc doc,
  IdAt item,
  UnreadableId id,
) => context.finding(
  doc,
  FindingKind.referenceMalformed,
  line: item.line,
  message:
      '${id.written} cannot be read: a digit follows the letter after its '
      'number',
  keys: {'form': _itemIdForm, 'text': id.written},
);

List<IdAt> _idsOfSection(
  MergedSection template,
  List<BodyLine> body,
  List<SectionItem> items,
) => [
  if (template.prefixId case final prefix?)
    ..._itemIds(template.id, prefix, body, items),
  if (template.id == acceptanceSectionId) ..._scenarioIds(template.id, body),
];

List<IdAt> _itemIds(
  String sectionKey,
  String prefix,
  List<BodyLine> body,
  List<SectionItem> items,
) {
  final starts = _itemStartsOf(body, items);
  return [
    for (final (n, start) in starts.indexed)
      if (!start.text.startsWith(_notApplicable))
        _idAt(
          body,
          start.index,
          n + 1 < starts.length ? starts[n + 1].index : body.length,
          sectionKey: sectionKey,
          prefix: prefix,
          id: readItemId(start.text, prefix),
        ),
  ];
}

List<IdAt> _scenarioIds(String sectionKey, List<BodyLine> body) {
  final headings = [
    for (final (i, line) in body.indexed)
      if (!line.fenced && opensHeadingItem(line.text)) i,
  ];
  return [
    for (final (n, index) in headings.indexed)
      if (readScenarioHeading(body[index].text) case final id?)
        _idAt(
          body,
          index,
          n + 1 < headings.length ? headings[n + 1] : body.length,
          sectionKey: sectionKey,
          prefix: scenarioIdPrefix,
          id: id,
        ),
  ];
}

IdAt _idAt(
  List<BodyLine> body,
  int index,
  int nextIndex, {
  required String sectionKey,
  required String prefix,
  required IdRead? id,
}) {
  var last = nextIndex - 1;
  while (last > index && body[last].text.trim().isEmpty) {
    last--;
  }
  return IdAt(
    sectionKey: sectionKey,
    prefix: prefix,
    line: body[index].line,
    endLine: body[last].line,
    id: id,
  );
}

/// Returns the item starts of [body], marker stripped: the `###` headings
/// when it has any, else its top-level list items and table rows; fenced lines
/// are no start.
List<_Start> _itemStartsOf(List<BodyLine> body, List<SectionItem> items) {
  final headings = <_Start>[];
  final listItems = <_Start>[];
  for (final (i, line) in body.indexed) {
    if (line.fenced) continue;
    if (headingItemTextOf(line.text) case final text?) {
      headings.add(_Start(index: i, text: text));
    } else if (_listMarker.firstMatch(line.text) case final marker?) {
      listItems.add(_Start(index: i, text: line.text.substring(marker.end)));
    }
  }
  if (headings.isNotEmpty) return headings;
  final listLines = {for (final start in listItems) start.index};
  return [
    ...listItems,
    for (final row in _tableRowStartsOf(body, items))
      if (!listLines.contains(row.index)) row,
  ]..sort((a, b) => a.index - b.index);
}

/// Returns the table rows among [items], the items of [body] as the index
/// reads them, a quoted row aside.
List<_Start> _tableRowStartsOf(List<BodyLine> body, List<SectionItem> items) {
  final indexOfLine = {for (final (i, line) in body.indexed) line.line: i};
  return [
    for (final item in items)
      if (item.kind == SectionItemKind.tableRow)
        if (indexOfLine[item.line] case final index?)
          if (!body[index].text.trimLeft().startsWith('>'))
            _Start(index: index, text: item.head),
  ];
}
