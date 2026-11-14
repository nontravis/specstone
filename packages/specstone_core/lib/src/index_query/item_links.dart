import 'package:specstone_core/src/doc_model/body_line.dart';
import 'package:specstone_core/src/doc_model/doc_items.dart';
import 'package:specstone_core/src/doc_model/markdown_lines.dart'
    show atxHeadingOf, itemHeadingMarker;
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show
        ItemId,
        ScenarioRef,
        itemKeyOf,
        readItemId,
        readScenarioHeading,
        readScenarioRef;
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/index_query/link_places.dart';

/// What a link cites (doc_model RULE-45): the whole doc, one `##` section,
/// one item of a section, or the block of a `###` heading.
sealed class LinkCite {
  const new();

  /// The `##` section this cite names, or null for a doc or a heading
  /// block.
  String? get sectionKey;
}

/// A doc link with no fragment or an empty one (RULE-42).
final class DocCite extends LinkCite {
  const new();

  @override
  String? get sectionKey => null;
}

/// A section link: the anchor names a `##` section and the link's text is
/// no item ID of that section.
final class SectionCite extends LinkCite {
  const new({required this.sectionKey});

  @override
  final String sectionKey;
}

/// An item link: the anchor names the `##` section and the whole text an
/// item ID of it (RULE-12), or `S<N>` on an `acceptance_criteria` section.
final class ItemCite extends LinkCite {
  const new({required this.sectionKey, required this.itemId});

  @override
  final String sectionKey;

  /// The key `check` holds the item by: the ID as written, or
  /// `Scenario <n>` for an `S<N>` link (RULE-35).
  final String itemId;
}

/// A fragment that names a `###` heading (RULE-46): the cite is that
/// heading's whole block.
final class HeadingBlockCite extends LinkCite {
  const new({required this.headingAnchor});

  /// The `###` heading's anchor, as the link writes it.
  final String headingAnchor;

  @override
  String? get sectionKey => null;
}

/// Classifies [link] as RULE-45 reads it, by the target [anchorTargetOf]
/// gave its anchor, so no reader maps anchors but that one.
///
/// [sectionKey] is the `##` section a [SectionTarget] names, null for every
/// other target; [prefixId] that section's `prefix_id`;
/// [isAcceptanceCriteria] whether it is an `acceptance_criteria` section. A
/// null [target] — no fragment, an empty one (RULE-42), or an anchor of no
/// `##` or `###` heading — makes the link a [DocCite]. A lettered or
/// unreadable form (RULE-33) is no item ID, so its link is a [SectionCite].
LinkCite classifyLink(
  LinkText link, {
  required AnchorTarget? target,
  required String? sectionKey,
  required String? prefixId,
  required bool isAcceptanceCriteria,
}) {
  if (target == null) return const DocCite();
  if (target is HeadingBlockTarget) {
    return HeadingBlockCite(headingAnchor: link.anchor!);
  }
  final key = sectionKey!;
  final scenario = isAcceptanceCriteria ? readScenarioRef(link.text) : null;
  if (scenario case ScenarioRef(storyName: null, number: final ItemId s)) {
    return ItemCite(sectionKey: key, itemId: itemKeyOf(s, isScenario: true));
  }
  if (prefixId case final prefix?) {
    final id = readItemId(link.text, prefix);
    if (id is ItemId && id.written == link.text) {
      return ItemCite(sectionKey: key, itemId: id.written);
    }
  }
  return SectionCite(sectionKey: key);
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

/// Two item links of one section joined by ` to ` (RULE-47).
typedef ItemRange = ({LinkText first, LinkText last});

/// Returns each pair of item links on [line], the text of the line they sit
/// on, joined by ` to `, in source order (RULE-47).
///
/// Two links pair when both sit whole on one line, name one target and one
/// anchor, and the whole text between them reads ` to `. A link that spans
/// lines pairs with none, so a range never joins two lines.
List<ItemRange> itemRangesOn(String line, List<LinkText> links) {
  final ranges = <ItemRange>[];
  for (var i = 0; i + 1 < links.length; i++) {
    final first = links[i];
    final last = links[i + 1];
    if (first.line != last.line ||
        first.endLine != first.line ||
        last.endLine != last.line) {
      continue;
    }
    if (first.target != last.target || first.anchor != last.anchor) continue;
    if (line.substring(first.endColumn, last.column) == ' to ') {
      ranges.add((first: first, last: last));
    }
  }
  return ranges;
}

/// The first and last body line of the item [itemId] of [section], spanning
/// its nested items and a heading's whole block (RULE-46); null when no
/// item of the section carries that ID (RULE-19).
///
/// A `### Scenario <N>` heading answers its scenario key (`Scenario <n>`,
/// RULE-35); any other item answers the ID at its start, read as
/// `readItemId` reads it.
({int first, int last})? itemExtentOf(List<BodyLine> section, String itemId) {
  final items = sectionItemsOf(section);
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final matches = item.kind == SectionItemKind.heading
        ? _headingNames(item.head, itemId)
        : _startsItemId(item.head, itemId);
    if (!matches) continue;
    return item.kind == SectionItemKind.heading
        ? _headingExtent(section, item.line)
        : _listExtent(items, i);
  }
  return null;
}

/// Whether the `###` heading [head] names [itemId]: its scenario key, or
/// the ID at its start.
bool _headingNames(String head, String itemId) =>
    switch (readScenarioHeading('$itemHeadingMarker$head')) {
      final ItemId id when itemKeyOf(id, isScenario: true) == itemId => true,
      _ => _startsItemId(head, itemId),
    };

/// Whether [itemId] is the ID at the start of [head] (RULE-19): a letter or
/// digit right after it makes the form another ID's (RULE-12, RULE-33).
bool _startsItemId(String head, String itemId) {
  final at = head.startsWith('**') ? 2 : 0;
  if (!head.startsWith(itemId, at)) return false;
  final end = at + itemId.length;
  if (end >= head.length) return true;
  final rest = head.substring(end);
  return !_idTail.hasMatch(rest);
}

/// A letter, digit, or `**` glued right onto an ID's digits, which makes
/// the text no whole ID (RULE-12, RULE-33).
final _idTail = RegExp(r'^[\p{L}\p{N}]|^\*\*', unicode: true);

/// The extent of the list item at [i]: its own lines plus every nested item
/// after it, up to the next item that opens unindented.
({int first, int last}) _listExtent(List<SectionItem> items, int i) {
  var end = _lastLineOf(items[i]);
  for (var k = i + 1; k < items.length && items[k].nested; k++) {
    end = _lastLineOf(items[k]);
  }
  return (first: items[i].line, last: end);
}

int _lastLineOf(SectionItem item) =>
    item.line + '\n'.allMatches(item.text).length;

/// The extent of the `###` heading at [headingLine]: its whole block up to
/// the next heading of its level or above, trailing blank lines off
/// (RULE-46, RULE-5).
({int first, int last}) _headingExtent(
  List<BodyLine> section,
  int headingLine,
) {
  var level = 0;
  var last = section.last.line;
  for (final line in section) {
    final heading = line.fenced ? null : atxHeadingOf(line.text);
    if (line.line == headingLine) {
      level = heading?.level ?? 0;
    } else if (line.line > headingLine &&
        level > 0 &&
        heading != null &&
        heading.level <= level) {
      last = line.line - 1;
      break;
    }
  }
  while (last > headingLine && _textOf(section, last).trim().isEmpty) {
    last--;
  }
  return (first: headingLine, last: last);
}

String _textOf(List<BodyLine> section, int line) =>
    section.firstWhere((l) => l.line == line).text;
