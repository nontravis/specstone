import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/models/section_item.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show readLeadingLinkTarget;
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_facts.dart'
    show itemKeyOfHead;
import 'package:specstone_core/src/index_query/item_links.dart'
    show ItemCite, SectionTarget, UnresolvedCite;
import 'package:specstone_core/src/index_query/override_chain.dart';

const _howSeparator = ' — ';

/// One `Overrides:` list item of a doc, read.
final class OverrideLine {
  /// A line at file [line]; every other field stays null when the line is
  /// malformed, out of chain, or links no doc.
  const new({
    required this.line,
    this.address,
    this.upstream,
    this.itemId,
    this.itemText,
    this.section,
  });

  /// The file line of the list item.
  final int line;

  /// `<doc type>:<name>#<ID>` of the linked item; null when the line is
  /// malformed or out of chain.
  final String? address;

  /// The DocPath the link resolves to.
  final String? upstream;

  /// The linked item's ID as the link writes it.
  final String? itemId;

  /// The linked item's own text, nested items aside; null when its section
  /// holds no such item.
  final String? itemText;

  /// The key of the section the link's anchor names, as a cited section
  /// reads it.
  final String? section;
}

/// Returns the override lines of [doc], in file order.
///
/// A list item that opens with `Overrides:`, outside fenced code, is a line.
/// A doc type that [carriesOverrides] refuses, and a project spec doc, the
/// top of every chain, hold none.
List<OverrideLine> overrideLinesOf(CheckContext context, IndexedDoc doc) => [
  for (final read in _readLines(context, doc)) read.line,
];

/// Returns the `override_line_malformed` and `override_not_in_chain` findings
/// of [doc].
Iterable<Finding> checkOverrideLines(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  for (final read in _readLines(context, doc)) {
    if (read.finding case final finding?) yield finding;
  }
}

typedef _Read = ({OverrideLine line, Finding? finding});

Iterable<_Read> _readLines(CheckContext context, IndexedDoc doc) sync* {
  if (!holdsOverrideLines(context.index, doc)) return;
  final chain = overrideChainOf(context.index, doc);
  for (var at = 0; at < context.contentOf(doc).sections.length; at++) {
    for (final item in context.itemsIn(doc, at)) {
      if (isOverrideLine(item)) {
        yield _readLine(context, doc, chain, item);
      }
    }
  }
}

_Read _readLine(
  CheckContext context,
  IndexedDoc doc,
  Set<String> chain,
  SectionItem item,
) {
  final line = item.line;
  final raw = context.linesOf(doc).lines[line - 1];
  final textStart = overrideTextStart(raw);
  final shown = readLeadingLinkTarget(raw.substring(textStart));
  if (shown == null) {
    return _malformed(context, doc, line, _textAfterMarker(item.head));
  }
  final link = overrideLinkAt(context.contentOf(doc), line, textStart);
  if (link == null) return _malformed(context, doc, line, shown);
  final read = readOverrideLink(context.index, link);
  if (read == null) return (line: OverrideLine(line: line), finding: null);
  if (!chain.contains(read.target.docPath)) {
    return _outOfChain(context, doc, line, shown, read.target);
  }
  return _tracked(context, doc, line, shown, read);
}

// The text after the marker, up to its first ` — ` or the line's end.
String _textAfterMarker(String head) {
  final rest = head.substring(overridesMarker.length);
  final cut = rest.indexOf(_howSeparator);
  return (cut < 0 ? rest : rest.substring(0, cut)).trim();
}

_Read _malformed(
  CheckContext context,
  IndexedDoc doc,
  int line,
  String target,
) => (
  line: OverrideLine(line: line),
  finding: context.finding(
    doc,
    FindingKind.overrideLineMalformed,
    line: line,
    message:
        'the Overrides line opens with no item link ("$target"); write '
        'Overrides: [<ID>](<doc>#<section>) — <how it differs>, because <why>',
    keys: {'target': target},
  ),
);

_Read _outOfChain(
  CheckContext context,
  IndexedDoc doc,
  int line,
  String shown,
  IndexedDoc target,
) => (
  line: OverrideLine(line: line),
  finding: context.finding(
    doc,
    FindingKind.overrideNotInChain,
    line: line,
    message:
        '$shown names ${target.docPath}, which is no doc above this one in '
        'its chain',
    keys: {'target': shown, 'doc': target.docPath},
  ),
);

// A link in the chain: an item link is tracked, a link to no anchor of its
// target is the broken-pointer rule's, any other link is no item link.
_Read _tracked(
  CheckContext context,
  IndexedDoc doc,
  int line,
  String shown,
  OverrideLinkRead read,
) {
  final target = read.target;
  final sections = read.sections;
  final cite = read.cite;
  final anchorTarget = read.anchorTarget;
  if (cite is UnresolvedCite) {
    return (line: OverrideLine(line: line), finding: null);
  }
  if (cite is! ItemCite || anchorTarget is! SectionTarget) {
    return _malformed(context, doc, line, shown);
  }
  final at = anchorTarget.sectionIndex;
  final section = sections[at];
  final item = context
      .itemsIn(target, at)
      .where(
        (item) =>
            itemKeyOfHead(
              item.head,
              isHeading: item.kind == SectionItemKind.heading,
              prefixId: section.prefixId,
              isAcceptanceCriteria: section.isAcceptanceCriteria,
            ) ==
            cite.itemId,
      )
      .firstOrNull;
  return (
    line: OverrideLine(
      line: line,
      address: '${target.docTypeId}:${target.name}#${cite.itemId}',
      upstream: target.docPath,
      itemId: cite.itemId,
      itemText: item?.text,
      section: section.key,
    ),
    finding: null,
  );
}
