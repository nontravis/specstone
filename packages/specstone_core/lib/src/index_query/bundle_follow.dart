import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show ItemId, acceptanceSectionId, readItemId, scenarioIdPrefix;
import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_trim.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_links.dart';
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/index_query/link_places.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

// MARK: - Parts

/// A line past the last line of any doc: the end of a head with no section.
const _pastLastLine = 0x7fffffff;

/// An item, a section, or a summary doc that a link of a bundle cites outside
/// what the bundle prints, cut from the stored text (INV-84).
final class AppendedPart {
  const new({
    required this.doc,
    this.sectionKey,
    this.itemId,
    this.summary = false,
    required this.text,
  });

  final IndexedDoc doc;

  /// The `##` section's key; the link's anchor for a `###` block that starts
  /// no item; null for a summary doc.
  final String? sectionKey;

  /// The cited item's ID, each item of a range its own; null for a section,
  /// a `###` block that starts no item, and a summary doc.
  final String? itemId;

  /// Whether the part is the doc in summary (INV-25).
  final bool summary;

  /// What prints after the part's naming line: an item's own lines, a
  /// section whole, or a summary doc's title and summary sections.
  final String text;
}

/// Returns the parts the links of [bundle]'s printed docs cite, then those
/// the links of each part cite, in the order a breadth-first walk first
/// reaches them, each once (`index_query/get_task_bundle/follow_cited_links`).
///
/// `query` follows no link. A target the bundle already prints whole, an
/// untyped doc, a doc `--no-project` dropped, and a link `check` reports
/// as broken add nothing; a link into another code target's doc is followed.
List<AppendedPart> followLinks(DocIndex index, Bundle bundle) {
  if (bundle.mode == BundleMode.query) return const [];
  final walk = _Walk(index, bundle);
  for (final doc in bundle.printOrder(index)) {
    walk.addPrinted(doc, summary: bundle.summaryOnly.contains(doc.docPath));
  }
  return walk.run();
}

// MARK: - Walk

/// A link with the [LinkText] that [classifyLink] reads it by.
///
/// The index keeps a text only for a link whose text can read as an item ID
/// (RULE-45), so any other link takes an empty text, which reads as none;
/// `shaped` tells the two apart.
typedef _Link = ({LinkText text, bool shaped});

/// What a link cites, with the doc it lands in, the `##` section its anchor
/// names, and the link itself.
typedef _Cited = ({
  _DocView view,
  LinkCite cite,
  int? sectionIndex,
  LinkText link,
});

/// The printed text of one doc or part whose links the walk follows.
typedef _Printed = ({_DocView view, List<LineRange> ranges});

/// One breadth-first walk over the links of a bundle and its parts.
final class _Walk {
  new(this.index, this.bundle);

  final DocIndex index;
  final Bundle bundle;
  final _whole = <String>{};
  final _summarized = <String>{};
  final _printedRanges = <String, List<LineRange>>{};
  final _queue = <_Printed>[];
  final _parts = <AppendedPart>[];
  final _views = <String, _DocView>{};

  /// Queues [doc], which the bundle prints whole or, when [summary], in
  /// summary.
  void addPrinted(IndexedDoc doc, {required bool summary}) {
    final view = _viewOf(doc);
    if (summary) {
      _summarized.add(doc.docPath);
      _queuePrinted(view, view.summaryRanges(bundle.mode));
    } else {
      _whole.add(doc.docPath);
      _queue.add((view: view, ranges: view.wholeRanges(bundle.mode)));
    }
  }

  /// Follows each queued doc and part in turn, the parts it appends joining
  /// the queue's end, and returns the parts.
  List<AppendedPart> run() {
    for (var i = 0; i < _queue.length; i++) {
      final (:view, :ranges) = _queue[i];
      for (final range in ranges) {
        _followRange(view, range);
      }
    }
    return _parts;
  }

  _DocView _viewOf(IndexedDoc doc) => _views[doc.docPath] ??= _DocView(
    doc,
    index.contentOf(doc),
    index.typeOf(doc),
  );

  void _queuePrinted(_DocView view, List<LineRange> ranges) {
    (_printedRanges[view.doc.docPath] ??= []).addAll(ranges);
    _queue.add((view: view, ranges: ranges));
  }

  void _followRange(_DocView view, LineRange range) {
    final links = [
      for (final link in view.links)
        if (range.first <= link.text.line && link.text.line <= range.last) link,
    ];
    for (var start = 0; start < links.length;) {
      var end = start + 1;
      while (end < links.length &&
          links[end].text.line == links[start].text.line) {
        end++;
      }
      _followLine(view, links.sublist(start, end));
      start = end;
    }
  }

  /// Follows [links], every link of one line of [view], in order; a range's
  /// first link appends each item of the range (RULE-47).
  void _followLine(_DocView view, List<_Link> links) {
    final classified = [
      for (final link in links)
        if (_classify(link.text) case final cited?) (link: link, cited: cited),
    ];
    final itemLinks = [
      for (final (:link, :cited) in classified)
        if (link.shaped) (link: link.text, cite: cited.cite),
    ];
    final rangeFrom = {
      if (itemLinks.where((link) => link.cite is ItemCite).length > 1)
        for (final range in itemRangesOn(
          view.lineText(links.first.text.line),
          itemLinks,
        ))
          range.first.link: range,
    };
    for (final (link: _, :cited) in classified) {
      final range = rangeFrom[cited.link];
      if (range != null) {
        _appendRange(cited, range);
      } else {
        _append(cited);
      }
    }
  }

  /// Returns what [link] cites, or null when it lands in no doc, an untyped
  /// doc, or a doc `--no-project` dropped.
  _Cited? _classify(LinkText link) {
    final doc = index.at(link.target);
    if (doc == null ||
        !doc.isTyped ||
        bundle.droppedPaths.contains(doc.docPath)) {
      return null;
    }
    final view = _viewOf(doc);
    final anchor = link.anchor;
    final target = anchor == null || anchor.isEmpty
        ? null
        : anchorTargetOf(view.facts, anchor);
    return (
      view: view,
      cite: classifyLink(link, target: target, sectionAt: view.citedSectionAt),
      sectionIndex: target is SectionTarget ? target.sectionIndex : null,
      link: link,
    );
  }

  void _append(_Cited cited) {
    final view = cited.view;
    switch ((cited.cite, cited.sectionIndex, cited.link.anchor)) {
      case (DocCite(), _, _):
        _appendSummary(view);
      case (SectionCite(:final sectionKey), final int at, _):
        _appendSection(view, at, sectionKey);
      case (ItemCite(:final sectionKey, :final itemId), final int at, _):
        _appendItem(view, at, sectionKey, itemId);
      case (HeadingBlockCite(:final headingLine), _, final String anchor):
        _appendBlock(view, headingLine, anchor);
      default:
        return;
    }
  }

  void _appendSummary(_DocView view) {
    final docPath = view.doc.docPath;
    if (_whole.contains(docPath) || _summarized.contains(docPath)) return;
    _summarized.add(docPath);
    _add(
      AppendedPart(
        doc: view.doc,
        summary: true,
        text: summaryBodyOf(view.doc, view.content, view.type, bundle.mode),
      ),
      view,
      view.summaryRanges(bundle.mode),
    );
  }

  void _appendSection(_DocView view, int at, String sectionKey) {
    final range = view.sectionRange(at);
    if (_prints(view, range)) return;
    _add(
      AppendedPart(
        doc: view.doc,
        sectionKey: sectionKey,
        text: sectionBlockOf(view.content.sections[at]),
      ),
      view,
      [range],
    );
  }

  void _appendItem(_DocView view, int at, String sectionKey, String itemId) {
    final section = view.citedSectionAt(at);
    if (section == null) return;
    final body = view.bodyLinesOf(at);
    final extent = itemExtentOf(
      body,
      itemId,
      prefixId: section.prefixId,
      isAcceptanceCriteria: section.isAcceptanceCriteria,
    );
    if (extent == null) return;
    _appendLines(view, body, extent, sectionKey: sectionKey, itemId: itemId);
  }

  /// Appends the `###` block at [headingLine], named by its item ID when it
  /// starts an item, else by [anchor] (RULE-46).
  void _appendBlock(_DocView view, int headingLine, String anchor) {
    final at = view.sectionHolding(headingLine);
    if (at == null) return;
    final body = view.bodyLinesOf(at);
    final extent = headingBlockExtentOf(body, headingLine);
    if (extent == null) return;
    final itemId = view.headingItemId(at, body, headingLine);
    final sectionKey = itemId == null ? anchor : view.citedSectionAt(at)?.key;
    _appendLines(
      view,
      body,
      extent,
      sectionKey: sectionKey ?? anchor,
      itemId: itemId,
    );
  }

  /// Appends the first and last item of [range] and each item of their
  /// section whose ID has their prefix and a number between theirs, in
  /// section order (RULE-47).
  void _appendRange(_Cited cited, ItemRange range) {
    final at = cited.sectionIndex;
    final section = at == null ? null : cited.view.citedSectionAt(at);
    if (at == null || section == null) return;
    final prefix = section.isAcceptanceCriteria
        ? scenarioIdPrefix
        : section.prefixId;
    final first = _numberOf(range.first.cite.itemId, prefix);
    final last = _numberOf(range.last.cite.itemId, prefix);
    if (first == null || last == null) return;
    final (low, high) = first <= last ? (first, last) : (last, first);
    for (final item in cited.view.content.itemFacts.sectionItems[at]) {
      final id = item.id;
      final number = id == null ? null : _numberOf(id, prefix);
      if (id != null && number != null && low <= number && number <= high) {
        _appendItem(cited.view, at, section.key, id);
      }
    }
  }

  void _appendLines(
    _DocView view,
    List<BodyLine> body,
    LineRange extent, {
    required String sectionKey,
    required String? itemId,
  }) {
    if (_prints(view, extent)) return;
    final lines = [
      for (final line in body)
        if (extent.first <= line.line && line.line <= extent.last) line.text,
    ];
    _add(
      AppendedPart(
        doc: view.doc,
        sectionKey: sectionKey,
        itemId: itemId,
        text: removeHtmlComments(lines.join('\n')).trimRight(),
      ),
      view,
      [extent],
    );
  }

  void _add(AppendedPart part, _DocView view, List<LineRange> ranges) {
    _parts.add(part);
    _queuePrinted(view, ranges);
  }

  /// Whether the bundle already prints every line of [range] of [view]'s doc:
  /// the doc whole, or a printed summary section or part that holds it.
  bool _prints(_DocView view, LineRange range) {
    final docPath = view.doc.docPath;
    if (_whole.contains(docPath)) return true;
    return _printedRanges[docPath]?.any(
          (printed) =>
              printed.first <= range.first && range.last <= printed.last,
        ) ??
        false;
  }
}

/// Returns the number of the item ID [id] of [prefix], or null when [id] is
/// no such ID.
BigInt? _numberOf(String id, String? prefix) {
  if (prefix == null) return null;
  final read = readItemId(id, prefix);
  return read is ItemId && read.written == id ? read.number : null;
}

// MARK: - Doc view

/// One doc as the walk reads it: its stored content, its held sections'
/// templates, and its links in line order.
final class _DocView {
  new(this.doc, this.content, this.type)
    : templates = heldTemplatesOf(content.sections, type);

  final IndexedDoc doc;
  final DocContent content;
  final MergedDocType? type;
  final List<MergedSection?> templates;

  late final List<_Link> links = _linksOf(content.lineFacts);

  late final List<String> _lines = content.text.split('\n');

  LineFacts get facts => content.lineFacts;

  /// Returns the section at [at] as [classifyLink] reads it, or null when the
  /// doc holds no section there.
  CitedSection? citedSectionAt(int at) {
    if (at >= content.sections.length) return null;
    final template = templates[at];
    return (
      key: template?.id ?? content.sections[at].key,
      prefixId: template?.prefixId,
      isAcceptanceCriteria: template?.id == acceptanceSectionId,
    );
  }

  List<BodyLine> bodyLinesOf(int at) =>
      sectionBodyLines(content.sections, facts, at);

  /// Returns the file lines of the section at [at], its header line first.
  LineRange sectionRange(int at) {
    final starts = facts.sectionLines;
    final last = at + 1 < starts.length
        ? starts[at + 1] - 1
        : bodyLinesOf(at).last.line;
    return (first: starts[at], last: last);
  }

  /// Returns the index of the section that holds file line [line], or null
  /// for a line before the first section.
  int? sectionHolding(int line) {
    final starts = facts.sectionLines;
    for (var at = starts.length - 1; at >= 0; at--) {
      if (starts[at] < line) return at;
    }
    return null;
  }

  /// Returns the ranges a whole print of the doc holds: its head, then each
  /// kept section in print order.
  List<LineRange> wholeRanges(BundleMode mode) => [
    (
      first: 1,
      last: facts.sectionLines.isEmpty
          ? _pastLastLine
          : facts.sectionLines.first - 1,
    ),
    for (final section in keptSectionsOf(content, type, mode))
      sectionRange(_indexOf(section)),
  ];

  /// Returns the ranges of the summary sections a summary of the doc prints.
  List<LineRange> summaryRanges(BundleMode mode) => [
    for (final section in summarySectionsOf(content, type, mode))
      sectionRange(_indexOf(section)),
  ];

  /// Returns the ID of the stored item of the section at [at], whose body is
  /// [body], that starts at file line [headingLine], or null when none does.
  String? headingItemId(int at, List<BodyLine> body, int headingLine) {
    final section = citedSectionAt(at);
    if (section == null) return null;
    for (final item in content.itemFacts.sectionItems[at]) {
      final id = item.id;
      if (id == null) continue;
      final extent = itemExtentOf(
        body,
        id,
        prefixId: section.prefixId,
        isAcceptanceCriteria: section.isAcceptanceCriteria,
      );
      if (extent?.first == headingLine) return id;
    }
    return null;
  }

  /// Returns file line [line] of the stored text, without its line ending.
  String lineText(int line) {
    final text = _lines[line - 1];
    return text.endsWith('\r') ? text.substring(0, text.length - 1) : text;
  }

  int _indexOf(IndexedSection section) =>
      content.sections.indexWhere((held) => identical(held, section));
}

/// Returns the doc links and self links of [facts] in line order, each with
/// the stored [LinkText] of its place when the index keeps one.
List<_Link> _linksOf(LineFacts facts) {
  final texts = <(int, String, String?, String), List<LinkText>>{};
  for (final text in facts.linkTexts) {
    (texts[(text.line, text.target, text.anchor, text.shown)] ??= []).add(text);
  }
  final taken = <(int, String, String?, String), int>{};
  _Link linkOf(LinkPlace place) {
    final key = (place.line, place.target, place.anchor, place.shown);
    final nth = taken[key] ?? 0;
    taken[key] = nth + 1;
    final stored = texts[key];
    if (stored != null && nth < stored.length) {
      return (text: stored[nth], shaped: true);
    }
    return (
      text: (
        line: place.line,
        column: 0,
        endLine: place.line,
        endColumn: 0,
        text: '',
        target: place.target,
        anchor: place.anchor,
        shown: place.shown,
      ),
      shaped: false,
    );
  }

  return [
    for (final place in _inLineOrder(facts.links, facts.selfLinks))
      linkOf(place),
  ];
}

/// Returns [a] and [b], each in source order, merged by line; on one line
/// [a]'s places come first.
List<LinkPlace> _inLineOrder(List<LinkPlace> a, List<LinkPlace> b) {
  final merged = <LinkPlace>[];
  var i = 0;
  var k = 0;
  while (i < a.length || k < b.length) {
    final takeA = k >= b.length || (i < a.length && a[i].line <= b[k].line);
    merged.add(takeA ? a[i++] : b[k++]);
  }
  return merged;
}
