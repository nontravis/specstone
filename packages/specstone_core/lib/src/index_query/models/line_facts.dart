import 'package:specstone_core/src/doc_model/models/doc_anchors.dart';
import 'package:specstone_core/src/doc_model/models/name_mention.dart';
import 'package:specstone_core/src/index_query/models/bare_item_id.dart';
import 'package:specstone_core/src/index_query/models/cite_candidate.dart';
import 'package:specstone_core/src/index_query/models/label_place.dart';
import 'package:specstone_core/src/index_query/models/line_range.dart';
import 'package:specstone_core/src/index_query/models/link_place.dart';
import 'package:specstone_core/src/index_query/models/link_text.dart';
import 'package:specstone_core/src/index_query/models/mermaid_block.dart';
import 'package:specstone_core/src/index_query/models/section_counts.dart';
import 'package:specstone_core/src/index_query/models/tbr_marker_place.dart';

/// The wire kind of a bare item ID cited by a link.
const bareItemLinkKind = 'link';

/// The wire kind of a bare item ID cited by a `cite` form.
const bareItemCiteKind = 'cite';

/// What a doc's file lines say, computed once when the index refreshes.
///
/// A check reads these instead of parsing the text again.
final class LineFacts {
  const new({
    required this.links,
    required this.fileLinks,
    required this.selfLinks,
    required this.linkTexts,
    required this.nameMentions,
    required this.numberLabels,
    required this.tbrMarkers,
    required this.citeCandidates,
    required this.bareItemIds,
    required this.mermaidBlocks,
    required this.anchors,
    required this.headingLines,
    required this.sectionLines,
    required this.sectionCounts,
    required this.fenced,
    required this.lineCount,
    required this.charCount,
    required this.frontmatterErrorLine,
  });

  /// The doc links that resolve to another `.md` doc, in source order.
  final List<LinkPlace> links;

  /// The relative links that are no doc link, in source order; each target is
  /// the path under the docs root, with leading `../` segments when it leaves
  /// the root.
  final List<LinkPlace> fileLinks;

  /// The links that name the doc itself, a bare `#anchor` included, in source
  /// order.
  final List<LinkPlace> selfLinks;

  /// The text and place of each doc link and self link whose text reads as an
  /// item ID, in source order.
  final List<LinkText> linkTexts;

  /// The doc-name mentions of the body, in source order; `line` is
  /// the file line.
  final List<NameMention> nameMentions;

  /// The number labels of the body as `number_label` reads them, in
  /// source order; `line` is the file line.
  final List<LabelPlace> numberLabels;

  /// The `TBR —` markers of the body outside fenced code and code spans, in
  /// source order; `line` is the file line and `rest` the line's text after
  /// the marker, trimmed.
  final List<TbrMarkerPlace> tbrMarkers;

  /// The cite candidates of the body, in source order; none for an
  /// untyped doc.
  final List<CiteCandidate> citeCandidates;

  /// The bare item IDs of the body, in source order; none for an untyped doc.
  final List<BareItemId> bareItemIds;

  /// The `mermaid` blocks of the body, in source order; none for an untyped
  /// doc.
  final List<MermaidBlock> mermaidBlocks;

  /// The doc's anchor set; null when the anchor set cannot
  /// be computed, never a stand-in for an empty one.
  final DocAnchors? anchors;

  /// The file line of each heading of [anchors], in the order of its
  /// `headingSlugs`; null when [anchors] is null or a heading is no ATX line
  /// outside fenced code, so the lines cannot be paired with the slugs.
  final List<int>? headingLines;

  /// The header line of each section, in the order of `Doc.sections`.
  final List<int> sectionLines;

  /// The line and code point counts of each section's body, in the order of
  /// [sectionLines].
  ///
  /// The section rows store these, so [toJson] leaves them out.
  final List<SectionCounts> sectionCounts;

  /// The runs of fenced code lines, fence lines included, in file order.
  final List<LineRange> fenced;

  /// The lines of the text `format` lays out for a typed doc, else of the LF
  /// text.
  final int lineCount;

  /// The code points of the text `format` lays out for a typed doc, else of
  /// the LF text.
  final int charCount;

  /// The line the YAML parser names, 1 when the frontmatter is no mapping.
  ///
  /// Null when the frontmatter is valid or absent.
  final int? frontmatterErrorLine;

  /// Whether file [line] (1-based) is fenced code content or a fence line.
  ///
  /// False for a line the file does not have.
  bool isFenced(int line) => _isFencedIn(fenced, line);

  /// Returns the facts as JSON values, apart from [sectionCounts].
  Map<String, Object?> toJson() => {
    'links': _placesToJson(links),
    'file_links': _placesToJson(fileLinks),
    'self_links': _placesToJson(selfLinks),
    'link_texts': [
      for (final t in linkTexts)
        [
          t.line,
          t.column,
          t.endLine,
          t.endColumn,
          t.text,
          t.target,
          t.anchor,
          t.shown,
        ],
    ],
    'name_mentions': [
      for (final m in nameMentions) [m.line, m.column, m.text],
    ],
    'number_labels': [
      for (final label in numberLabels) [label.line, label.written],
    ],
    'tbr_markers': [
      for (final marker in tbrMarkers) [marker.line, marker.rest],
    ],
    'cite_candidates': [
      for (final c in citeCandidates)
        [c.line, c.written, c.sectionKey, c.itemIds],
    ],
    'bare_item_ids': [for (final b in bareItemIds) _bareItemIdToJson(b)],
    'mermaid_blocks': [
      for (final b in mermaidBlocks) [b.fenceLine, b.hash],
    ],
    'anchors': anchors?.toJson(),
    'heading_lines': headingLines,
    'sections': sectionLines,
    'fenced': [
      for (final range in fenced) [range.first, range.last],
    ],
    'lines': lineCount,
    'chars': charCount,
    'yaml_error': frontmatterErrorLine,
  };
}

/// Returns [bare] as its JSON row: line, column, ID, citation kind, and the
/// citation as written, the last two null for no citation.
List<Object?> _bareItemIdToJson(BareItemId bare) {
  final (kind, written) = switch (bare.citation) {
    null => (null, null),
    LinkCitation(:final destination) => (bareItemLinkKind, destination),
    CiteCitation(:final written) => (bareItemCiteKind, written),
  };
  return [bare.line, bare.column, bare.id, kind, written];
}

/// Returns [places] as JSON values.
List<List<Object?>> _placesToJson(List<LinkPlace> places) => [
  for (final place in places)
    [place.target, place.line, place.shown, place.anchor],
];

/// Whether file [line] is inside one of the [ranges] of fenced lines.
bool _isFencedIn(List<LineRange> ranges, int line) {
  var low = 0;
  var high = ranges.length - 1;
  while (low <= high) {
    final mid = (low + high) >> 1;
    final range = ranges[mid];
    if (line < range.first) {
      high = mid - 1;
    } else if (line > range.last) {
      low = mid + 1;
    } else {
      return true;
    }
  }
  return false;
}
