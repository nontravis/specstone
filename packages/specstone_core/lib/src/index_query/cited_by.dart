import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_links.dart';
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/index_query/link_places.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// One item link to an item, from the citing doc's `name` and `docType`: the
/// ID of its item whose lines hold the link, null when none does, and the
/// trimmed `line` that holds the link.
typedef CitedBy = ({String name, String docType, String? byItem, String line});

/// The lines that cite each item, by the cited item's DocPath and ID.
typedef CitedByIndex = Map<({String docPath, String itemId}), List<CitedBy>>;

/// An item a bundle prints whole, whose `by` lines print right after file
/// line `after` of its doc.
typedef CitedItem = ({String item, int after, List<CitedBy> by});

/// Returns who cites each item, from the links the index stores
/// (`index_query/get_task_bundle/show_cited_by`).
///
/// One line per item link from a typed doc other than the item's own, an item
/// range giving one to each item it spans, in tree order of the citing docs
/// and then line order. An item of a doc whose type's `bundle:` list holds
/// `design` has none, since that doc prints in every design bundle.
/// [classifyLink] reads each link, so it is an item link here exactly when
/// `check` and the follow read it as one.
CitedByIndex citedByIndex(DocIndex index) {
  final docs = <String, _Doc>{};
  _Doc? read(IndexedDoc doc) {
    final typeId = doc.docTypeId;
    if (typeId == null) return null;
    return docs[doc.docPath] ??= _Doc(
      doc,
      typeId,
      index.contentOf(doc),
      index.typeOf(doc),
    );
  }

  final cited = <({String docPath, String itemId}), List<CitedBy>>{};
  for (final source in index.docs) {
    final reader = read(source);
    if (reader == null) continue;
    for (final line in reader.linkLines) {
      for (final (:doc, :itemId) in _itemLinksOn(index, reader, line, read)) {
        (cited[(docPath: doc, itemId: itemId)] ??= []).add((
          name: source.name,
          docType: reader.docTypeId,
          byItem: reader.itemHolding(line),
          line: reader.lineText(line).trim(),
        ));
      }
    }
  }
  return cited;
}

/// Returns `  · cited by <name> (<doc type>) <item ID>: <line>` for [by], the
/// item ID `—` when it has none.
String citedByLineOf(CitedBy by) =>
    '  · cited by ${by.name} (${by.docType}) ${by.byItem ?? '—'}: ${by.line}';

/// Returns the items of the section [at] of [doc], whose held sections
/// [section] reads, that [cited] holds lines for and whose lines lie in
/// [within] (the whole section when null), in the order their lines print.
List<CitedItem> citedItemsIn(
  CitedByIndex cited,
  IndexedDoc doc,
  DocContent content,
  CitedSection section,
  int at, {
  LineRange? within,
}) {
  final body = sectionBodyLines(content.sections, content.lineFacts, at);
  final found = <({String item, LineRange extent, List<CitedBy> by})>[];
  final ids = <String>{};
  for (final fact in content.itemFacts.sectionItems[at]) {
    final id = fact.id;
    final by = id == null ? null : cited[(docPath: doc.docPath, itemId: id)];
    if (id == null || by == null || !ids.add(id)) continue;
    final extent = itemExtentOf(
      body,
      id,
      prefixId: section.prefixId,
      isAcceptanceCriteria: section.isAcceptanceCriteria,
    );
    if (extent == null) continue;
    if (within != null &&
        (extent.first < within.first || within.last < extent.last)) {
      continue;
    }
    found.add((item: id, extent: extent, by: by));
  }
  // An item nested in another ends no later than it, so it prints first.
  found.sort((a, b) {
    final byEnd = a.extent.last.compareTo(b.extent.last);
    return byEnd != 0 ? byEnd : b.extent.first.compareTo(a.extent.first);
  });
  return [
    for (final (:item, :extent, :by) in found)
      (item: item, after: extent.last, by: by),
  ];
}

/// Returns the lines of [items] by the file line each prints after; items
/// that end on one line, nested, keep every line in [items] order.
Map<int, List<String>> citedLinesAfter(List<CitedItem> items) {
  final after = <int, List<String>>{};
  for (final item in items) {
    (after[item.after] ??= []).addAll([
      for (final by in item.by) citedByLineOf(by),
    ]);
  }
  return after;
}

/// Returns [items] as the `citedBy` objects of `--json`, one per line.
List<Map<String, Object?>> citedByJson(List<CitedItem> items) => [
  for (final item in items)
    for (final by in item.by)
      {
        'item': item.item,
        'name': by.name,
        'docType': by.docType,
        'byItem': by.byItem,
        'line': by.line,
      },
];

/// An item a link of one line names: the item `itemId` of the doc `doc`.
typedef _ItemLink = ({String doc, String itemId});

/// Returns each item the item links of file [line] of [reader] name, a range
/// naming each item it spans once, in source order.
///
/// A range's last link adds nothing of its own, since the range names its
/// item; every other link adds its own, even when two name one item.
List<_ItemLink> _itemLinksOn(
  DocIndex index,
  _Doc reader,
  int line,
  _Doc? Function(IndexedDoc doc) read,
) {
  final classified = <({LinkText link, LinkCite cite, _Doc target, int? at})>[];
  for (final link in reader.linksOn(line)) {
    final doc = index.at(link.target);
    final target = doc == null ? null : read(doc);
    if (target == null) continue;
    final anchor = link.anchor;
    final to = anchor == null || anchor.isEmpty
        ? null
        : anchorTargetOf(target.facts, anchor);
    classified.add((
      link: link,
      cite: classifyLink(link, target: to, sectionAt: target.sectionAt),
      target: target,
      at: to is SectionTarget ? to.sectionIndex : null,
    ));
  }
  final ranges = itemRangesOn(reader.lineText(line), [
    for (final (:link, :cite, target: _, at: _) in classified)
      (link: link, cite: cite),
  ]);
  final rangeFrom = {for (final range in ranges) range.first.link: range};
  final rangeEnds = {for (final range in ranges) range.last.link};
  final spanned = <_ItemLink>{};
  final found = <_ItemLink>[];
  for (final (:link, :cite, :target, :at) in classified) {
    if (cite is! ItemCite ||
        target.doc.docPath == reader.doc.docPath ||
        _joinsDesign(target.type)) {
      continue;
    }
    final range = rangeFrom[link];
    if (range == null && rangeEnds.contains(link)) continue;
    for (final id in _idsOf(range, cite, target, at)) {
      final item = (doc: target.doc.docPath, itemId: id);
      if (range == null || spanned.add(item)) found.add(item);
    }
  }
  return found;
}

List<String> _idsOf(ItemRange? range, ItemCite cite, _Doc target, int? at) {
  final section = at == null ? null : target.sectionAt(at);
  if (range == null || at == null || section == null) return [cite.itemId];
  return itemIdsInRange(
    range,
    section,
    target.content.itemFacts.sectionItems[at],
  );
}

/// Whether a doc of [type] joins every design bundle through `bundle:`.
bool _joinsDesign(MergedDocType? type) =>
    type?.bundle?.contains(BundleMode.design.wire) ?? false;

/// One typed doc as the lines read it: its stored content, its held sections
/// as [classifyLink] reads them, and its text by line.
final class _Doc {
  new(this.doc, this.docTypeId, this.content, this.type)
    : _sections = citedSectionsOf(content, type);

  final IndexedDoc doc;
  final String docTypeId;
  final DocContent content;
  final MergedDocType? type;
  final List<CitedSection> _sections;

  late final List<String> _lines = content.text.split('\n');
  final _extents = <int, List<({String id, LineRange extent})>>{};

  LineFacts get facts => content.lineFacts;

  CitedSection? sectionAt(int at) =>
      at < _sections.length ? _sections[at] : null;

  /// The file lines that start a link whose text reads as an item ID, in
  /// order, each once.
  Iterable<int> get linkLines => {
    for (final link in facts.linkTexts) link.line,
  };

  /// Returns the links of file line [line] whose text reads as an item ID,
  /// in source order.
  Iterable<LinkText> linksOn(int line) =>
      facts.linkTexts.where((link) => link.line == line);

  /// Returns file line [line] of the stored text, without its line ending.
  String lineText(int line) {
    final text = _lines[line - 1];
    return text.endsWith('\r') ? text.substring(0, text.length - 1) : text;
  }

  /// Returns the ID of the item whose lines hold file line [line], the
  /// innermost when items nest, or null when none does.
  String? itemHolding(int line) {
    final starts = facts.sectionLines;
    final at = starts.lastIndexWhere((start) => start < line);
    if (at < 0) return null;
    String? holding;
    var span = 0x7fffffff;
    for (final (:id, :extent) in _extentsAt(at)) {
      final size = extent.last - extent.first;
      if (extent.first <= line && line <= extent.last && size < span) {
        holding = id;
        span = size;
      }
    }
    return holding;
  }

  List<({String id, LineRange extent})> _extentsAt(int at) =>
      _extents[at] ??= _extentsOf(at);

  List<({String id, LineRange extent})> _extentsOf(int at) {
    final section = sectionAt(at);
    if (section == null) return const [];
    final body = sectionBodyLines(content.sections, facts, at);
    return [
      for (final fact in content.itemFacts.sectionItems[at])
        if (fact.id case final id?)
          if (itemExtentOf(
                body,
                id,
                prefixId: section.prefixId,
                isAcceptanceCriteria: section.isAcceptanceCriteria,
              )
              case final extent?)
            (id: id, extent: extent),
    ];
  }
}
