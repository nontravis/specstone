import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/scenario_blocks.dart';
import 'package:specstone_core/src/doc_model/markdown_lines.dart'
    show itemHeadingMarker;
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

const _notApplicable = 'N/A';
const _itemIdForm = 'item_id';
// Unlike doc_items, an item that carries an ID starts at a top-level marker
// with text after it.
final _listMarker = RegExp(r'^(?:[-*+]|\d+[.)])\s+');

/// One item of a doc, or one story scenario heading, in document order.
///
/// `line` and `endLine` are the 1-based first and last non-blank file lines
/// of the item, nested lines and fenced code included.
typedef IdAt = ({
  String sectionKey,
  String prefix,
  int line,
  int endLine,
  IdRead? id,
});

typedef _Start = ({int index, String text});

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
        ),
  ];
}

/// Returns the ID findings of a typed [doc]; an untyped doc has none.
///
/// A held section whose template writes a `prefix_id` holds items: the `###`
/// headings when it has any, else its top-level list entries, fenced code
/// excluded and `N/A` entries skipped. An item with no ID of that prefix
/// holds an `item_id_missing`; one repeating an ID already held in the doc,
/// or a scenario repeating a number's value, holds an `item_id_duplicate`;
/// one whose digits a letter follows, as does a story scenario heading,
/// holds an `item_id_lettered` naming the next free number.
Iterable<Finding> checkItemIds(CheckContext context, IndexedDoc doc) sync* {
  final type = context.typeOf(doc);
  if (type == null) return;
  final items = idsInDoc(context.contentOf(doc), type);
  final reads = [for (final item in items) ?item.id];
  final next = nextFreeIds(reads);
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
      yield _lettered(context, doc, item, id, next[index]!);
    } else {
      final held = _heldKeyOf(item, id);
      final first = seen[held];
      if (first == null) {
        seen[held] = item.line;
      } else {
        yield _duplicate(context, doc, item, id, first);
      }
    }
  }
}

// A scenario is held by its number's value, so `Scenario 01` repeats
// `Scenario 1` (W9); an item ID by its text as written.
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

Finding _lettered(
  CheckContext context,
  IndexedDoc doc,
  IdAt item,
  IdRead id,
  String next,
) => context.finding(
  doc,
  FindingKind.itemIdLettered,
  line: item.line,
  message: '${id.written} has a letter after its number; use $next',
  keys: {'id': id.written, 'section': item.sectionKey, 'next': next},
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

List<IdAt> _idsOfSection(MergedSection template, List<BodyLine> body) => [
  if (template.prefixId case final prefix?)
    ..._itemIds(template.id, prefix, body),
  if (template.id == acceptanceSectionId) ..._scenarioIds(template.id, body),
];

List<IdAt> _itemIds(String sectionKey, String prefix, List<BodyLine> body) {
  final starts = _itemStartsOf(body);
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
      if (!line.fenced && isSubHeading(line.text)) i,
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
  return (
    sectionKey: sectionKey,
    prefix: prefix,
    line: body[index].line,
    endLine: body[last].line,
    id: id,
  );
}

/// Returns the item starts of [body], marker stripped: the `###` headings
/// when it has any, else its top-level list items; fenced lines are no start.
List<_Start> _itemStartsOf(List<BodyLine> body) {
  final headings = <_Start>[];
  final listItems = <_Start>[];
  for (final (i, line) in body.indexed) {
    if (line.fenced) continue;
    if (line.text.startsWith(itemHeadingMarker)) {
      headings.add((
        index: i,
        text: line.text.substring(itemHeadingMarker.length),
      ));
    } else if (_listMarker.firstMatch(line.text) case final marker?) {
      listItems.add((index: i, text: line.text.substring(marker.end)));
    }
  }
  return headings.isNotEmpty ? headings : listItems;
}
