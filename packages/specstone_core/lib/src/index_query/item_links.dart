import 'package:specstone_core/src/doc_model/doc_items.dart';
import 'package:specstone_core/src/doc_model/markdown_lines.dart'
    show atxHeadingOf;
import 'package:specstone_core/src/doc_model/models/id_read.dart';
import 'package:specstone_core/src/doc_model/models/section_item.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show
        ScenarioRef,
        acceptanceSectionId,
        itemKeyOf,
        readItemId,
        readScenarioRef,
        scenarioIdPrefix;
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_facts.dart'
    show itemKeyOfHead;
import 'package:specstone_core/src/index_query/models/cited_section.dart';
import 'package:specstone_core/src/index_query/models/classified_link.dart';
import 'package:specstone_core/src/index_query/models/item_fact.dart';
import 'package:specstone_core/src/index_query/models/item_link.dart';
import 'package:specstone_core/src/index_query/models/item_range.dart';
import 'package:specstone_core/src/index_query/models/line_facts.dart';
import 'package:specstone_core/src/index_query/models/line_range.dart';
import 'package:specstone_core/src/index_query/models/link_cite.dart';
import 'package:specstone_core/src/index_query/models/link_text.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// Classifies [link] as a cite reads it, by the [target] that
/// [anchorTargetOf] gave its anchor, so no reader maps anchors but that
/// one.
///
/// [sectionAt] gives the held section at an index of the doc's sections, or
/// null when it holds none. A lettered or unreadable form is no
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
    OtherAnchorTarget() => const OtherAnchorCite(),
    HeadingBlockTarget(:final headingLine) => HeadingBlockCite(
      headingLine: headingLine,
    ),
    SectionTarget(:final sectionIndex) => switch (sectionAt(sectionIndex)) {
      null => const OtherAnchorCite(),
      final section => _sectionCite(link.text, section),
    },
  };
}

/// Returns each held section of [content] as [classifyLink] reads it, in
/// the doc's section order; [type] gives each section's template.
List<CitedSection> citedSectionsOf(DocContent content, MergedDocType? type) {
  final templates = heldTemplatesOf(content.sections, type);
  return [
    for (final (at, section) in content.sections.indexed)
      CitedSection(
        key: templates[at]?.id ?? section.key,
        prefixId: templates[at]?.prefixId,
        isAcceptanceCriteria: templates[at]?.id == acceptanceSectionId,
      ),
  ];
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

/// The target of an anchor: a `##` section or a `###` heading
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

/// The anchor exists in the doc but names no `##` section and no
/// `###` block it can place; never a broken pointer.
final class OtherAnchorTarget extends AnchorTarget {
  const new();
}

/// Returns what [anchor] names in [facts]: the `##` section that holds it,
/// the `###` heading block it points at, [OtherAnchorTarget] when the
/// anchor exists but names neither, or null when it exists in no anchor set.
///
/// An html id, the title, a heading below `###`, and a heading whose line
/// the scan cannot pair with its slug (so none is guessed at) are
/// other anchors; so is any anchor of a doc whose anchor set is unknown,
/// which `check` never reports.
AnchorTarget? anchorTargetOf(LineFacts facts, String anchor) {
  final anchors = facts.anchors;
  if (anchors == null) return const OtherAnchorTarget();
  if (!anchors.holds(anchor)) return null;
  final lines = facts.headingLines;
  final index = anchors.headingSlugs.indexOf(anchor);
  if (lines == null || index < 0) return const OtherAnchorTarget();
  final level = anchors.headingLevels[index];
  if (level < 2 || level > 3) return const OtherAnchorTarget();
  final line = lines[index];
  if (level == 2 && facts.sectionLines.contains(line)) {
    return SectionTarget(sectionIndex: facts.sectionLines.indexOf(line));
  }
  return HeadingBlockTarget(headingLine: line);
}

/// Returns each pair of adjacent item links on [line], the text of the
/// line they sit on, joined by ` to `, in source order.
///
/// [links] are every link of the line that holds text, each with its
/// [classifyLink] cite, in source order; only two [ItemCite]s of one
/// target, anchor, and section pair. A link that spans lines pairs with
/// none, so a range never joins two lines.
List<ItemRange> itemRangesOn(String line, List<ClassifiedLink> links) {
  final ranges = <ItemRange>[];
  for (var i = 0; i + 1 < links.length; i++) {
    final ClassifiedLink(link: first, cite: firstCite) = links[i];
    final ClassifiedLink(link: last, cite: lastCite) = links[i + 1];
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
      ranges.add(
        ItemRange(
          first: ItemLink(link: first, cite: firstCite),
          last: ItemLink(link: last, cite: lastCite),
        ),
      );
    }
  }
  return ranges;
}

/// Returns the IDs of the items [range] spans in [items], the stored items of
/// its [section]: the first and last item and each item whose ID has their
/// prefix and a number between theirs, in section order.
List<String> itemIdsInRange(
  ItemRange range,
  CitedSection section,
  List<ItemFact> items,
) {
  final prefix = section.isAcceptanceCriteria
      ? scenarioIdPrefix
      : section.prefixId;
  final first = _numberOf(range.first.cite.itemId, prefix);
  final last = _numberOf(range.last.cite.itemId, prefix);
  if (first == null || last == null) return const [];
  final (low, high) = first <= last ? (first, last) : (last, first);
  return [
    for (final item in items)
      if (item.id case final id?)
        if (_numberOf(id, prefix) case final number?)
          if (low <= number && number <= high) id,
  ];
}

/// Returns the number of the item ID [id] of [prefix], or null when [id] is
/// no such ID.
BigInt? _numberOf(String id, String? prefix) {
  if (prefix == null) return null;
  final read = readItemId(id, prefix);
  return read is ItemId && read.written == id ? read.number : null;
}

/// Returns the first and last body line of each item ID of [section], spanning
/// the item's nested items, their fenced code, and a heading's block; an ID
/// no item of the section holds is absent.
///
/// [prefixId] and [isAcceptanceCriteria] are the section's; an ID is read as
/// the index reads it (`itemKeyOfHead`), so this and `check` agree on which
/// items exist. The first item holding an ID spans it.
Map<String, LineRange> itemExtentsOf(
  List<BodyLine> section, {
  required String? prefixId,
  required bool isAcceptanceCriteria,
}) {
  final items = sectionItemsOf(section);
  final extents = <String, LineRange>{};
  final seen = <String>{};
  for (final (i, item) in items.indexed) {
    final isHeading = item.kind == SectionItemKind.heading;
    final key = itemKeyOfHead(
      item.head,
      isHeading: isHeading,
      prefixId: prefixId,
      isAcceptanceCriteria: isAcceptanceCriteria,
    );
    if (key == null || !seen.add(key)) continue;
    final extent = isHeading
        ? headingBlockExtentOf(section, item.line)
        : _listExtent(section, items, i);
    if (extent != null) extents[key] = extent;
  }
  return extents;
}

/// The first and last body line of the block of the heading at file line
/// [headingLine] of [section]: up to the next heading of its level or above,
/// trailing blank lines off; null when that line is no
/// heading of [section].
///
/// A heading inside fenced code is no heading, and a quoted `> ###` heading
/// reads as its level.
LineRange? headingBlockExtentOf(List<BodyLine> section, int headingLine) {
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
  return LineRange(first: headingLine, last: section[end].line);
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
LineRange _listExtent(List<BodyLine> section, List<SectionItem> items, int i) {
  final base = _indentOf(items[i].firstLine);
  var end = _lastLineOf(items[i]);
  for (var k = i + 1; ; k++) {
    final next = k < items.length ? items[k] : null;
    end = _withFencesBefore(section, end, next?.line, base);
    if (next == null || _indentOf(next.firstLine) <= base) break;
    end = _lastLineOf(next);
  }
  return LineRange(first: items[i].line, last: end);
}

/// Returns [end], moved past each fenced block that follows it, blank lines
/// between aside, and opens indented deeper than [base], before file line
/// [before] (the section end when null).
int _withFencesBefore(List<BodyLine> section, int end, int? before, int base) {
  bool inRange(int at) =>
      at < section.length && (before == null || section[at].line < before);
  var last = end;
  var at = section.indexWhere((l) => l.line == end) + 1;
  while (true) {
    var open = at;
    while (inRange(open) && section[open].text.trim().isEmpty) {
      open++;
    }
    if (!inRange(open) ||
        !section[open].fenced ||
        _indentOf(section[open].text) <= base) {
      return last;
    }
    for (at = open; inRange(at) && section[at].fenced; at++) {
      last = section[at].line;
    }
  }
}
