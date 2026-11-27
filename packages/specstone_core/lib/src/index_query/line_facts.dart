import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_anchors.dart';
import 'package:specstone_core/src/doc_model/markdown_body.dart'
    show holdsLinkSyntax;
import 'package:specstone_core/src/doc_model/markdown_lines.dart'
    show atxHeadingOf;
import 'package:specstone_core/src/doc_model/models/doc_anchors.dart';
import 'package:specstone_core/src/doc_model/models/label_part.dart';
import 'package:specstone_core/src/doc_model/models/name_mention.dart';
import 'package:specstone_core/src/doc_model/models/number_label_line.dart';
import 'package:specstone_core/src/doc_model/models/tbr_marker_line.dart';
import 'package:specstone_core/src/doc_model/name_mentions.dart';
import 'package:specstone_core/src/doc_model/number_label.dart'
    show labelLinesInMarkdown;
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show readDocAddress;
import 'package:specstone_core/src/doc_model/text_scan.dart';
import 'package:specstone_core/src/index_query/doc_parse.dart';
import 'package:specstone_core/src/index_query/link_places.dart';
import 'package:specstone_core/src/index_query/models/bare_item_id.dart';
import 'package:specstone_core/src/index_query/models/cite_candidate.dart';
import 'package:specstone_core/src/index_query/models/label_place.dart';
import 'package:specstone_core/src/index_query/models/line_facts.dart';
import 'package:specstone_core/src/index_query/models/line_range.dart';
import 'package:specstone_core/src/index_query/models/link_place.dart';
import 'package:specstone_core/src/index_query/models/link_places.dart';
import 'package:specstone_core/src/index_query/models/link_text.dart';
import 'package:specstone_core/src/index_query/models/mermaid_block.dart';
import 'package:specstone_core/src/index_query/models/prefixed_label_place.dart';
import 'package:specstone_core/src/index_query/models/section_counts.dart';
import 'package:specstone_core/src/index_query/models/tbr_marker_place.dart';

const _tab = 0x09;
const _cr = 0x0D;
const _space = 0x20;
const _hash = 0x23;

/// The warning for [docPath] whose markdown the parser fails on.
String markdownUnparsedWarning(String docPath) =>
    '$docPath: the markdown parser failed; its links are not indexed';

/// Returns the warning [links], the links of the doc at [docPath], give it:
/// [markdownUnparsedWarning] when the parser failed (null [links]), a
/// warning when the link scan and the parser list its links differently,
/// and null otherwise.
///
/// The second keeps a doc whose links a move or the see rule cannot read
/// from passing in silence.
String? linkWarningOf(String docPath, LinkPlaces? links) {
  if (links == null) return markdownUnparsedWarning(docPath);
  if (links.readersAgree) return null;
  return '$docPath: the link scan and the markdown parser list its links '
      'differently; a move or rename leaves its inline links as written, and '
      'check skips its see links';
}

/// Returns how many lines of [lfText], the text [doc] parses, come before the
/// text after its frontmatter: the frontmatter lines, delimiters included.
int linesBeforeBodyOf(Doc doc, String lfText) =>
    _allLines(lfText.substring(0, lfText.length - doc.afterFrontmatter.length));

/// Returns every line of [text], blank or not, a final empty line excluded.
int _allLines(String text) {
  if (text.isEmpty) return 0;
  final breaks = scanText(text).breaks;
  return text.endsWith('\n') ? breaks : breaks + 1;
}

/// Returns the lines of [lfText] without their `\n` and with no final empty
/// line.
List<String> lfLinesOf(String lfText) {
  final lines = lfText.isEmpty ? <String>[] : lfText.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  return lines;
}

/// Computes the facts of [parse], the file at [docPath], and the
/// [sectionCounts] of each section of its doc.
///
/// [parse] is of the file text with LF line ends; every line number comes
/// from it, while `lineCount` and `charCount` measure [countedText], and
/// `approvalMarkChars` comes from [counted], the parse whose frontmatter
/// [countedText] holds. [frontmatterErrorLine] is `FrontmatterYaml.errorLine`
/// of its frontmatter. [bodyTbrMarkers] are the TBR markers of the body, by
/// 0-based body line; [citeCandidates], [bareItemIds], and [mermaidBlocks] are
/// those of a typed doc, none for an untyped one. A body whose parse fails has
/// no links and an unknown anchor set; [markdownUnparsedWarning] joins
/// [warnings] only when the body holds link syntax, as at base — a body with
/// no link syntax is never parsed for links, so it never warns.
/// [linkWarningOf] gives the warning.
LineFacts lineFactsOf({
  required DocParse parse,
  required DocParse counted,
  required String countedText,
  required String docPath,
  required List<SectionCounts> sectionCounts,
  required int? frontmatterErrorLine,
  required List<TbrMarkerLine> bodyTbrMarkers,
  required List<CiteCandidate> citeCandidates,
  required List<BareItemId> bareItemIds,
  required List<MermaidBlock> mermaidBlocks,
  required List<String> warnings,
}) {
  final doc = parse.doc;
  final bodyStart = parse.bodyFirstLine - 1;
  final whole = scanText(countedText);
  final body = doc.afterFrontmatter;
  // One parse per doc, failed or not, shared by the anchors and the links:
  // the inline pass runs only on the blocks that can hold either. A body
  // with no link syntax is never read for links, so it never warns.
  final tree = parse.tree;
  final links = !holdsLinkSyntax(body)
      ? noLinks
      : tree == null
      ? null
      : linkPlacesOf(
          body,
          docPath: docPath,
          firstLine: parse.bodyFirstLine,
          tree: tree,
          linkSources: parse.linkSources,
        );
  if (linkWarningOf(docPath, links) case final warning?) {
    warnings.add(warning);
  }
  final anchors = tree == null ? null : anchorsOf(tree.nodes);
  final fenced = _fencedRanges(doc.afterFrontmatter, bodyStart);
  final labels = labelLinesInMarkdown(body, blocks: parse.lineBlocks);
  return LineFacts(
    links: links?.docLinks ?? const [],
    fileLinks: links?.fileLinks ?? const [],
    selfLinks: links?.selfLinks ?? const [],
    linkTexts: links?.texts ?? const [],
    addressLinkTexts: links?.addressTexts ?? const [],
    nameMentions: _mentionsFrom(doc.afterFrontmatter, bodyStart),
    numberLabels: [
      for (final NumberLabelLine(:line, :written) in labels.numbers)
        LabelPlace(line: bodyStart + line + 1, written: written),
    ],
    prefixedLabels: [
      for (final chain in labels.prefixed)
        PrefixedLabelPlace(
          line: bodyStart + chain.line + 1,
          parts: chain.parts,
        ),
    ],
    tbrMarkers: [
      for (final TbrMarkerLine(:line, :rest) in bodyTbrMarkers)
        TbrMarkerPlace(line: bodyStart + line + 1, rest: rest),
    ],
    citeCandidates: citeCandidates,
    bareItemIds: bareItemIds,
    mermaidBlocks: mermaidBlocks,
    anchors: anchors,
    headingLines: anchors == null
        ? null
        : _headingLinesOf(body, bodyStart, fenced, anchors),
    sectionLines: [for (final i in doc.sectionLineIndexes) bodyStart + i + 1],
    sectionCounts: sectionCounts,
    fenced: fenced,
    lineCount: _lineCount(countedText, fromLine: bodyStart + 1),
    charCount: countedText.length - whole.pairs,
    approvalMarkChars: counted.approvalMarkChars,
    frontmatterErrorLine: frontmatterErrorLine,
  );
}

/// Computes the section lines and fenced lines of [parse], for a reader of
/// item IDs and blocks that reads nothing else.
///
/// No markdown parse runs: links are empty, anchors unknown, and section
/// counts empty, so only `sectionLines`, `fenced`, and the counts of lines
/// and characters hold.
LineFacts lineStructureOf(DocParse parse) {
  final DocParse(:lfText, :doc) = parse;
  final bodyStart = parse.bodyFirstLine - 1;
  final whole = scanText(lfText);
  return LineFacts(
    links: const [],
    fileLinks: const [],
    selfLinks: const [],
    linkTexts: const [],
    addressLinkTexts: const [],
    nameMentions: const [],
    numberLabels: const [],
    prefixedLabels: const [],
    tbrMarkers: const [],
    citeCandidates: const [],
    bareItemIds: const [],
    mermaidBlocks: const [],
    anchors: null,
    headingLines: null,
    sectionLines: [for (final i in doc.sectionLineIndexes) bodyStart + i + 1],
    sectionCounts: const [],
    fenced: _fencedRanges(doc.afterFrontmatter, bodyStart),
    lineCount: _lineCount(lfText, fromLine: bodyStart + 1),
    charCount: lfText.length - whole.pairs,
    approvalMarkChars: parse.approvalMarkChars,
    frontmatterErrorLine: null,
  );
}

/// Reads the facts `toJson` wrote, with the section counts the section rows
/// kept.
LineFacts lineFactsFromJson(
  Map<String, Object?> json, {
  required List<SectionCounts> sectionCounts,
}) {
  final fenced = json['fenced']! as List<Object?>;
  final anchors = json['anchors'] as Map<String, Object?>?;
  return LineFacts(
    links: _placesOfJson(json['links']!),
    fileLinks: _placesOfJson(json['file_links']!),
    selfLinks: _placesOfJson(json['self_links']!),
    linkTexts: _linkTextsOfJson(json['link_texts']!),
    addressLinkTexts: _linkTextsOfJson(json['address_link_texts']!),
    nameMentions: _mentionsOfJson(json['name_mentions']!),
    numberLabels: [
      for (final label
          in (json['number_labels']! as List<Object?>).cast<List<Object?>>())
        LabelPlace(line: label[0]! as int, written: label[1]! as String),
    ],
    prefixedLabels: [
      for (final chain
          in (json['prefixed_labels']! as List<Object?>).cast<List<Object?>>())
        PrefixedLabelPlace(
          line: chain[0]! as int,
          parts: [
            for (final part
                in (chain[1]! as List<Object?>).cast<List<Object?>>())
              LabelPart(
                prefix: part[0]! as String,
                written: part[1]! as String,
                ownerWritten: part[2] as String?,
                ownerStart: part[3] as int?,
              ),
          ],
        ),
    ],
    tbrMarkers: [
      for (final marker
          in (json['tbr_markers']! as List<Object?>).cast<List<Object?>>())
        TbrMarkerPlace(line: marker[0]! as int, rest: marker[1]! as String),
    ],
    citeCandidates: _citeCandidatesOfJson(json['cite_candidates']!),
    bareItemIds: _bareItemIdsOfJson(json['bare_item_ids']!),
    mermaidBlocks: _mermaidBlocksOfJson(json['mermaid_blocks']!),
    anchors: anchors == null
        ? null
        : DocAnchors(
            headingSlugs: (anchors['headings']! as List<Object?>)
                .cast<String>(),
            headingLevels: (anchors['levels']! as List<Object?>).cast<int>(),
            htmlIds: (anchors['ids']! as List<Object?>).cast<String>().toSet(),
          ),
    headingLines: (json['heading_lines'] as List<Object?>?)?.cast<int>(),
    sectionLines: (json['sections']! as List<Object?>).cast<int>(),
    sectionCounts: sectionCounts,
    fenced: [
      for (final range in fenced.cast<List<Object?>>())
        LineRange(first: range[0]! as int, last: range[1]! as int),
    ],
    lineCount: json['lines']! as int,
    charCount: json['chars']! as int,
    approvalMarkChars: json['approval_mark_chars']! as int,
    frontmatterErrorLine: json['yaml_error'] as int?,
  );
}

/// Returns the mentions of [body], whose lines start at file line
/// `bodyStart + 1`.
List<NameMention> _mentionsFrom(String body, int bodyStart) => [
  for (final m in nameMentionsInMarkdown(body))
    NameMention(
      line: bodyStart + m.line,
      column: m.column,
      text: m.text,
      address: m.address,
    ),
];

/// Returns the mentions [json] holds, as `LineFacts.toJson` wrote them.
List<NameMention> _mentionsOfJson(Object json) => [
  for (final m in (json as List<Object?>).cast<List<Object?>>())
    NameMention(
      line: m[0]! as int,
      column: m[1]! as int,
      text: m[2]! as String,
      address: readDocAddress(m[2]! as String),
    ),
];

/// Returns the link texts [json] holds, as `LineFacts.toJson` wrote them.
List<LinkText> _linkTextsOfJson(Object json) => [
  for (final t in (json as List<Object?>).cast<List<Object?>>())
    LinkText(
      line: t[0]! as int,
      column: t[1]! as int,
      endLine: t[2]! as int,
      endColumn: t[3]! as int,
      text: t[4]! as String,
      target: t[5]! as String,
      anchor: t[6] as String?,
      shown: t[7]! as String,
    ),
];

/// Returns the cite candidates [json] holds, as `LineFacts.toJson` wrote them.
List<CiteCandidate> _citeCandidatesOfJson(Object json) => [
  for (final c in (json as List<Object?>).cast<List<Object?>>())
    CiteCandidate(
      line: c[0]! as int,
      written: c[1]! as String,
      sectionKey: c[2] as String?,
      itemIds: (c[3]! as List<Object?>).cast<String>().toList(),
    ),
];

/// Returns the bare item IDs [json] holds, as `LineFacts.toJson` wrote them.
List<BareItemId> _bareItemIdsOfJson(Object json) => [
  for (final b in (json as List<Object?>).cast<List<Object?>>())
    BareItemId(
      line: b[0]! as int,
      column: b[1]! as int,
      id: b[2]! as String,
      citation: switch (b[3]) {
        null => null,
        bareItemLinkKind => LinkCitation(destination: b[4]! as String),
        bareItemCiteKind => CiteCitation(written: b[4]! as String),
        final kind => throw FormatException('unknown citation kind', kind),
      },
    ),
];

/// Returns the mermaid blocks [json] holds, as `LineFacts.toJson` wrote them.
List<MermaidBlock> _mermaidBlocksOfJson(Object json) => [
  for (final b in (json as List<Object?>).cast<List<Object?>>())
    MermaidBlock(fenceLine: b[0]! as int, hash: b[1]! as String),
];

/// Returns the places [json] holds, as `_placesToJson` wrote them.
List<LinkPlace> _placesOfJson(Object json) => [
  for (final place in (json as List<Object?>).cast<List<Object?>>())
    LinkPlace(
      target: place[0]! as String,
      line: place[1]! as int,
      shown: place[2]! as String,
      anchor: place[3] as String?,
    ),
];

/// Returns the non-blank lines of [text] from 1-based line [fromLine] on: the
/// body alone when [fromLine] opens it, the whole text from line 1.
int _lineCount(String text, {required int fromLine}) {
  if (text.isEmpty || fromLine < 1) return 0;
  var count = 0;
  var line = 1;
  var start = 0;
  while (start < text.length) {
    final end = text.indexOf('\n', start);
    final stop = end < 0 ? text.length : end;
    if (line >= fromLine && _holdsText(text, start, stop)) count++;
    if (end < 0) break;
    line++;
    start = end + 1;
  }
  return count;
}

/// Whether the line of [text] from [start] to [stop] holds any non-space
/// character.
bool _holdsText(String text, int start, int stop) {
  for (var i = start; i < stop; i++) {
    final unit = text.codeUnitAt(i);
    if (unit != _space && unit != _tab && unit != _cr) return true;
  }
  return false;
}

/// Returns the fenced blocks of [body], fence lines included, the lines from
/// file line `bodyStart + 1` on.
///
/// A closing fence ends its range, so blocks that touch stay apart. A fence
/// its quote or list item ends has no closing line, so its range ends at the
/// last fenced line, and a fence that opens there starts a new range. An
/// unclosed block runs to the last line. A body with no backtick or tilde run
/// of fence length holds no fence, so its lines are never split.
List<LineRange> _fencedRanges(String body, int bodyStart) {
  if (!mayHoldFence(body)) return const [];
  final scan = fenceScan(lfLinesOf(body));
  final ranges = <LineRange>[];
  int? first;
  for (var i = 0; i < scan.fenced.length; i++) {
    if (first != null && (!scan.fenced[i] || scan.opens[i] != null)) {
      ranges.add(LineRange(first: first, last: bodyStart + i));
      first = null;
    }
    if (scan.fenced[i]) first ??= bodyStart + i + 1;
    if (first != null && scan.closes[i]) {
      ranges.add(LineRange(first: first, last: bodyStart + i + 1));
      first = null;
    }
  }
  if (first != null) {
    ranges.add(LineRange(first: first, last: bodyStart + scan.fenced.length));
  }
  return ranges;
}

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

/// Returns the file line of each ATX heading of [body] outside the [fenced]
/// lines, whose first line is file line `bodyStart + 1`, when each pairs with
/// a heading `markdown` read in [anchors]: the same level, and, for a heading
/// text with no inline markup, the same slug; else null.
///
/// A setext heading or a heading inside a quote or a list is a heading to
/// `markdown` and no line here, and a `##` line inside an HTML block is a
/// line here and no heading to `markdown`, so a doc where the two disagree
/// keeps no line.
List<int>? _headingLinesOf(
  String body,
  int bodyStart,
  List<LineRange> fenced,
  DocAnchors anchors,
) {
  final levels = anchors.headingLevels;
  final lines = <int>[];
  final found = <int>[];
  final texts = <String>[];
  for (final (i, text) in lfLinesOf(body).indexed) {
    final line = bodyStart + i + 1;
    if (text.isEmpty ||
        (text.codeUnitAt(0) != _hash && text.codeUnitAt(0) != _space)) {
      continue;
    }
    if (_isFencedIn(fenced, line)) continue;
    final heading = atxHeadingOf(text);
    if (heading == null) continue;
    lines.add(line);
    found.add(heading.level);
    texts.add(heading.text);
  }
  if (found.length != levels.length) return null;
  for (var i = 0; i < levels.length; i++) {
    if (found[i] != levels[i]) return null;
    if (!_sameSlug(anchors.headingSlugs[i], texts[i], levels[i])) return null;
  }
  return lines;
}

/// The characters that start inline markup, which make a heading's slug
/// differ from the slug of its written text.
final _inlineMarkup = RegExp(r'[`*_\[<&\\!~]');

/// Whether [parsed], a slug `markdown` gave a heading, is the slug of the
/// heading of [level] written as [text], bar a `-1`, `-2` repeat suffix.
///
/// A text with inline markup is parsed as a heading alone, for the slug the
/// parser gives it.
bool _sameSlug(String parsed, String text, int level) {
  final slug = _inlineMarkup.hasMatch(text)
      ? anchorsOfBody('${'#' * level} $text')?.headingSlugs.firstOrNull
      : headingSlugOf(text);
  if (slug == null) return false;
  if (parsed == slug) return true;
  return parsed.startsWith('$slug-') &&
      int.tryParse(parsed.substring(slug.length + 1)) != null;
}
