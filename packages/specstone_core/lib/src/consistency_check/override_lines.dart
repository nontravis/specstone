import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/doc_items.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show readLeadingLinkTarget;
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_facts.dart'
    show itemKeyOfHead;
import 'package:specstone_core/src/index_query/item_links.dart'
    show
        ItemCite,
        SectionTarget,
        UnresolvedCite,
        anchorTargetOf,
        citedSectionsOf,
        classifyLink;
import 'package:specstone_core/src/index_query/link_places.dart' show LinkText;
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// Id of the doc type whose `overrides` field is one NFR id, no override line.
const nfTypeId = 'nf';

const _overridesField = 'overrides';
const _marker = 'Overrides:';
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
}

/// Whether a doc of [type] can hold override lines: it declares the
/// `overrides` field and is not an `nf` or a type built on it, whose field is
/// one NFR id.
bool carriesOverrides(MergedDocType? type) =>
    type != null &&
    !type.buildsOn(nfTypeId) &&
    type.fields.any((field) => field.id == _overridesField);

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
  final type = context.typeOf(doc);
  if (type == null || !carriesOverrides(type)) return;
  if (context.set.isProjectSpecType(type)) return;
  final chain = _chainOf(context, doc);
  for (var at = 0; at < context.contentOf(doc).sections.length; at++) {
    for (final item in context.itemsIn(doc, at)) {
      if (item.kind == SectionItemKind.listItem &&
          item.head.startsWith(_marker)) {
        yield _readLine(context, doc, chain, item);
      }
    }
  }
}

// The docs above [doc]: the project spec docs of its code target, and, for a
// feature's spec doc, that target's spec docs under each ancestor feature of
// its feature. The ancestor docs count only when their type carries
// `overrides`.
Set<String> _chainOf(CheckContext context, IndexedDoc doc) {
  final index = context.index;
  bool inTarget(IndexedDoc other) => other.target == doc.target;
  final paths = {
    for (final other in index.docs)
      if (other.isTyped && inTarget(other))
        if (context.set.isProjectSpecType(context.typeOf(other)!))
          other.docPath,
  };
  final feature = index.parentOf(doc);
  var ancestor = feature == null ? null : index.parentOf(feature);
  for (; ancestor != null; ancestor = index.parentOf(ancestor)) {
    for (final spec in index.childrenOf(ancestor)) {
      if (inTarget(spec) && carriesOverrides(context.typeOf(spec))) {
        paths.add(spec.docPath);
      }
    }
  }
  return paths;
}

_Read _readLine(
  CheckContext context,
  IndexedDoc doc,
  Set<String> chain,
  SectionItem item,
) {
  final line = item.line;
  final raw = context.linesOf(doc).lines[line - 1];
  final textStart = _textStartOf(raw);
  final shown = readLeadingLinkTarget(raw.substring(textStart));
  if (shown == null) {
    return _malformed(context, doc, line, _textAfterMarker(item.head));
  }
  final link = _linkTextAt(context, doc, line, textStart);
  if (link == null) return _malformed(context, doc, line, shown);
  final target = context.index.at(link.target);
  if (target == null) return (line: OverrideLine(line: line), finding: null);
  if (!chain.contains(target.docPath)) {
    return _outOfChain(context, doc, line, shown, target);
  }
  return _tracked(context, doc, line, shown, target, link);
}

// The offset of the first character after `Overrides:` and its spaces.
int _textStartOf(String raw) {
  var at = raw.indexOf(_marker) + _marker.length;
  while (at < raw.length && raw[at] == ' ') {
    at++;
  }
  return at;
}

// The text after the marker, up to its first ` — ` or the line's end.
String _textAfterMarker(String head) {
  final rest = head.substring(_marker.length);
  final cut = rest.indexOf(_howSeparator);
  return (cut < 0 ? rest : rest.substring(0, cut)).trim();
}

// The link whose text reads as an item ID and opens at [column] of [line].
LinkText? _linkTextAt(
  CheckContext context,
  IndexedDoc doc,
  int line,
  int column,
) => context
    .contentOf(doc)
    .lineFacts
    .linkTexts
    .where((link) => link.line == line && link.column == column)
    .firstOrNull;

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
  IndexedDoc target,
  LinkText link,
) {
  final content = context.contentOf(target);
  final anchor = link.anchor;
  final anchorTarget = anchor == null || anchor.isEmpty
      ? null
      : anchorTargetOf(content.lineFacts, anchor);
  final sections = citedSectionsOf(content, context.typeOf(target));
  final cite = classifyLink(
    link,
    target: anchorTarget,
    sectionAt: (at) => at < sections.length ? sections[at] : null,
  );
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
    ),
    finding: null,
  );
}
