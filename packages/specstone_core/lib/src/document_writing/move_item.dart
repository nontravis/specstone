import 'package:specstone_core/src/doc_model/doc_items.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_facts.dart'
    show itemKeyOfHead;
import 'package:specstone_core/src/index_query/item_links.dart'
    show ItemCite, anchorTargetOf, citedSectionsOf, classifyLink;
import 'package:specstone_core/src/index_query/override_chain.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';

const _overridesMarker = 'Overrides:';

/// One item a `move` call names: the doc that holds it and its ID there.
final class ItemTarget {
  const new({required this.doc, required this.id});

  final IndexedDoc doc;
  final String id;
}

/// Where one item of a `move` call lands.
final class ItemLanding {
  const new({
    required this.from,
    required this.to,
    required this.sectionKey,
    required this.newId,
  });

  /// The item and its source doc.
  final ItemTarget from;

  /// The doc the item lands in.
  final IndexedDoc to;

  /// The key of the section the item leaves and lands in.
  final String sectionKey;

  /// The ID the item holds in [to]: its own, or the next free number there.
  final String newId;
}

/// Whether [address] names an item: it holds a `#` and its whole text names
/// no doc, so a path whose file name holds `#` stays a doc target.
bool isItemAddress(DocIndex index, String address) =>
    index.splitAddress(address).sectionKey != null;

/// Returns where each item [addresses] name lands in the doc [under] names, in
/// the order given, writing nothing.
///
/// An item already in that doc stays and an item named twice lands once, so
/// both leave no landing. [codeTarget] keeps each address and [under] to that
/// code target's docs and the shared docs.
///
/// Throws [WriteFault] `item_not_found` for an ID its doc lacks; an
/// [IndexFault] for a name that no doc or 2 or more docs carry, an untyped
/// doc, an [under] doc type with no section of the item's key and prefix, and
/// an `Overrides:` line the move would leave outside its chain. Every fault
/// comes before any lock, and one refused item refuses the whole call.
List<ItemLanding> planItemMove(
  WriteSession session,
  List<String> addresses, {
  required String under,
  String? codeTarget,
}) {
  final index = session.index;
  final sources = _distinct([
    for (final address in addresses) _targetOf(session, address, codeTarget),
  ]);
  final destination = session.target(under, codeTarget: codeTarget);
  final located = [for (final source in sources) _locate(index, source)];
  final moving = [
    for (final item in located)
      if (item.target.doc.docPath != destination.docPath) item,
  ];
  if (moving.isEmpty) return const [];
  for (final item in moving) {
    _requireSection(index, destination, item);
  }
  _requireChains(index, destination, moving);
  return _landings(index, destination, moving);
}

ItemTarget _targetOf(WriteSession session, String address, String? codeTarget) {
  final (:docPart, :sectionKey) = session.index.splitAddress(address);
  if (sectionKey == null || sectionKey.isEmpty) {
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      '$address names no item ID after #',
    );
  }
  final doc = session.target(docPart, codeTarget: codeTarget);
  return ItemTarget(doc: doc, id: sectionKey);
}

List<ItemTarget> _distinct(List<ItemTarget> targets) {
  final seen = <String>{};
  return [
    for (final target in targets)
      if (seen.add(_keyOf(target.doc.docPath, target.id))) target,
  ];
}

String _keyOf(String docPath, String id) => '$docPath#$id';

/// An item found in its source doc, with the section it sits in.
final class _Located {
  const new(this.target, this.sectionAt, this.key, this.prefix);

  final ItemTarget target;

  /// The index of the item's section among the held sections of its doc.
  final int sectionAt;

  /// The key and ID prefix of the item's section.
  final String key;
  final String prefix;
}

_Located _locate(DocIndex index, ItemTarget target) {
  final content = index.contentOf(target.doc);
  final sections = citedSectionsOf(content, index.typeOf(target.doc));
  for (final (at, section) in sections.indexed) {
    final prefix = section.prefixId;
    if (prefix == null) continue;
    final holds = content.itemFacts.sectionItems[at].any(
      (fact) => fact.id == target.id,
    );
    if (holds) return _Located(target, at, section.key, prefix);
  }
  throw WriteFault(
    WriteFaultCode.itemNotFound,
    '${target.doc.docPath} holds no ${target.id}',
  );
}

void _requireSection(DocIndex index, IndexedDoc destination, _Located item) {
  final type = index.typeOf(destination);
  final holds =
      type != null &&
      type.sections.any(
        (section) => section.id == item.key && section.prefixId == item.prefix,
      );
  if (holds) return;
  throw IndexFault(
    IndexFaultCode.argumentInvalid,
    '${destination.docPath} takes no ${item.target.id}: its doc type has no '
    '${item.key} section numbered ${item.prefix}',
  );
}

/// One `Overrides:` line read: the doc that holds it and the item it links.
final class _OverrideCite {
  const new(this.doc, this.line, this.upstream, this.itemId);

  final IndexedDoc doc;
  final int line;
  final IndexedDoc upstream;
  final String itemId;

  String get lineKey => '${doc.docPath}:$line';

  String get address => _keyOf(upstream.docPath, itemId);
}

/// Refuses a move that leaves an `Overrides:` line outside its chain.
///
/// Throws [IndexFault] `argument_invalid` naming the doc of a line that links
/// a moved item while [destination] sits outside its chain, then the
/// overridden item of a moved item's own line that [destination]'s chain does
/// not hold. An own line moves with its item, so only the second rule reads
/// it.
void _requireChains(
  DocIndex index,
  IndexedDoc destination,
  List<_Located> moving,
) {
  final moved = {
    for (final item in moving) _keyOf(item.target.doc.docPath, item.target.id),
  };
  final own = [for (final item in moving) ?_ownOverrideOf(index, item)];
  final ownLines = {for (final cite in own) cite.lineKey};
  for (final doc in index.docs) {
    for (final cite in _overrideCitesOf(index, doc)) {
      if (ownLines.contains(cite.lineKey) || !moved.contains(cite.address)) {
        continue;
      }
      final chain = overrideChainOf(index, doc);
      if (!chain.contains(cite.upstream.docPath) ||
          chain.contains(destination.docPath)) {
        continue;
      }
      throw IndexFault(
        IndexFaultCode.argumentInvalid,
        '${doc.docPath} overrides ${cite.address}, and '
        '${destination.docPath} would sit outside its chain',
      );
    }
  }
  final destinationChain = overrideChainOf(index, destination);
  for (final cite in own) {
    final holder = moved.contains(cite.address)
        ? destination.docPath
        : cite.upstream.docPath;
    if (destinationChain.contains(holder)) continue;
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      '${cite.address} sits outside the chain of ${destination.docPath}, '
      'so the item that overrides it cannot move there',
    );
  }
}

List<SectionItem> _itemsOf(DocContent content, int at) =>
    sectionItemsOf(sectionBodyLines(content.sections, content.lineFacts, at));

bool _isOverrideLine(SectionItem item) =>
    item.kind == SectionItemKind.listItem &&
    item.head.startsWith(_overridesMarker);

/// Returns the `Overrides:` lines of [doc], in file order.
///
/// A line whose link names no item of a doc is left out, as it is no cite.
List<_OverrideCite> _overrideCitesOf(DocIndex index, IndexedDoc doc) {
  final type = index.typeOf(doc);
  if (type == null ||
      !carriesOverrides(type) ||
      index.set.isProjectSpecType(type)) {
    return const [];
  }
  final content = index.contentOf(doc);
  final items = [
    for (var at = 0; at < content.sections.length; at++)
      ..._itemsOf(content, at).where(_isOverrideLine),
  ];
  if (items.isEmpty) return const [];
  final lines = toLf(content.text).split('\n');
  return [
    for (final item in items)
      ?_citeAt(index, doc, content, item.line, lines[item.line - 1]),
  ];
}

/// Returns the `Overrides:` line right after the item [located], that line
/// nested under it included.
_OverrideCite? _ownOverrideOf(DocIndex index, _Located located) {
  final doc = located.target.doc;
  final content = index.contentOf(doc);
  final items = _itemsOf(content, located.sectionAt);
  final at = items.indexWhere(
    (item) =>
        itemKeyOfHead(
          item.head,
          isHeading: item.kind == SectionItemKind.heading,
          prefixId: located.prefix,
          isAcceptanceCriteria: false,
        ) ==
        located.target.id,
  );
  for (var k = at + 1; k < items.length; k++) {
    final next = items[k];
    if (_isOverrideLine(next)) {
      final lines = toLf(content.text).split('\n');
      return _citeAt(index, doc, content, next.line, lines[next.line - 1]);
    }
    if (!next.nested) return null;
  }
  return null;
}

/// Reads the item the link that opens the text after `Overrides:` on [line]
/// of [doc] names, or null when it names none.
_OverrideCite? _citeAt(
  DocIndex index,
  IndexedDoc doc,
  DocContent content,
  int line,
  String raw,
) {
  final column = _textStartOf(raw);
  final link = content.lineFacts.linkTexts
      .where((text) => text.line == line && text.column == column)
      .firstOrNull;
  final upstream = link == null ? null : index.at(link.target);
  if (link == null || upstream == null) return null;
  final upstreamContent = index.contentOf(upstream);
  final anchor = link.anchor;
  final sections = citedSectionsOf(upstreamContent, index.typeOf(upstream));
  final cite = classifyLink(
    link,
    target: anchor == null || anchor.isEmpty
        ? null
        : anchorTargetOf(upstreamContent.lineFacts, anchor),
    sectionAt: (at) => at < sections.length ? sections[at] : null,
  );
  return cite is ItemCite
      ? _OverrideCite(doc, line, upstream, cite.itemId)
      : null;
}

// The offset of the first character after `Overrides:` and its spaces.
int _textStartOf(String raw) {
  var at = raw.indexOf(_overridesMarker) + _overridesMarker.length;
  while (at < raw.length && raw[at] == ' ') {
    at++;
  }
  return at;
}

List<ItemLanding> _landings(
  DocIndex index,
  IndexedDoc destination,
  List<_Located> moving,
) {
  final taken = <String, List<IdRead>>{};
  return [
    for (final item in moving)
      ItemLanding(
        from: item.target,
        to: destination,
        sectionKey: item.key,
        newId: _landedId(
          item,
          taken.putIfAbsent(
            item.key,
            () => _idsIn(index, destination, item.key, item.prefix),
          ),
        ),
      ),
  ];
}

/// Returns the IDs of [prefix] that the section [key] of [destination] holds,
/// in file order; none when it lacks the section.
List<IdRead> _idsIn(
  DocIndex index,
  IndexedDoc destination,
  String key,
  String prefix,
) {
  final content = index.contentOf(destination);
  final sections = citedSectionsOf(content, index.typeOf(destination));
  final at = sections.indexWhere(
    (section) => section.key == key && section.prefixId == prefix,
  );
  if (at < 0) return [];
  return [
    for (final item in _itemsOf(content, at)) ?readItemId(item.head, prefix),
  ];
}

/// Returns the ID [item] holds once it lands among [taken], and adds it.
///
/// An ID [taken] lacks stays. Otherwise the next free number of its prefix
/// counts the lettered IDs of [taken] and the items already landed.
String _landedId(_Located item, List<IdRead> taken) {
  final id = item.target.id;
  final clashes = taken.whereType<ItemId>().any((held) => held.written == id);
  final landed = clashes ? _nextFree(taken, item.prefix) : id;
  taken.add(
    readItemId(landed, item.prefix) ??
        (throw StateError('$landed does not read as an ID of ${item.prefix}')),
  );
  return landed;
}

String _nextFree(List<IdRead> taken, String prefix) {
  final probe = [
    ...taken,
    LetteredId(prefix: prefix, digits: '0', letters: 'x'),
  ];
  return nextFreeIds(probe)[probe.length - 1] ??
      (throw StateError('no next free ID of $prefix'));
}
