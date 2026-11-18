import 'dart:collection';

import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_links.dart';
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/index_query/link_places.dart';
import 'package:specstone_core/src/index_query/models/cited_by.dart';
import 'package:specstone_core/src/index_query/models/cited_item.dart';
import 'package:specstone_core/src/index_query/models/cited_place.dart';
import 'package:specstone_core/src/index_query/models/cited_section.dart';
import 'package:specstone_core/src/index_query/models/classified_link.dart';
import 'package:specstone_core/src/index_query/models/item_range.dart';
import 'package:specstone_core/src/index_query/models/line_range.dart';
import 'package:specstone_core/src/index_query/models/link_cite.dart';
import 'package:specstone_core/src/index_query/models/link_text.dart';
import 'package:specstone_core/src/index_query/read_answer.dart'
    show nameWithType;
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';

/// The lines that cite each [CitedPlace].
///
/// [inline] says where a bundle prints them: right after their place when
/// true, or as parts of their own ([citedByPartBlock]) when false.
final class CitedByIndex extends MapView<CitedPlace, List<CitedBy>> {
  new(super.map, {required this.inline});

  /// Whether the lines print right after their place.
  final bool inline;

  /// Returns this index less each line whose citer's DocPath is in [from] on a
  /// place of a doc whose DocPath is in [into]; a place left bare is dropped.
  CitedByIndex withoutLinks({
    required Set<String> from,
    required Set<String> into,
  }) {
    final kept = <CitedPlace, List<CitedBy>>{};
    for (final MapEntry(key: place, value: lines) in entries) {
      if (!into.contains(place.docPath)) {
        kept[place] = lines;
        continue;
      }
      final rest = [
        for (final by in lines)
          if (!from.contains(by.docPath)) by,
      ];
      if (rest.isNotEmpty) kept[place] = rest;
    }
    return CitedByIndex(kept, inline: inline);
  }
}

/// Returns who cites each place, from the lines the index stores.
///
/// The lines are those [scanCitedBy] gives for the docs the index held when it
/// last wrote a doc. See [CitedByIndex.inline] for [inline].
CitedByIndex citedByIndex(DocIndex index, {bool inline = true}) =>
    CitedByIndex(_citedLinksOf[index] ??= index.citedLines(), inline: inline);

/// The cited-by lines of each index, read on first use: an index is one read
/// snapshot, so `check`'s many bundles of one run share one read.
final _citedLinksOf = Expando<Map<CitedPlace, List<CitedBy>>>();

/// Returns who cites each place, read from the links of [docs], the docs in
/// tree order, whose content [contentOf] gives and whose doc types [set] holds.
///
/// One line per link from a typed doc other than the cited doc's own, an item
/// range giving one to each item it spans, in tree order of the citing docs
/// and then line order. A place of a doc whose type's `bundle:` list holds
/// `design` has none, since that doc prints in every design bundle.
/// [classifyLink] reads each link, so it cites a place here exactly when
/// `check` and the follow read it so: an item, a `###` block, a section, or
/// the whole doc, which an anchor no section or block places also names. A
/// link whose anchor matches nothing cites none.
Map<CitedPlace, List<CitedBy>> scanCitedBy(
  List<IndexedDoc> docs, {
  required MergedSet set,
  required DocContent Function(IndexedDoc doc) contentOf,
}) {
  final byPath = {for (final doc in docs) doc.docPath: doc};
  final read = <String, _Doc>{};
  _Doc? readerOf(IndexedDoc doc) {
    final typeId = doc.docTypeId;
    if (typeId == null) return null;
    return read[doc.docPath] ??= _Doc(
      doc,
      typeId,
      contentOf(doc),
      set.lookup(typeId),
    );
  }

  final cited = <CitedPlace, List<CitedBy>>{};
  for (final source in docs) {
    final reader = readerOf(source);
    if (reader == null) continue;
    for (final line in reader.linkLines) {
      for (final place in _citesOn(byPath, reader, line, readerOf)) {
        (cited[place] ??= []).add(
          CitedBy(
            docPath: source.docPath,
            name: source.name,
            docType: reader.docTypeId,
            byItem: reader.itemHolding(line),
            line: reader.lineText(line).trim(),
          ),
        );
      }
    }
  }
  return cited;
}

/// Returns `  · cited by <name> (<doc type>) <item ID>: <line>` for [by], the
/// item ID `—` when it has none.
String citedByLineOf(CitedBy by) =>
    '  · cited by ${by.name} (${by.docType}) ${by.byItem ?? '—'}: ${by.line}';

/// Returns the items and `###` blocks of the section [at] of [doc], whose held
/// sections [section] reads, that [cited] holds lines for and whose lines lie
/// in [within] (the whole section when null), in the order their lines print.
///
/// [extents] is the extent of each item of the section as [itemExtentsOf]
/// gives it; a caller that reads the section often passes the one it holds,
/// and without it the section is read once, when it first needs an extent.
List<CitedItem> citedItemsIn(
  CitedByIndex cited,
  IndexedDoc doc,
  DocContent content,
  CitedSection section,
  int at, {
  LineRange? within,
  Map<String, LineRange>? extents,
}) {
  var extentOf = extents;
  final found = <({String id, LineRange extent, List<CitedBy> by})>[];
  final ids = <String>{};
  for (final fact in content.itemFacts.sectionItems[at]) {
    final id = fact.id;
    final by = id == null
        ? null
        : cited[CitedPlace(
            docPath: doc.docPath,
            kind: CitedKind.item,
            key: id,
          )];
    if (id == null || by == null || !ids.add(id)) continue;
    extentOf ??= itemExtentsOf(
      sectionBodyLines(content.sections, content.lineFacts, at),
      prefixId: section.prefixId,
      isAcceptanceCriteria: section.isAcceptanceCriteria,
    );
    final extent = extentOf[id];
    if (extent == null) continue;
    if (within != null &&
        (extent.first < within.first || within.last < extent.last)) {
      continue;
    }
    found.add((id: id, extent: extent, by: by));
  }
  for (final _Block(:anchor, :line) in _blocksIn(content.lineFacts, at)) {
    final by =
        cited[CitedPlace(
          docPath: doc.docPath,
          kind: CitedKind.item,
          key: anchor,
        )];
    if (by == null) continue;
    if (within != null && (line < within.first || within.last < line)) {
      continue;
    }
    found.add((id: anchor, extent: LineRange(first: line, last: line), by: by));
  }
  // An item nested in another ends no later than it, so it prints first.
  found.sort((a, b) {
    final byEnd = a.extent.last.compareTo(b.extent.last);
    return byEnd != 0 ? byEnd : b.extent.first.compareTo(a.extent.first);
  });
  return [
    for (final (:id, :extent, :by) in found)
      CitedItem(
        kind: CitedKind.item,
        item: id,
        sectionKey: section.key,
        after: extent.last,
        by: by,
      ),
  ];
}

/// Returns the entry of the section [at] of [doc], whose held sections
/// [section] reads, that [cited] holds lines for, its lines after the
/// section's header line; null when none.
CitedItem? citedSectionIn(
  CitedByIndex cited,
  IndexedDoc doc,
  DocContent content,
  CitedSection section,
  int at,
) {
  final by =
      cited[CitedPlace(
        docPath: doc.docPath,
        kind: CitedKind.section,
        key: section.key,
      )];
  if (by == null) return null;
  return CitedItem(
    kind: CitedKind.section,
    item: null,
    sectionKey: section.key,
    after: content.lineFacts.sectionLines[at],
    by: by,
  );
}

/// Returns the entry of the whole [doc] that [cited] holds lines for, its
/// lines after the doc's naming line; null when none.
CitedItem? citedDocIn(CitedByIndex cited, IndexedDoc doc) {
  final by =
      cited[CitedPlace(docPath: doc.docPath, kind: CitedKind.doc, key: null)];
  if (by == null) return null;
  return CitedItem(
    kind: CitedKind.doc,
    item: null,
    sectionKey: null,
    after: 0,
    by: by,
  );
}

/// A `###` heading of a section: the anchor a link names it by, and its file
/// line.
final class _Block {
  const new({required this.anchor, required this.line});

  final String anchor;
  final int line;
}

/// Returns the `###` headings inside the section [at] of [facts], each by the
/// anchor a link names it by, first of a repeated anchor only, as
/// [anchorTargetOf] reads it.
List<_Block> _blocksIn(LineFacts facts, int at) {
  final anchors = facts.anchors;
  final lines = facts.headingLines;
  if (anchors == null || lines == null) return const [];
  final starts = facts.sectionLines;
  final end = at + 1 < starts.length ? starts[at + 1] : null;
  final blocks = <_Block>[];
  for (final (i, anchor) in anchors.headingSlugs.indexed) {
    if (i >= lines.length) break;
    final line = lines[i];
    if (line <= starts[at] || (end != null && line >= end)) continue;
    final target = anchorTargetOf(facts, anchor);
    if (target is HeadingBlockTarget && target.headingLine == line) {
      blocks.add(_Block(anchor: anchor, line: line));
    }
  }
  return blocks;
}

/// Returns the lines of [items] by the file line each prints after; items
/// that end on one line, nested, keep every line in [items] order. A doc's
/// lines come under line 0, and a section's under its header's line.
///
/// None when [cited] prints its lines as parts ([CitedByIndex.inline]).
Map<int, List<String>> citedLinesAfter(
  CitedByIndex? cited,
  List<CitedItem> items,
) {
  final after = <int, List<String>>{};
  if (cited?.inline == false) return after;
  for (final item in items) {
    (after[item.after] ??= []).addAll([
      for (final by in item.by) citedByLineOf(by),
    ]);
  }
  return after;
}

/// Returns the part that holds the cited-by lines of [item] of [doc]: its
/// naming line, then one line per citing link.
///
/// The naming line names the item's doc, its `#<section key>`, and its
/// `item <ID>` for an item or block, the `#<section key>` alone for a
/// section, and the doc alone for a whole doc, then ends ` · cited by <==`.
String citedByPartBlock(IndexedDoc doc, CitedItem item) {
  final place = switch (item.kind) {
    CitedKind.item => '${doc.docPath}#${item.sectionKey} · item ${item.item}',
    CitedKind.section => '${doc.docPath}#${item.sectionKey}',
    CitedKind.doc => doc.docPath,
  };
  return '==> ${nameWithType(doc)} · $place · cited by <==\n'
      '${[for (final by in item.by) citedByLineOf(by)].join('\n')}';
}

/// Returns the closing-list name of the part [citedByPartBlock] gives for
/// [item] of [doc], `<name> (<doc type>) · cited by`, then ` [<ID>]` for an
/// item or block and ` [#<section key>]` for a section.
String citedByListName(IndexedDoc doc, CitedItem item) {
  final mark = switch (item.kind) {
    CitedKind.item => ' [${item.item}]',
    CitedKind.section => ' [#${item.sectionKey}]',
    CitedKind.doc => '',
  };
  return '${nameWithType(doc)} · cited by$mark';
}

/// Returns [items] as the `citedBy` objects of `--json`, one per line: the
/// place's `kind`, its `item`, and its `section` (the key of a section entry,
/// else null) ahead of the line's own keys.
List<Map<String, Object?>> citedByJson(List<CitedItem> items) => [
  for (final item in items)
    for (final by in item.by)
      {
        'kind': item.kind.name,
        'item': item.item,
        'section': item.kind == CitedKind.section ? item.sectionKey : null,
        'name': by.name,
        'docType': by.docType,
        'byItem': by.byItem,
        'line': by.line,
      },
];

/// Returns each place the links of file [line] of [reader] name, a range
/// naming each item it spans once, in source order.
///
/// A range's last link adds nothing of its own, since the range names its
/// item; every other link adds its own, even when two name one place.
List<CitedPlace> _citesOn(
  Map<String, IndexedDoc> byPath,
  _Doc reader,
  int line,
  _Doc? Function(IndexedDoc doc) read,
) {
  final classified = <({LinkText link, LinkCite cite, _Doc target, int? at})>[];
  for (final link in reader.linksOn(line)) {
    final doc = byPath[link.target];
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
      ClassifiedLink(link: link, cite: cite),
  ]);
  final rangeFrom = {for (final range in ranges) range.first.link: range};
  final rangeEnds = {for (final range in ranges) range.last.link};
  final spanned = <CitedPlace>{};
  final found = <CitedPlace>[];
  for (final (:link, :cite, :target, :at) in classified) {
    final docPath = target.doc.docPath;
    if (_joinsDesign(target.type)) continue;
    CitedPlace place(CitedKind kind, String? key) =>
        CitedPlace(docPath: docPath, kind: kind, key: key);
    switch (cite) {
      case ItemCite():
        final range = rangeFrom[link];
        if (range == null && rangeEnds.contains(link)) continue;
        if (range != null && !rangeEnds.contains(link)) spanned.clear();
        for (final id in _idsOf(range, cite, target, at)) {
          final item = place(CitedKind.item, id);
          if (range == null || spanned.add(item)) found.add(item);
        }
      case SectionCite(:final sectionKey):
        found.add(place(CitedKind.section, sectionKey));
      case HeadingBlockCite():
        found.add(place(CitedKind.item, link.anchor));
      case DocCite() || OtherAnchorCite():
        found.add(place(CitedKind.doc, null));
      case UnresolvedCite():
        break;
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

/// An item of a section by its ID, with the file lines it spans.
final class _ItemExtent {
  const new({required this.id, required this.extent});

  final String id;
  final LineRange extent;
}

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
  final _extents = <int, List<_ItemExtent>>{};

  LineFacts get facts => content.lineFacts;

  CitedSection? sectionAt(int at) =>
      at < _sections.length ? _sections[at] : null;

  late final Map<int, List<LinkText>> _linksByLine = _linksByLineOf(facts);

  /// The file lines that start a link to another doc, in order, each once.
  Iterable<int> get linkLines => _linksByLine.keys;

  /// Returns the links to other docs of file line [line], in source order.
  List<LinkText> linksOn(int line) => _linksByLine[line] ?? const [];

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
    for (final _ItemExtent(:id, :extent) in _extentsAt(at)) {
      final size = extent.last - extent.first;
      if (extent.first <= line && line <= extent.last && size < span) {
        holding = id;
        span = size;
      }
    }
    return holding;
  }

  List<_ItemExtent> _extentsAt(int at) => _extents[at] ??= _extentsOf(at);

  List<_ItemExtent> _extentsOf(int at) {
    final section = sectionAt(at);
    if (section == null) return const [];
    final extents = itemExtentsOf(
      sectionBodyLines(content.sections, facts, at),
      prefixId: section.prefixId,
      isAcceptanceCriteria: section.isAcceptanceCriteria,
    );
    return [
      for (final fact in content.itemFacts.sectionItems[at])
        if (fact.id case final id?)
          if (extents[id] case final extent?)
            _ItemExtent(id: id, extent: extent),
    ];
  }
}

/// Returns the links to other docs of [facts] by file line, each in source
/// order with the [LinkText] the index stored for it, or a text-free one that
/// reads as no item ID.
///
/// A stored text joins the nth link of its line, destination as written, and
/// anchor, so each link is read once; a link with no text, whose own text
/// reads as no item ID, is a section, block, or doc link.
Map<int, List<LinkText>> _linksByLineOf(LineFacts facts) {
  final places = facts.links;
  final stored = storedLinkTextsOf(places, facts.linkTexts);
  final byLine = <int, List<LinkText>>{};
  for (final (i, place) in places.indexed) {
    (byLine[place.line] ??= []).add(stored[i] ?? textFreeLinkOf(place));
  }
  return byLine;
}
