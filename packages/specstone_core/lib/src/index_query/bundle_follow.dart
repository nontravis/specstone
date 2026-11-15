import 'dart:io';

import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_trim.dart';
import 'package:specstone_core/src/index_query/cited_by.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_links.dart';
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/index_query/link_places.dart';
import 'package:specstone_core/src/index_query/link_scan.dart'
    show linkSourcesOf;
import 'package:specstone_core/src/index_query/summary_cut.dart';
import 'package:specstone_core/src/portable_path.dart';
import 'package:specstone_core/src/rendering/line_ending.dart' show toLf;
import 'package:specstone_core/src/templates/merged_doc_type.dart';

// MARK: - Parts

/// A line past the last line of any doc: the end of a head with no section.
const _pastLastLine = 0x7fffffff;

/// An item, a section, or a summary doc that a link of a bundle cites outside
/// what the bundle prints, cut from the stored text, or the path of a file no
/// doc type describes that a link names.
final class AppendedPart {
  const new({
    required this.doc,
    this.sectionKey,
    this.itemId,
    this.heading,
    this.summary = false,
    this.nameOnly = false,
    this.cited = const [],
    this.sections = const [],
    required this.text,
  });

  /// A part that names [path], a file under the docs root that the index
  /// holds no doc for, by its path alone, as an untyped doc of that path.
  new file(String path)
    : this(
        doc: IndexedDoc(
          docPath: path,
          name: path,
          frontmatter: const {},
          tokens: 0,
        ),
        text: '',
      );

  /// A part that names [doc] by its naming line alone, with no text.
  new nameLine(IndexedDoc doc) : this(doc: doc, nameOnly: true, text: '');

  final IndexedDoc doc;

  /// The key of the `##` section that holds the part; null for a summary doc,
  /// a naming line, and a path.
  final String? sectionKey;

  /// The cited item's ID, each item of a range its own; null for a section,
  /// a `###` block that starts no item, a summary doc, and a path.
  final String? itemId;

  /// The link's anchor for a `###` block that starts no item, else null.
  final String? heading;

  /// Whether the part is the doc in summary.
  final bool summary;

  /// Whether the part is the doc's naming line alone, since its type's
  /// `summary_for` leaves out the bundle's target.
  final bool nameOnly;

  /// The items of the part whose cited-by lines [text] holds, in print order;
  /// empty outside a design bundle.
  final List<CitedItem> cited;

  /// The `##` sections [text] holds whole, each with its header's line in
  /// [text]: a section part's own, a summary doc's summary sections; none for
  /// an item, a `###` block, or a path.
  final List<SectionLine> sections;

  /// What prints after the part's naming line: an item's own lines, a
  /// section whole, a summary doc's title and summary sections, or nothing
  /// for a naming line and a path.
  final String text;

  /// Whether the part names a file no doc type describes by its path alone,
  /// since an untyped doc never joins a bundle.
  bool get pathOnly => !doc.isTyped;
}

/// Returns the parts the links of [bundle]'s printed docs cite, then those
/// the links of each part cite, in the order a breadth-first walk first
/// reaches them, each once.
///
/// `query` follows no link. A file no doc type describes, an untyped doc or
/// any other linked file on disk, adds its path alone. A target the bundle
/// already prints whole, a section the trim drops, a doc `--no-project`
/// dropped, and a link `check` reports as broken add nothing; a link into
/// another code target's doc is followed.
///
/// Given [citedBy], each part holds its items' cited-by lines right after
/// them.
List<AppendedPart> followLinks(
  DocIndex index,
  Bundle bundle, {
  CitedByIndex? citedBy,
}) {
  if (bundle.mode == BundleMode.query) return const [];
  final walk = _Walk(index, bundle, citedBy);
  for (final doc in bundle.printOrder(index)) {
    walk.addPrinted(doc, summary: bundle.summaryOnly.contains(doc.docPath));
  }
  return walk.run();
}

// MARK: - Walk

/// A link with the [LinkText] that [classifyLink] reads it by.
///
/// The index keeps a text only for a link whose text can read as an item ID,
/// so any other link takes an empty text, which reads as none;
/// `shaped` tells the two apart. `file` marks a link to a file that is no
/// `.md` doc.
typedef _Link = ({LinkText text, bool shaped, bool file});

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
  new(this.index, this.bundle, this.citedBy);

  final DocIndex index;
  final Bundle bundle;
  final CitedByIndex? citedBy;
  final _whole = <String>{};
  final _summarized = <String>{};
  final _paths = <String>{};
  final _named = <String>{};
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
      _followLine(view, view.inSourceOrder(links.sublist(start, end)));
      start = end;
    }
  }

  /// Follows [links], every link of one line of [view], in source order; a
  /// range's first link appends each item of the range.
  void _followLine(_DocView view, List<_Link> links) {
    final classified = [
      for (final link in links) (link: link, cited: _classify(link.text)),
    ];
    final itemLinks = [
      for (final (:link, :cited) in classified)
        if (link.shaped && cited != null) (link: link.text, cite: cited.cite),
    ];
    final rangeFrom = {
      if (itemLinks.where((link) => link.cite is ItemCite).length > 1)
        for (final range in itemRangesOn(
          view.lineText(links.first.text.line),
          itemLinks,
        ))
          range.first.link: range,
    };
    for (final (:link, :cited) in classified) {
      final range = cited == null ? null : rangeFrom[cited.link];
      if (cited == null) {
        _appendPath(link);
      } else if (_namesOnly(cited.view)) {
        _appendNameLine(cited.view);
      } else if (range != null) {
        _appendRange(cited, range);
      } else {
        _append(cited);
      }
    }
  }

  /// Whether the bundle prints [view]'s doc by its naming line alone: its type
  /// leaves out the bundle's target and the bundle does not print it whole.
  bool _namesOnly(_DocView view) =>
      !_whole.contains(view.doc.docPath) && !bundle.printsSummaryOf(view.type);

  /// Appends the naming line of [view]'s doc once, whatever link names it;
  /// the doc's links are not followed.
  void _appendNameLine(_DocView view) {
    if (_named.add(view.doc.docPath)) {
      _parts.add(AppendedPart.nameLine(view.doc));
    }
  }

  /// Appends the path of the file no doc type describes that [link] names,
  /// once: an untyped doc, or a file that is no `.md` doc and exists on
  /// disk. Any other link that cites nothing adds nothing.
  void _appendPath(_Link link) {
    final path = link.text.target;
    if (_paths.contains(path)) return;
    if (link.file) {
      if (!_onDisk(path)) return;
      _paths.add(path);
      _parts.add(AppendedPart.file(path));
      return;
    }
    final doc = index.at(path);
    if (doc == null || doc.isTyped) return;
    _paths.add(path);
    _parts.add(AppendedPart(doc: doc, text: ''));
  }

  /// Whether [path], a path under the docs root, names a file or folder on
  /// disk; a missing one is `check`'s `link_target_missing`, never followed.
  bool _onDisk(String path) {
    if (!isPortablePath(path)) return false;
    final root = index.docsRoot.path;
    final separator = Platform.pathSeparator;
    final onDisk = [
      if (root.endsWith(separator))
        root.substring(0, root.length - 1)
      else
        root,
      ...path.split('/'),
    ].join(separator);
    return FileSystemEntity.typeSync(onDisk) != FileSystemEntityType.notFound;
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
    final print = summaryPrintOf(
      view.doc,
      view.content,
      view.type,
      bundle.mode,
      citedBy,
    );
    _add(
      AppendedPart(
        doc: view.doc,
        summary: true,
        cited: print.cited,
        sections: print.sections,
        text: print.text,
      ),
      view,
      view.summaryRanges(bundle.mode),
    );
  }

  void _appendSection(_DocView view, int at, String sectionKey) {
    final range = view.sectionRange(at);
    if (!view.keeps(at, bundle.mode) || _prints(view, range)) return;
    final cited = _citedIn(view, at);
    _add(
      AppendedPart(
        doc: view.doc,
        sectionKey: sectionKey,
        cited: cited,
        sections: [(key: sectionKey, line: 0)],
        text: sectionBlockOf(
          view.content.sections[at],
          bodyLine: view.facts.sectionLines[at] + 1,
          after: citedLinesAfter(cited),
        ),
      ),
      view,
      [range],
    );
  }

  /// Returns the items of the section [at] of [view]'s doc inside [within],
  /// the whole section when null, that other docs cite; none outside a
  /// design bundle.
  List<CitedItem> _citedIn(_DocView view, int at, {LineRange? within}) {
    final cited = citedBy;
    final section = view.citedSectionAt(at);
    if (cited == null || section == null) return const [];
    return citedItemsIn(
      cited,
      view.doc,
      view.content,
      section,
      at,
      within: within,
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
    _appendLines(
      view,
      body,
      extent,
      at: at,
      sectionKey: sectionKey,
      itemId: itemId,
    );
  }

  /// Appends the `###` block at [headingLine], named by its item ID when it
  /// starts an item, else by [anchor].
  void _appendBlock(_DocView view, int headingLine, String anchor) {
    final at = view.sectionHolding(headingLine);
    final section = at == null ? null : view.citedSectionAt(at);
    if (at == null || section == null) return;
    final body = view.bodyLinesOf(at);
    final extent = headingBlockExtentOf(body, headingLine);
    if (extent == null) return;
    final itemId = view.headingItemId(at, body, headingLine);
    _appendLines(
      view,
      body,
      extent,
      at: at,
      sectionKey: section.key,
      itemId: itemId,
      heading: itemId == null ? anchor : null,
    );
  }

  /// Appends the first and last item of [range] and each item of their
  /// section whose ID has their prefix and a number between theirs, in
  /// section order.
  void _appendRange(_Cited cited, ItemRange range) {
    final at = cited.sectionIndex;
    final section = at == null ? null : cited.view.citedSectionAt(at);
    if (at == null || section == null) return;
    final items = cited.view.content.itemFacts.sectionItems[at];
    for (final id in itemIdsInRange(range, section, items)) {
      _appendItem(cited.view, at, section.key, id);
    }
  }

  void _appendLines(
    _DocView view,
    List<BodyLine> body,
    LineRange extent, {
    required int at,
    required String sectionKey,
    required String? itemId,
    String? heading,
  }) {
    if (!view.keeps(at, bundle.mode) || _prints(view, extent)) return;
    final lines = [
      for (final line in body)
        if (extent.first <= line.line && line.line <= extent.last) line.text,
    ];
    final cited = _citedIn(view, at, within: extent);
    _add(
      AppendedPart(
        doc: view.doc,
        sectionKey: sectionKey,
        itemId: itemId,
        heading: heading,
        cited: cited,
        text: printedBodyOf(
          lines.join('\n'),
          firstLine: extent.first,
          after: citedLinesAfter(cited),
        ),
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

// MARK: - Doc view

/// One doc as the walk reads it: its stored content, its held sections as
/// [classifyLink] reads them, and its links in line order.
final class _DocView {
  new(this.doc, this.content, this.type)
    : _sections = citedSectionsOf(content, type);

  final IndexedDoc doc;
  final DocContent content;
  final MergedDocType? type;
  final List<CitedSection> _sections;

  late final List<_Link> links = _linksOf(content.lineFacts);

  late final List<String> _lines = content.text.split('\n');

  late final Map<(int, String), List<int>> _sourceColumns = _sourceColumnsOf(
    content,
  );

  LineFacts get facts => content.lineFacts;

  /// Returns the section at [at] as [classifyLink] reads it, or null when the
  /// doc holds no section there.
  CitedSection? citedSectionAt(int at) =>
      at < _sections.length ? _sections[at] : null;

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

  /// Whether a print in [mode] keeps the section at [at]; one that is N/A or
  /// still its template prints nowhere, as a part or whole.
  bool keeps(int at, BundleMode mode) {
    final section = content.sections[at];
    return keptSectionsOf(
      content,
      type,
      mode,
    ).any((kept) => identical(kept, section));
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

  /// Returns the ranges of the summary sections a summary of the doc prints,
  /// a `summary_rows` section's narrowed to its cut.
  List<LineRange> summaryRanges(BundleMode mode) => [
    for (final section in summarySectionsOf(content, type, mode))
      _printedRange(section),
  ];

  LineRange _printedRange(IndexedSection section) {
    final at = _indexOf(section);
    final range = sectionRange(at);
    final rows = summaryRowCountOf(type, section.key);
    if (rows == null) return range;
    final cut = cutToRows(section.body, rows);
    final last = range.first + cut.lineCount;
    return (first: range.first, last: last < range.last ? last : range.last);
  }

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

  /// Returns [links], every link of one file line, in source order.
  ///
  /// The nth link of a destination as written on the line sits at the column
  /// of the nth link source the scan reads there, however the destination is
  /// written; a link the scan placed on no source of the line goes last.
  List<_Link> inSourceOrder(List<_Link> links) {
    if (links.length < 2) return links;
    final lineEnd = lineText(links.first.text.line).length;
    final taken = <(int, String), int>{};
    int columnOf(_Link link) {
      final key = (link.text.line, link.text.shown);
      final nth = taken[key] ?? 0;
      taken[key] = nth + 1;
      final columns = _sourceColumns[key];
      return columns != null && nth < columns.length ? columns[nth] : lineEnd;
    }

    final columns = [for (final link in links) columnOf(link)];
    final order = [for (var i = 0; i < links.length; i++) i]
      ..sort((a, b) {
        final byColumn = columns[a].compareTo(columns[b]);
        return byColumn != 0 ? byColumn : a - b;
      });
    return [for (final i in order) links[i]];
  }

  /// Returns file line [line] of the stored text, without its line ending.
  String lineText(int line) {
    final text = _lines[line - 1];
    return text.endsWith('\r') ? text.substring(0, text.length - 1) : text;
  }

  int _indexOf(IndexedSection section) =>
      content.sections.indexWhere((held) => identical(held, section));
}

/// Returns the 0-based column of each link source of [content]'s stored text,
/// by its file line and destination as written, in source order: the scan
/// the index placed each link by.
Map<(int, String), List<int>> _sourceColumnsOf(DocContent content) {
  final lf = toLf(content.text);
  final frontmatter = content.frontmatterText ?? '';
  final body = lf.substring(frontmatter.length);
  final firstLine = '\n'.allMatches(frontmatter).length + 1;
  final columns = <(int, String), List<int>>{};
  for (final source in linkSourcesOf(body, firstLine: firstLine)) {
    final shown = source.shown;
    if (shown == null) continue;
    final lineStart = body.lastIndexOf('\n', source.offset) + 1;
    (columns[(source.line, shown)] ??= []).add(source.offset - lineStart);
  }
  return columns;
}

/// Returns the doc links, self links, and file links of [facts] in line
/// order, each with the stored [LinkText] of its place when the index keeps
/// one.
List<_Link> _linksOf(LineFacts facts) {
  final texts = <(int, String, String?, String), List<LinkText>>{};
  for (final text in facts.linkTexts) {
    (texts[(text.line, text.target, text.anchor, text.shown)] ??= []).add(text);
  }
  final taken = <(int, String, String?, String), int>{};
  _Link linkOf(LinkPlace place, {required bool file}) {
    final key = (place.line, place.target, place.anchor, place.shown);
    final nth = taken[key] ?? 0;
    taken[key] = nth + 1;
    final stored = texts[key];
    if (!file && stored != null && nth < stored.length) {
      return (text: stored[nth], shaped: true, file: false);
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
      file: file,
    );
  }

  final links = [
    for (final place in [...facts.links, ...facts.selfLinks])
      linkOf(place, file: false),
    for (final place in facts.fileLinks) linkOf(place, file: true),
  ];
  return _byLine(links);
}

/// Returns [links], whose doc, self, and file links each come in source
/// order, sorted by line, ties kept in list order; `inSourceOrder` orders
/// the links of one line.
List<_Link> _byLine(List<_Link> links) {
  final order = [for (var i = 0; i < links.length; i++) i]
    ..sort((a, b) {
      final byLine = links[a].text.line.compareTo(links[b].text.line);
      return byLine != 0 ? byLine : a - b;
    });
  return [for (final i in order) links[i]];
}
