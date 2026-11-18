import 'package:specstone_core/src/doc_model/doc.dart' show Doc;
import 'package:specstone_core/src/doc_model/doc_items.dart'
    show SectionItem, SectionItemKind;
import 'package:specstone_core/src/doc_model/markdown_lines.dart'
    show startsTable;
import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_facts.dart'
    show generatedLineTest, leadBodyLinesOf, leadItemsAt, sectionItemsAt;
import 'package:specstone_core/src/index_query/item_links.dart';
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/index_query/link_places.dart';
import 'package:specstone_core/src/index_query/models/ancestor_piece.dart';
import 'package:specstone_core/src/rendering/line_ending.dart' show toLf;
import 'package:specstone_core/src/templates/merged_doc_type.dart';

// MARK: - Pieces

/// Returns the pieces of each ancestor spec doc of [bundle] that link to or
/// from its target subtree, cut from the stored text with no file read.
///
/// A piece inside another is left out; one reached both ways is outbound.
/// Pieces come in the docs' print order, then by file line.
List<AncestorPiece> ancestorPiecesOf(DocIndex index, Bundle bundle) {
  final targets = bundle.targetSubtreePaths;
  final ancestors = bundle.ancestorSpecPaths.difference(targets);
  if (ancestors.isEmpty) return const [];
  final views = _viewsOf[index] ??= _Views(index);
  final candidates = <String, List<AncestorPiece>>{};
  for (final doc in index.docs) {
    final found = [
      if (targets.contains(doc.docPath))
        ..._outboundFrom(views, doc, ancestors),
      if (ancestors.contains(doc.docPath))
        ..._inboundTo(views.of(doc), targets),
    ];
    for (final piece in found) {
      (candidates[piece.doc.docPath] ??= []).add(piece);
    }
  }
  return [
    for (final doc in bundle.printOrder(index))
      ..._outermost(candidates[doc.docPath] ?? const []),
  ];
}

/// Returns [candidates] of one doc by file line, each piece that lies inside
/// another left out.
///
/// An outer piece sorts before what it holds; of two pieces on the same lines
/// the outbound one comes first and is kept.
List<AncestorPiece> _outermost(List<AncestorPiece> candidates) {
  final sorted = [...candidates]..sort(_byPlace);
  final kept = <AncestorPiece>[];
  for (final piece in sorted) {
    final isInside = kept.any(
      (outer) => outer.first <= piece.first && piece.last <= outer.last,
    );
    if (!isInside) kept.add(piece);
  }
  return kept;
}

int _byPlace(AncestorPiece a, AncestorPiece b) {
  final byFirst = a.first.compareTo(b.first);
  if (byFirst != 0) return byFirst;
  final byLast = b.last.compareTo(a.last);
  if (byLast != 0) return byLast;
  final byDirection = a.direction.index.compareTo(b.direction.index);
  if (byDirection != 0) return byDirection;
  final byItem = (a.itemId ?? '').compareTo(b.itemId ?? '');
  return byItem != 0 ? byItem : (a.heading ?? '').compareTo(b.heading ?? '');
}

// MARK: - Outbound

/// A link of a target-subtree doc into an ancestor spec doc, with what it
/// cites there.
final class _Cited {
  const new({
    required this.view,
    required this.link,
    required this.cite,
    required this.sectionIndex,
  });

  final _View view;
  final LinkText link;
  final LinkCite cite;

  /// The index of the `##` section the link's anchor names, else null.
  final int? sectionIndex;
}

_Cited _citedOf(_View view, LinkText link) {
  final anchor = link.anchor;
  final target = anchor == null || anchor.isEmpty
      ? null
      : anchorTargetOf(view.facts, anchor);
  return _Cited(
    view: view,
    link: link,
    cite: classifyLink(link, target: target, sectionAt: view.sectionAt),
    sectionIndex: target is SectionTarget ? target.sectionIndex : null,
  );
}

/// Returns the outbound pieces of the links of [source] into [ancestors].
List<AncestorPiece> _outboundFrom(
  _Views views,
  IndexedDoc source,
  Set<String> ancestors,
) {
  final from = views.of(source);
  final onLine = <int, List<_Cited>>{};
  for (final link in from.links) {
    final doc = views.index.at(link.target);
    if (doc == null || !ancestors.contains(doc.docPath)) continue;
    (onLine[link.line] ??= []).add(_citedOf(views.of(doc), link));
  }
  return [
    for (final MapEntry(key: line, value: cited) in onLine.entries)
      ..._outboundOnLine(from.lines[line - 1], cited),
  ];
}

/// Returns the pieces [cited], the links of one line [text], cite; an item
/// range gives each item of the range a piece of its own.
List<AncestorPiece> _outboundOnLine(String text, List<_Cited> cited) {
  final itemLinks = <ItemLink>[
    for (final one in cited)
      if (one.cite case final ItemCite item) (link: one.link, cite: item),
  ]..sort((a, b) => a.link.column.compareTo(b.link.column));
  final rangeFrom = {
    for (final range in itemRangesOn(text, itemLinks)) range.first.link: range,
  };
  return [for (final one in cited) ..._outboundOf(one, rangeFrom[one.link])];
}

List<AncestorPiece> _outboundOf(_Cited cited, ItemRange? range) {
  const direction = PieceDirection.outbound;
  final _Cited(:view, :cite, :sectionIndex, :link) = cited;
  return switch (cite) {
    ItemCite(:final itemId) when sectionIndex != null => [
      for (final id in _idsOf(view, sectionIndex, itemId, range))
        ?view.itemPiece(sectionIndex, id, direction),
    ],
    SectionCite() when sectionIndex != null => [
      ?view.sectionPiece(sectionIndex, direction),
    ],
    HeadingBlockCite(:final headingLine) => [
      ?view.blockPiece(headingLine, link.anchor, direction),
    ],
    _ => const [],
  };
}

List<String> _idsOf(_View view, int at, String itemId, ItemRange? range) {
  final section = view.sectionAt(at);
  if (range == null || section == null) return [itemId];
  return itemIdsInRange(
    range,
    section,
    view.content.itemFacts.sectionItems[at],
  );
}

// MARK: - Inbound

/// Returns the inbound pieces of the links of [ancestor] into [targets].
List<AncestorPiece> _inboundTo(_View ancestor, Set<String> targets) => [
  for (final link in ancestor.links)
    if (targets.contains(link.target)) ?ancestor.inboundPieceAt(link.line),
];

// MARK: - Doc view

/// An item that holds an ID, with the file lines it spans.
final class _IdExtent {
  const new({required this.id, required this.extent});

  final String id;
  final LineRange extent;

  int get span => extent.last - extent.first;
}

/// The doc views of each index, built on first use: an index is one read
/// snapshot, so a doc that many bundles of one `check` run read is opened, and
/// its item extents found, once.
final _viewsOf = Expando<_Views>();

/// The docs the pieces read, each opened once.
final class _Views {
  new(this.index);

  final DocIndex index;
  final _byPath = <String, _View>{};

  _View of(IndexedDoc doc) => _byPath[doc.docPath] ??= _View(
    doc,
    index.contentOf(doc),
    index.typeOf(doc),
  );
}

/// One doc as the pieces read it: its stored content, its held sections as
/// [classifyLink] reads them, its links, and its text by line.
final class _View {
  new(this.doc, this.content, this.type)
    : held = citedSectionsOf(content, type);

  final IndexedDoc doc;
  final DocContent content;
  final MergedDocType? type;
  final List<CitedSection> held;

  /// The file's lines, line endings left out.
  late final List<String> lines = toLf(content.text).split('\n');

  /// The links to other docs, in source order.
  late final List<LinkText> links = _linkTextsOf(content.lineFacts);

  final _items = <int, List<SectionItem>>{};
  final _idExtents = <int, List<_IdExtent>>{};

  LineFacts get facts => content.lineFacts;

  CitedSection? sectionAt(int at) => at < held.length ? held[at] : null;

  List<BodyLine> _bodyOf(int at) =>
      sectionBodyLines(content.sections, facts, at);

  /// Returns the piece of the item [id] of the section [at], or null when the
  /// section holds no such item.
  AncestorPiece? itemPiece(int at, String id, PieceDirection direction) {
    final section = sectionAt(at);
    if (section == null) return null;
    final extent = itemExtentOf(
      _bodyOf(at),
      id,
      prefixId: section.prefixId,
      isAcceptanceCriteria: section.isAcceptanceCriteria,
    );
    return extent == null
        ? null
        : _piece(section.key, direction, extent, itemId: id);
  }

  /// Returns the piece of the whole section [at], its header line first.
  AncestorPiece? sectionPiece(int at, PieceDirection direction) {
    final section = sectionAt(at);
    if (section == null) return null;
    final starts = facts.sectionLines;
    var last = at + 1 < starts.length ? starts[at + 1] - 1 : lines.length;
    while (last > starts[at] && lines[last - 1].trim().isEmpty) {
      last--;
    }
    return _piece(section.key, direction, (first: starts[at], last: last));
  }

  /// Returns the piece of the `###` block at [headingLine], named by its item
  /// ID when it starts an item, else by [anchor] or, with none, its own slug.
  AncestorPiece? blockPiece(
    int headingLine,
    String? anchor,
    PieceDirection direction,
  ) {
    final at = _sectionHolding(headingLine);
    final section = at == null ? null : sectionAt(at);
    if (at == null || section == null) return null;
    final extent = headingBlockExtentOf(_bodyOf(at), headingLine);
    if (extent == null) return null;
    final id = _idExtentsAt(at)
        .where((item) => item.extent.first == headingLine)
        .firstOrNull
        ?.id;
    return _piece(
      section.key,
      direction,
      extent,
      itemId: id,
      heading: id == null ? anchor ?? _slugAt(headingLine) : null,
    );
  }

  /// Returns the inbound piece that holds file line [line]: the ID item with
  /// its nested items; else the `###` block; else the table row, the list
  /// item, or the paragraph. A line of the lead gives the list item or the
  /// paragraph, with an empty section key. Null when none holds it.
  AncestorPiece? inboundPieceAt(int line) {
    if (facts.sectionLines.contains(line)) return null;
    final at = _sectionHolding(line);
    if (at == null) return _leadPieceAt(line);
    final section = sectionAt(at);
    if (section == null) return null;
    const direction = PieceDirection.inbound;
    if (_idItemHolding(at, line) case final item?) {
      return _piece(section.key, direction, item.extent, itemId: item.id);
    }
    if (_blockHeadingHolding(at, line) case final headingLine?) {
      return blockPiece(headingLine, null, direction);
    }
    return _plainPieceIn(_bodyOf(at), _itemsAt(at), section.key, line);
  }

  AncestorPiece? _leadPieceAt(int line) {
    final body = _leadBody;
    if (body.isEmpty || line < body.first.line) return null;
    return _plainPieceIn(body, _leadItems, '', line);
  }

  /// The lines of the lead, the head after its title line.
  late final List<BodyLine> _leadBody = _leadBodyOf();

  late final List<SectionItem> _leadItems = leadItemsAt(content, type);

  late final Doc _doc = Doc.parse(toLf(content.text));

  late final bool Function(int line) _isGenerated = generatedLineTest(
    _doc,
    toLf(content.text),
    type?.listedGenerators.toSet() ?? const {},
  );

  List<BodyLine> _leadBodyOf() =>
      leadBodyLinesOf(_doc, toLf(content.text), facts, _isGenerated);

  /// Returns the table row, list item, or paragraph of [items], the items of
  /// [body], that holds [line], or null.
  AncestorPiece? _plainPieceIn(
    List<BodyLine> body,
    List<SectionItem> items,
    String sectionKey,
    int line,
  ) {
    const direction = PieceDirection.inbound;
    for (final (i, item) in items.indexed) {
      final last = _lastLineOf(item);
      if (line < item.line || last < line) continue;
      return switch (item.kind) {
        SectionItemKind.tableRow => _piece(sectionKey, direction, (
          first: line,
          last: line,
        ), above: _tableHeadAbove(body, line)),
        SectionItemKind.listItem => _piece(
          sectionKey,
          direction,
          _bulletExtent(body, items, i),
        ),
        SectionItemKind.paragraph => _piece(sectionKey, direction, (
          first: item.line,
          last: last,
        )),
        SectionItemKind.heading => null,
      };
    }
    return null;
  }

  AncestorPiece _piece(
    String sectionKey,
    PieceDirection direction,
    LineRange extent, {
    String? itemId,
    String? heading,
    String? above,
  }) => AncestorPiece(
    doc: doc,
    sectionKey: sectionKey,
    itemId: itemId,
    heading: heading,
    direction: direction,
    first: extent.first,
    last: extent.last,
    text: [
      ?above,
      lines.sublist(extent.first - 1, extent.last).join('\n'),
    ].join('\n'),
  );

  /// Returns the index of the section whose body holds file line [line], or
  /// null for a line before the first section.
  int? _sectionHolding(int line) {
    final starts = facts.sectionLines;
    for (var at = starts.length - 1; at >= 0; at--) {
      if (starts[at] < line) return at;
    }
    return null;
  }

  List<SectionItem> _itemsAt(int at) =>
      _items[at] ??= sectionItemsAt(content, at, type);

  List<_IdExtent> _idExtentsAt(int at) => _idExtents[at] ??= _idExtentsOf(at);

  List<_IdExtent> _idExtentsOf(int at) {
    final section = sectionAt(at);
    if (section == null) return const [];
    final body = _bodyOf(at);
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
            _IdExtent(id: id, extent: extent),
    ];
  }

  /// Returns the innermost ID item of the section [at] whose lines hold
  /// [line], or null.
  _IdExtent? _idItemHolding(int at, int line) {
    _IdExtent? holding;
    for (final item in _idExtentsAt(at)) {
      final holds = item.extent.first <= line && line <= item.extent.last;
      if (holds && (holding == null || item.span < holding.span)) {
        holding = item;
      }
    }
    return holding;
  }

  /// Returns the file line of the `###` heading whose block in the section
  /// [at] holds [line], or null.
  int? _blockHeadingHolding(int at, int line) {
    final anchors = facts.anchors;
    final headingLines = facts.headingLines;
    if (anchors == null || headingLines == null) return null;
    final starts = facts.sectionLines;
    final end = at + 1 < starts.length ? starts[at + 1] : lines.length + 1;
    final body = _bodyOf(at);
    int? found;
    for (final (i, headingLine) in headingLines.indexed) {
      if (i >= anchors.headingLevels.length ||
          anchors.headingLevels[i] != _blockLevel ||
          headingLine <= starts[at] ||
          end <= headingLine ||
          line < headingLine) {
        continue;
      }
      final extent = headingBlockExtentOf(body, headingLine);
      if (extent != null && line <= extent.last) found = headingLine;
    }
    return found;
  }

  String? _slugAt(int headingLine) {
    final at = facts.headingLines?.indexOf(headingLine);
    final slugs = facts.anchors?.headingSlugs;
    return at == null || slugs == null || at < 0 || slugs.length <= at
        ? null
        : slugs[at];
  }

  /// Returns the header and separator rows of the table that holds the row at
  /// file line [rowLine] of [body], or null when none is found.
  String? _tableHeadAbove(List<BodyLine> body, int rowLine) {
    final rowAt = rowLine - body.first.line;
    for (var at = rowAt - 1; at >= 1; at--) {
      final separator = _unquoted(body[at].text);
      if (separator.trim().isEmpty) return null;
      if (startsTable(_unquoted(body[at - 1].text), separator)) {
        return '${lines[body[at - 1].line - 1]}\n${lines[body[at].line - 1]}';
      }
    }
    return null;
  }
}

/// The level of the heading a `###` block opens.
const _blockLevel = 3;

final _quoteMarks = RegExp('^(?: {0,3}> ?)*');

/// Returns [text] without the `>` marks of a blockquote it opens with.
String _unquoted(String text) =>
    text.substring(_quoteMarks.firstMatch(text)!.end);

int _indentOf(String text) => text.length - text.trimLeft().length;

int _lastLineOf(SectionItem item) =>
    item.line + '\n'.allMatches(item.text).length;

/// Returns the file lines of the bullet at [i] of [items], the section's
/// items: its own lines, then each item and each fenced block indented deeper
/// than it.
LineRange _bulletExtent(List<BodyLine> body, List<SectionItem> items, int i) {
  final base = _indentOf(items[i].firstLine);
  var end = _lastLineOf(items[i]);
  for (var k = i + 1; ; k++) {
    final next = k < items.length ? items[k] : null;
    end = _withFencesBefore(body, end, next?.line, base);
    if (next == null || _indentOf(next.firstLine) <= base) {
      return (first: items[i].line, last: end);
    }
    end = _lastLineOf(next);
  }
}

/// Returns [end], moved past each fenced block that follows it, blank lines
/// between aside, and opens indented deeper than [base], before file line
/// [before] (the section end when null).
int _withFencesBefore(List<BodyLine> body, int end, int? before, int base) {
  bool inRange(int at) =>
      at < body.length && (before == null || body[at].line < before);
  var last = end;
  var at = body.indexWhere((line) => line.line == end) + 1;
  while (true) {
    var open = at;
    while (inRange(open) && body[open].text.trim().isEmpty) {
      open++;
    }
    if (!inRange(open) ||
        !body[open].fenced ||
        _indentOf(body[open].text) <= base) {
      return last;
    }
    for (at = open; inRange(at) && body[at].fenced; at++) {
      last = body[at].line;
    }
  }
}

/// Returns the links to other docs of [facts] in source order, each with the
/// [LinkText] the index stored for it, or a text-free one that reads as no
/// item ID.
List<LinkText> _linkTextsOf(LineFacts facts) {
  final stored = storedLinkTextsOf(facts.links, facts.linkTexts);
  return [
    for (final (i, place) in facts.links.indexed)
      stored[i] ?? textFreeLinkOf(place),
  ];
}
