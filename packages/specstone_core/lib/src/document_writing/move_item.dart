import 'package:specstone_core/src/doc_model/doc_items.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_facts.dart'
    show itemKeyOfHead, sectionItemsAt;
import 'package:specstone_core/src/index_query/item_links.dart'
    show ItemCite, citedSectionsOf;
import 'package:specstone_core/src/index_query/override_chain.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';

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
/// the order given, writing nothing; an item already there or named twice
/// leaves no landing.
///
/// Throws [WriteFault] `item_not_found` or an [IndexFault] before any lock;
/// one refused item refuses the call.
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
  final located = [for (final source in sources) locateItem(index, source)];
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
final class LocatedItem {
  const new(this.target, this.sectionAt, this.key, this.prefix);

  final ItemTarget target;

  /// The index of the item's section among the held sections of its doc.
  final int sectionAt;

  /// The key and ID prefix of the item's section.
  final String key;
  final String prefix;
}

LocatedItem locateItem(DocIndex index, ItemTarget target) {
  final content = index.contentOf(target.doc);
  final sections = citedSectionsOf(content, index.typeOf(target.doc));
  for (final (at, section) in sections.indexed) {
    final prefix = section.prefixId;
    if (prefix == null) continue;
    final holds = content.itemFacts.sectionItems[at].any(
      (fact) => fact.id == target.id,
    );
    if (holds) return LocatedItem(target, at, section.key, prefix);
  }
  throw WriteFault(
    WriteFaultCode.itemNotFound,
    '${target.doc.docPath} holds no ${target.id}',
  );
}

void _requireSection(DocIndex index, IndexedDoc destination, LocatedItem item) {
  final type = index.typeOf(destination);
  final holds =
      type != null &&
      type.sections.any(
        (section) => section.id == item.key && section.prefixId == item.prefix,
      );
  if (holds) return;
  throw IndexFault(
    IndexFaultCode.argumentInvalid,
    '${destination.docPath} has no ${item.key} section for ${item.prefix} '
    'items',
  );
}

/// One `Overrides:` line read: the doc that holds it and the item it links.
final class OverrideCite {
  const new(this.doc, this.line, this.upstream, this.itemId);

  final IndexedDoc doc;
  final int line;
  final IndexedDoc upstream;
  final String itemId;

  String get lineKey => '${doc.docPath}:$line';

  String get address => _keyOf(upstream.docPath, itemId);

  /// The label of the `overrides` entry that records the linked item.
  String get entryLabel => '${upstream.docTypeId}:${upstream.name}#$itemId';
}

/// Refuses a move that leaves an `Overrides:` line outside its chain.
///
/// Throws [IndexFault] `argument_invalid`: first for a line that links a moved
/// item while [destination] sits outside its chain, then for a moved item's
/// own line, which moves with it, linking an item [destination]'s chain lacks.
void _requireChains(
  DocIndex index,
  IndexedDoc destination,
  List<LocatedItem> moving,
) {
  final moved = {
    for (final item in moving) _keyOf(item.target.doc.docPath, item.target.id),
  };
  final own = [for (final item in moving) ?ownOverrideOf(index, item)];
  final ownLines = {for (final line in own) line.cite.lineKey};
  for (final doc in index.docs) {
    for (final cite in overrideCitesOf(index, doc)) {
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
        '${doc.docPath} overrides ${cite.address}; '
        '${destination.docPath} sits outside its chain',
      );
    }
  }
  final destinationChain = overrideChainOf(index, destination);
  for (final line in own) {
    final cite = line.cite;
    final holder = moved.contains(cite.address)
        ? destination.docPath
        : cite.upstream.docPath;
    if (destinationChain.contains(holder)) continue;
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      '${_keyOf(line.item.target.doc.docPath, line.item.target.id)} '
      'overrides ${cite.address}, outside the chain of '
      '${destination.docPath}',
    );
  }
}

/// Returns the `Overrides:` lines of [doc] that link an item, in file order.
List<OverrideCite> overrideCitesOf(DocIndex index, IndexedDoc doc) {
  if (!holdsOverrideLines(index, doc)) return const [];
  final content = index.contentOf(doc);
  final items = [
    for (var at = 0; at < content.sections.length; at++)
      ...sectionItemsAt(content, at).where(isOverrideLine),
  ];
  if (items.isEmpty) return const [];
  final lines = toLf(content.text).split('\n');
  return [
    for (final item in items)
      ?_citeAt(index, doc, content, item.line, lines[item.line - 1]),
  ];
}

/// A moved item and the `Overrides:` line right after it.
final class OwnLine {
  const new(this.item, this.cite);

  final LocatedItem item;
  final OverrideCite cite;
}

/// Returns the index of the item [located] names among [items], its section's.
int itemIndexOf(List<SectionItem> items, LocatedItem located) =>
    items.indexWhere(
      (item) =>
          itemKeyOfHead(
            item.head,
            isHeading: item.kind == SectionItemKind.heading,
            prefixId: located.prefix,
            isAcceptanceCriteria: false,
          ) ==
          located.target.id,
    );

/// Returns the `Overrides:` line right after the item [located], that line
/// nested under it included; for a heading item, the first one in its block.
OwnLine? ownOverrideOf(DocIndex index, LocatedItem located) {
  final doc = located.target.doc;
  final content = index.contentOf(doc);
  final items = sectionItemsAt(content, located.sectionAt);
  final at = itemIndexOf(items, located);
  final isBlock = items[at].kind == SectionItemKind.heading;
  for (var k = at + 1; k < items.length; k++) {
    final next = items[k];
    if (isOverrideLine(next)) {
      final lines = toLf(content.text).split('\n');
      final cite = _citeAt(
        index,
        doc,
        content,
        next.line,
        lines[next.line - 1],
      );
      return cite == null ? null : OwnLine(located, cite);
    }
    final endsItem = isBlock
        ? next.kind == SectionItemKind.heading
        : !next.nested;
    if (endsItem) return null;
  }
  return null;
}

/// Reads the item the link that opens the text after `Overrides:` on [line]
/// of [doc] names, or null when it names none.
OverrideCite? _citeAt(
  DocIndex index,
  IndexedDoc doc,
  DocContent content,
  int line,
  String raw,
) {
  final link = overrideLinkAt(content, line, overrideTextStart(raw));
  final read = link == null ? null : readOverrideLink(index, link);
  return switch (read) {
    OverrideLinkRead(cite: ItemCite(:final itemId), :final target) =>
      OverrideCite(doc, line, target, itemId),
    _ => null,
  };
}

List<ItemLanding> _landings(
  DocIndex index,
  IndexedDoc destination,
  List<LocatedItem> moving,
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
    for (final item in sectionItemsAt(content, at))
      ?readItemId(item.head, prefix),
  ];
}

/// Returns the ID [item] holds once it lands among [taken], and adds it.
///
/// An ID [taken] lacks stays. Otherwise the next free number of its prefix
/// counts the lettered IDs of [taken] and the items already landed.
String _landedId(LocatedItem item, List<IdRead> taken) {
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
