import 'package:specstone_core/src/doc_model/body_line.dart';
import 'package:specstone_core/src/doc_model/doc_items.dart';
import 'package:specstone_core/src/doc_model/markdown_lines.dart'
    show atxHeadingOf;
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show ItemId, ScenarioRef, itemKeyOf, readItemId, readScenarioRef;
import 'package:specstone_core/src/index_query/item_facts.dart'
    show itemKeyOfHead;
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/index_query/link_places.dart';

/// What a link cites (doc_model RULE-45): the whole doc, one `##` section,
/// one item of a section, the block of a `###` heading, or nothing the doc
/// holds.
sealed class LinkCite {
  const new();
}

/// A doc link: no fragment, or an empty one (RULE-42).
final class DocCite extends LinkCite {
  const new();
}

/// A section link: the anchor names a `##` section and the link's text is
/// no item ID of that section.
final class SectionCite extends LinkCite {
  const new({required this.sectionKey});

  final String sectionKey;
}

/// An item link: the anchor names the `##` section and the whole text an
/// item ID of it (RULE-12), or `S<N>` on an `acceptance_criteria` section.
final class ItemCite extends LinkCite {
  const new({required this.sectionKey, required this.itemId});

  final String sectionKey;

  /// The key `check` holds the item by: the ID as written, or
  /// `Scenario <n>` for an `S<N>` link (RULE-35).
  final String itemId;
}

/// A fragment that names a `###` heading (RULE-46): the cite is that
/// heading's whole block, which [headingBlockExtentOf] bounds.
final class HeadingBlockCite extends LinkCite {
  const new({required this.headingLine});

  /// The file line of the `###` heading.
  final int headingLine;
}

/// A link with a fragment that names no `##` or `###` heading the doc can
/// place: a missing anchor, an html id, a heading line the scan cannot
/// pair (RULE-13). Neither a doc link nor a cite; a reader reports or skips
/// it and never prints the doc (follow_cited_links E13).
final class UnresolvedCite extends LinkCite {
  const new();
}

/// What a classifier needs of the `##` section a link names.
typedef CitedSection = ({
  String key,
  String? prefixId,
  bool isAcceptanceCriteria,
});

/// Classifies [link] as RULE-45 reads it, by the [target] that
/// [anchorTargetOf] gave its anchor, so no reader maps anchors but that
/// one.
///
/// [sectionAt] gives the held section at an index of the doc's sections, or
/// null when it holds none. A lettered or unreadable form (RULE-33) is no
/// item ID, so its link is a section link.
LinkCite classifyLink(
  LinkText link, {
  required AnchorTarget? target,
  required CitedSection? Function(int sectionIndex) sectionAt,
}) {
  final anchor = link.anchor;
  if (anchor == null || anchor.isEmpty) return const DocCite();
  return switch (target) {
    null => const UnresolvedCite(),
    HeadingBlockTarget(:final headingLine) => HeadingBlockCite(
      headingLine: headingLine,
    ),
    SectionTarget(:final sectionIndex) => switch (sectionAt(sectionIndex)) {
      null => const UnresolvedCite(),
      final section => _sectionCite(link.text, section),
    },
  };
}

LinkCite _sectionCite(String text, CitedSection section) {
  final scenario = section.isAcceptanceCriteria ? readScenarioRef(text) : null;
  if (scenario case ScenarioRef(storyName: null, number: final ItemId s)) {
    return ItemCite(
      sectionKey: section.key,
      itemId: itemKeyOf(s, isScenario: true),
    );
  }
  final prefix = section.prefixId;
  if (prefix != null) {
    final id = readItemId(text, prefix);
    if (id is ItemId && id.written == text) {
      return ItemCite(sectionKey: section.key, itemId: id.written);
    }
  }
  return SectionCite(sectionKey: section.key);
}

/// The target of an anchor (RULE-46): a `##` section or a `###` heading
/// block.
sealed class AnchorTarget {
  const new();
}

/// The anchor names a `##` section of the doc.
final class SectionTarget extends AnchorTarget {
  const new({required this.sectionIndex});

  /// The section's index in the doc's sections, as `Doc.sections` orders
  /// them; its key is the held section's `key` at the same index.
  final int sectionIndex;
}

/// The anchor names a `###` heading of the doc: the cite is that heading's
/// whole block.
final class HeadingBlockTarget extends AnchorTarget {
  const new({required this.headingLine});

  /// The file line of the `###` heading.
  final int headingLine;
}

/// Returns what [anchor] names in [facts]: the `##` section that holds it,
/// or the `###` heading block it points at, or null.
///
/// Null when [facts] holds no anchor set, no heading lines (a heading the
/// line scan cannot place, so none pairs with its slug), or no `##` or
/// `###` heading of that anchor — an html id names an anchor (RULE-13) but
/// no section, and the title heading names the doc, so neither is guessed
/// at.
AnchorTarget? anchorTargetOf(LineFacts facts, String anchor) {
  final anchors = facts.anchors;
  final lines = facts.headingLines;
  if (anchors == null || lines == null) return null;
  final index = anchors.headingSlugs.indexOf(anchor);
  if (index < 0) return null;
  final level = anchors.headingLevels[index];
  if (level < 2 || level > 3) return null;
  final line = lines[index];
  if (level == 2 && facts.sectionLines.contains(line)) {
    return SectionTarget(sectionIndex: facts.sectionLines.indexOf(line));
  }
  return HeadingBlockTarget(headingLine: line);
}

/// A link a reader classified as an item link.
typedef ItemLink = ({LinkText link, ItemCite cite});

/// Two item links of one section joined by ` to ` (RULE-47).
typedef ItemRange = ({ItemLink first, ItemLink last});

/// Returns each pair of adjacent item links on [line], the text of the
/// line they sit on, joined by ` to `, in source order (RULE-47).
///
/// [links] are every link of the line that holds text, each with its
/// [classifyLink] cite, in source order; only two [ItemCite]s of one
/// target, anchor, and section pair. A link that spans lines pairs with
/// none, so a range never joins two lines.
List<ItemRange> itemRangesOn(
  String line,
  List<({LinkText link, LinkCite cite})> links,
) {
  final ranges = <ItemRange>[];
  for (var i = 0; i + 1 < links.length; i++) {
    final (link: first, cite: firstCite) = links[i];
    final (link: last, cite: lastCite) = links[i + 1];
    if (firstCite is! ItemCite || lastCite is! ItemCite) continue;
    if (first.line != last.line ||
        first.endLine != first.line ||
        last.endLine != last.line) {
      continue;
    }
    if (first.target != last.target ||
        first.anchor != last.anchor ||
        firstCite.sectionKey != lastCite.sectionKey) {
      continue;
    }
    if (line.substring(first.endColumn, last.column) == ' to ') {
      ranges.add((
        first: (link: first, cite: firstCite),
        last: (link: last, cite: lastCite),
      ));
    }
  }
  return ranges;
}

/// The first and last body line of the item [itemId] of [section], spanning
/// its nested items, their fenced code, and a heading's block (RULE-46);
/// null when no item of the section holds that ID (RULE-19).
///
/// [prefixId] and [isAcceptanceCriteria] are the section's; the ID is read
/// as the index reads it (`itemKeyOfHead`), so this and `check` agree on
/// which items exist.
({int first, int last})? itemExtentOf(
  List<BodyLine> section,
  String itemId, {
  required String? prefixId,
  required bool isAcceptanceCriteria,
}) {
  final items = sectionItemsOf(section);
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final key = itemKeyOfHead(
      item.head,
      isHeading: item.kind == SectionItemKind.heading,
      prefixId: prefixId,
      isAcceptanceCriteria: isAcceptanceCriteria,
    );
    if (key != itemId) continue;
    return item.kind == SectionItemKind.heading
        ? headingBlockExtentOf(section, item.line)
        : _listExtent(section, items, i);
  }
  return null;
}

/// The first and last body line of the block of the heading at file line
/// [headingLine] of [section]: up to the next heading of its level or above,
/// trailing blank lines off (RULE-46, RULE-5); null when that line is no
/// heading of [section].
///
/// A heading inside fenced code is no heading, and a quoted `> ###` heading
/// reads as its level.
({int first, int last})? headingBlockExtentOf(
  List<BodyLine> section,
  int headingLine,
) {
  final start = section.indexWhere((l) => l.line == headingLine);
  if (start < 0) return null;
  final level = _headingLevelOf(section[start]);
  if (level == null) return null;
  var end = section.length - 1;
  for (var k = start + 1; k < section.length; k++) {
    final other = _headingLevelOf(section[k]);
    if (other != null && other <= level) {
      end = k - 1;
      break;
    }
  }
  while (end > start && section[end].text.trim().isEmpty) {
    end--;
  }
  return (first: headingLine, last: section[end].line);
}

final _quoteMarks = RegExp('^(?: {0,3}> ?)*');

/// The level of the ATX heading [line] is, after any `>` marks, or null.
int? _headingLevelOf(BodyLine line) {
  if (line.fenced) return null;
  final inner = line.text.substring(_quoteMarks.firstMatch(line.text)!.end);
  return atxHeadingOf(inner)?.level;
}

int _indentOf(String text) => text.length - text.trimLeft().length;

int _lastLineOf(SectionItem item) =>
    item.line + '\n'.allMatches(item.text).length;

/// The extent of the item at [i]: its own lines, then each item indented
/// deeper than it and each fenced block indented deeper than it, up to the
/// first item indented no deeper.
({int first, int last}) _listExtent(
  List<BodyLine> section,
  List<SectionItem> items,
  int i,
) {
  final base = _indentOf(items[i].firstLine);
  var end = _lastLineOf(items[i]);
  for (var k = i + 1; ; k++) {
    final next = k < items.length ? items[k] : null;
    end = _withFencesBefore(section, end, next?.line, base);
    if (next == null || _indentOf(next.firstLine) <= base) break;
    end = _lastLineOf(next);
  }
  return (first: items[i].line, last: end);
}

/// Returns [end], moved past each fenced block that follows it directly and
/// opens indented deeper than [base], before file line [before] (the section
/// end when null).
int _withFencesBefore(List<BodyLine> section, int end, int? before, int base) {
  var last = end;
  var at = section.indexWhere((l) => l.line == end) + 1;
  while (at < section.length &&
      (before == null || section[at].line < before) &&
      section[at].fenced &&
      _indentOf(section[at].text) > base) {
    while (at < section.length &&
        (before == null || section[at].line < before) &&
        section[at].fenced) {
      last = section[at].line;
      at++;
    }
  }
  return last;
}
