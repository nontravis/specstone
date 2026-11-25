import 'package:specstone_core/src/consistency_check/item_id_rules.dart'
    show idsInDoc;
import 'package:specstone_core/src/consistency_check/models/id_at.dart';
import 'package:specstone_core/src/doc_model/doc_items.dart';
import 'package:specstone_core/src/doc_model/models/doc_address.dart';
import 'package:specstone_core/src/doc_model/models/id_read.dart';
import 'package:specstone_core/src/doc_model/models/section_item.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/document_writing/item_landing.dart'
    show nestedIdsOf;
import 'package:specstone_core/src/document_writing/retired_ids.dart';
import 'package:specstone_core/src/document_writing/scenario_items.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_facts.dart'
    show itemKeyOfHead, sectionItemsAt;
import 'package:specstone_core/src/index_query/item_links.dart'
    show citedSectionsOf;
import 'package:specstone_core/src/index_query/models/link_cite.dart';
import 'package:specstone_core/src/index_query/override_chain.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// One item a `move` call names: the doc that holds it and its ID there.
final class ItemTarget {
  const new({required this.doc, required this.id});

  final IndexedDoc doc;
  final String id;
}

/// A doc the call creates, which items land in though no index holds it.
final class CreatedDoc {
  const new({required this.doc, required this.content, required this.chain});

  final IndexedDoc doc;

  /// The content of its skeleton.
  final DocContent content;

  /// The DocPaths its `Overrides:` lines may link, as [overrideChainOf] gives.
  final Set<String> chain;
}

/// Where one item of a `move` call lands.
final class ItemLanding {
  const new({
    required this.from,
    required this.to,
    required this.sectionKey,
    required this.newId,
    this.created,
  });

  /// The item and its source doc.
  final ItemTarget from;

  /// The doc the item lands in.
  final IndexedDoc to;

  /// The key of the section the item leaves and lands in.
  final String sectionKey;

  /// The ID the item holds in [to]: an edge case's or a scenario's position
  /// once [numberByPosition] numbers it; any other its own, or the next free
  /// number there.
  final String newId;

  /// [to] as the call creates it; null for a doc the index holds.
  final CreatedDoc? created;

  /// Returns the content of [to] before the call.
  DocContent destinationContentOf(DocIndex index) =>
      created?.content ?? index.contentOf(to);

  /// Whether the item is a scenario, `S<N>`, of a story's acceptance criteria.
  bool get isScenario => sectionKey == acceptanceSectionId;

  /// Whether the item's ID is its position: an edge case or a scenario.
  bool get isPositional =>
      isScenario ||
      isPositionalPrefix(readItemIdOfWrittenPrefix(from.id)?.prefix ?? '');

  /// Returns this landing with [id] as its [newId].
  ItemLanding withNewId(String id) => ItemLanding(
    from: from,
    to: to,
    sectionKey: sectionKey,
    newId: id,
    created: created,
  );
}

/// Whether [address] names an item: its text after `#` reads whole as an
/// item ID and its whole text names no doc.
///
/// A `#<section key>`, and a path whose file name holds `#`, stay doc targets.
bool isItemAddress(DocIndex index, String address) {
  final key = index.splitAddress(address).sectionKey;
  if (key == null) return false;
  final id = readItemIdOfWrittenPrefix(key);
  return id is ItemId && id.written == key;
}

/// Returns where each item [addresses] name lands in [destination], in the
/// order given, writing nothing; an item already there or named twice leaves
/// no landing.
///
/// A scenario target `S<N>` of a story rides the same plan; each edge case
/// and scenario keeps its ID until [numberByPosition] numbers every landing
/// of the call. [created] holds [destination] when the call creates it.
/// Throws [WriteFault] `item_not_found` or an [IndexFault] before any lock;
/// one refused item refuses the call.
List<ItemLanding> planItemLandings(
  WriteSession session,
  List<String> addresses, {
  required IndexedDoc destination,
  CreatedDoc? created,
  String? codeTarget,
}) => _landingsIn(
  session,
  _sourcesOf(session, addresses, codeTarget),
  destination,
  created,
);

List<ItemTarget> _sourcesOf(
  WriteSession session,
  List<String> addresses,
  String? codeTarget,
) => _distinct([
  for (final address in addresses) _targetOf(session, address, codeTarget),
]);

List<ItemLanding> _landingsIn(
  WriteSession session,
  List<ItemTarget> sources,
  IndexedDoc destination,
  CreatedDoc? created,
) {
  final index = session.index;
  final located = [for (final source in sources) locateItem(index, source)];
  final moving = [
    for (final item in located)
      if (item.target.doc.docPath != destination.docPath) item,
  ];
  if (moving.isEmpty) return const [];
  for (final item in moving) {
    _requireSection(index, destination, item);
  }
  _requireChains(
    index,
    destination,
    moving,
    created?.chain ?? overrideChainOf(index, destination),
  );
  requireRulesTravel(index, moving);
  return _landings(index, destination, moving, created);
}

ItemTarget _targetOf(WriteSession session, String address, String? codeTarget) {
  final DocAddress(:docPart, :sectionKey) = session.index.splitAddress(address);
  if (sectionKey == null || sectionKey.isEmpty) {
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      '$address names no item ID after #',
    );
  }
  final doc = session.target(docPart, codeTarget: codeTarget);
  final isScenario = doc.docTypeId == storyType && isScenarioId(sectionKey);
  return ItemTarget(
    doc: doc,
    id: isScenario ? scenarioIdByValue(sectionKey) : sectionKey,
  );
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
  const new(
    this.target,
    this.sectionAt,
    this.key,
    this.prefix, {
    this.isScenario = false,
  });

  final ItemTarget target;

  /// The index of the item's section among the held sections of its doc.
  final int sectionAt;

  /// The key of the item's section and the prefix of the item's ID.
  final String key;
  final String prefix;

  /// Whether the item is a scenario, whose section carries no ID prefix.
  final bool isScenario;

  /// The key the index holds the item by: its ID, or `Scenario <N>`.
  String get heldAs => isScenario ? scenarioKeyOfId(target.id) : target.id;

  /// Whether a section of [sectionKey] whose items carry [prefixId] takes the
  /// item.
  bool isTakenBy(String sectionKey, String? prefixId) =>
      sectionKey == key && prefixId == (isScenario ? null : prefix);
}

/// Returns the item [target] names in its source doc, a scenario of a story
/// included.
///
/// Throws [WriteFault] `item_not_found` when the doc holds no such item.
LocatedItem locateItem(DocIndex index, ItemTarget target) {
  if (isScenarioId(target.id) && target.doc.docTypeId == storyType) {
    return locateScenario(index, target);
  }
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
  throw itemNotFoundOf(target);
}

/// Returns the fault for a source doc that holds no item [target] names.
WriteFault itemNotFoundOf(ItemTarget target) => WriteFault(
  WriteFaultCode.itemNotFound,
  '${target.doc.docPath} holds no ${target.id}',
);

/// Throws [IndexFault] `argument_invalid` when [destination]'s doc type gives
/// [item] no section, a scenario taking a story alone.
void _requireSection(DocIndex index, IndexedDoc destination, LocatedItem item) {
  final type = index.typeOf(destination);
  final holds =
      type != null &&
      (!item.isScenario || destination.docTypeId == storyType) &&
      type.sections.any(
        (section) => item.isTakenBy(section.id, section.prefixId),
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
  Set<String> destinationChain,
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
      ...sectionItemsAt(content, at, index.typeOf(doc)).where(isOverrideLine),
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
            isAcceptanceCriteria: located.isScenario,
          ) ==
          located.heldAs,
    );

/// Returns the `Overrides:` line right after the item [located], that line
/// nested under it included; for a heading item, the first one in its block.
OwnLine? ownOverrideOf(DocIndex index, LocatedItem located) {
  final doc = located.target.doc;
  final content = index.contentOf(doc);
  final items = sectionItemsAt(content, located.sectionAt, index.typeOf(doc));
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
    final endsItem = isBlock ? opensHeadingItem(next.firstLine) : !next.nested;
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
  CreatedDoc? created,
) {
  final content = created?.content ?? index.contentOf(destination);
  final type = index.typeOf(destination);
  final retired = RetiredIds.readFrom(toLf(content.text)).ids;
  final taken = <String, List<IdRead>>{};
  final landings = <ItemLanding>[];
  for (final item in moving) {
    final held = taken.putIfAbsent(
      item.key,
      () => _idsIn(content, type, item.key, item.prefix),
    );
    _takeNested(index, item, destination, held, retired);
    landings.add(
      ItemLanding(
        from: item.target,
        to: destination,
        sectionKey: item.key,
        newId: _landedId(item, held, retired),
        created: created,
      ),
    );
  }
  return landings;
}

/// Adds to [taken] the ID of each item nested in [item], which lands with it
/// in [destination].
///
/// Throws [IndexFault] `argument_invalid` for a nested ID that [taken] holds
/// or [retired] lists.
void _takeNested(
  DocIndex index,
  LocatedItem item,
  IndexedDoc destination,
  List<IdRead> taken,
  Set<String> retired,
) {
  for (final id in nestedIdsOf(index, item)) {
    final isHeld =
        retired.contains(id) ||
        taken.whereType<ItemId>().any((held) => held.written == id);
    if (isHeld) {
      throw IndexFault(
        IndexFaultCode.argumentInvalid,
        '${destination.docPath} already holds or retired $id, nested in '
        '${_keyOf(item.target.doc.docPath, item.target.id)}',
      );
    }
    if (readItemId(id, item.prefix) case final read?) taken.add(read);
  }
}

/// Returns the IDs of [prefix] that the section [key] of a doc of [type]
/// whose content is [content] holds, in file order; none when it lacks the
/// section.
List<IdRead> _idsIn(
  DocContent content,
  MergedDocType? type,
  String key,
  String prefix,
) {
  final sections = citedSectionsOf(content, type);
  final at = sections.indexWhere(
    (section) => section.key == key && section.prefixId == prefix,
  );
  if (at < 0) return [];
  return [
    for (final item in sectionItemsAt(content, at, type))
      ?readItemId(item.head, prefix),
  ];
}

/// Returns the ID [item] holds once it lands among [taken], and adds it.
///
/// An edge case or a scenario keeps its ID until [numberByPosition] numbers
/// it. Any other ID stays unless [taken] holds it or [retired] lists it; then
/// it takes the next free number of its prefix, counting the lettered IDs of
/// [taken], the items already landed, and [retired].
String _landedId(LocatedItem item, List<IdRead> taken, Set<String> retired) {
  final id = item.target.id;
  if (item.isScenario || isPositionalPrefix(item.prefix)) return id;
  final clashes =
      retired.contains(id) ||
      taken.whereType<ItemId>().any((held) => held.written == id);
  final landed = clashes ? _nextFree(taken, item.prefix, retired) : id;
  taken.add(
    readItemId(landed, item.prefix) ??
        (throw StateError('$landed does not read as an ID of ${item.prefix}')),
  );
  return landed;
}

String _nextFree(List<IdRead> taken, String prefix, Set<String> retired) {
  final probe = [
    ...taken,
    LetteredId(prefix: prefix, digits: '0', letters: 'x'),
  ];
  return nextFreeIds(probe, retired: retired)[probe.length - 1] ??
      (throw StateError('no next free ID of $prefix'));
}

// MARK: - Position numbers

/// The new IDs one doc's edge cases and scenarios take by position in a move.
final class Renumbering {
  const new({required this.docPath, required this.oldToNew});

  /// The DocPath of the doc whose items it numbers.
  final String docPath;

  /// The new ID of each item that stays in the doc and takes a new number, by
  /// its old ID; a scenario's written `S<N>`.
  final Map<String, String> oldToNew;
}

/// The landings of a move, each edge case and scenario at its position, and
/// one [Renumbering] per doc the move numbers.
final class PositionNumbers {
  const new({required this.landings, required this.renumberings});

  final List<ItemLanding> landings;
  final List<Renumbering> renumberings;
}

/// Numbers by position the edge cases and scenarios of each doc that
/// [landings] add one to or take one from, and of each of [kept].
///
/// Each section's items that stay come first, in file order or, for a doc of
/// [orders], in that order; the items landing in it follow in [landings]
/// order. A doc of [kept] whose numbers and list ordinals already equal their
/// positions gets no [Renumbering].
PositionNumbers numberByPosition(
  DocIndex index,
  List<ItemLanding> landings, {
  Map<String, List<ItemTarget>> orders = const {},
  List<IndexedDoc> kept = const [],
}) {
  final positional = [
    for (final landing in landings)
      if (landing.isPositional) landing,
  ];
  final changed = _docsOf(positional);
  final docs = {
    ...changed,
    for (final doc in [...kept, for (final o in orders.values) o.first.doc])
      if (!changed.containsKey(doc.docPath)) doc.docPath: doc,
  };
  final newIds = <ItemLanding, String>{};
  final renumberings = <Renumbering>[];
  for (final MapEntry(key: docPath, value: doc) in docs.entries) {
    final numbers = _DocNumbering.of(
      index,
      doc,
      positional,
      orders[docPath] ?? const [],
    ).number();
    newIds.addAll(numbers.landed);
    if (changed.containsKey(docPath) || numbers.isOutOfPlace) {
      renumberings.add(
        Renumbering(docPath: docPath, oldToNew: numbers.oldToNew),
      );
    }
  }
  return PositionNumbers(
    landings: [
      for (final landing in landings)
        landing.withNewId(newIds[landing] ?? landing.newId),
    ],
    renumberings: renumberings,
  );
}

/// Returns each doc [landings] leave or land in, by DocPath.
Map<String, IndexedDoc> _docsOf(List<ItemLanding> landings) => {
  for (final landing in landings) ...{
    landing.from.doc.docPath: landing.from.doc,
    landing.to.docPath: landing.to,
  },
};

/// Returns the digits an edge case or scenario whose ID reads [id] takes at
/// [position], padded to [width]; null when [id] holds that number already or
/// reads as no ID.
String? positionDigitsOf(IdRead? id, int position, int width) => switch (id) {
  ItemId(:final number) when number == BigInt.from(position) => null,
  ItemId() || LetteredId() => '$position'.padLeft(width, '0'),
  _ => null,
};

/// Returns the digit count a section of position IDs of [prefix] numbers its
/// [ids] with: a scenario's is never padded, and an edge case's is that of the
/// widest of [ids], 2 at the least, so the first reads `E01`.
int positionWidthOf(String prefix, Iterable<IdRead?> ids) {
  if (prefix != edgeCaseIdPrefix) return 1;
  return ids.fold(
    _edgeCaseWidth,
    (width, id) => switch (id) {
      ItemId(:final digits) ||
      LetteredId(:final digits) when digits.length > width => digits.length,
      _ => width,
    },
  );
}

const _edgeCaseWidth = 2;

final _listOrdinal = RegExp(r'^(\d+)[.)]\s');

/// Returns the list ordinal [line] opens with, such as `2` of `2. E02 — …`;
/// null when it opens with none.
int? listOrdinalOf(String line) => switch (_listOrdinal.firstMatch(line)) {
  final match? => int.parse(match.group(1)!),
  null => null,
};

/// One edge case or scenario of a numbered section: one that stays, at its
/// file line, or one that lands.
final class _Numbered {
  const new(this.id, {this.held, this.landing});

  /// The ID as an address writes it: `E03`, or `S3` for a scenario.
  final IdRead? id;
  final IdAt? held;
  final ItemLanding? landing;
}

/// What numbering one doc gives: each landing's new ID, each staying item's,
/// and whether any number or list ordinal was out of place.
final class _DocNumbers {
  new(this._lines);

  /// The doc's LF lines before the call.
  final List<String> _lines;
  final landed = <ItemLanding, String>{};
  final oldToNew = <String, String>{};
  var _isOrdinalOff = false;

  bool get isOutOfPlace => _isOrdinalOff || oldToNew.isNotEmpty;

  /// Numbers [section], items of IDs of [prefix], in the order it holds them.
  void addSection(List<_Numbered> section, String prefix) {
    final width = positionWidthOf(prefix, [
      for (final item in section) item.id,
    ]);
    for (final (at, item) in section.indexed) {
      _add(item, at + 1, width);
    }
  }

  void _add(_Numbered item, int position, int width) {
    final held = item.held;
    if (held != null) {
      final ordinal = listOrdinalOf(_lines[held.line - 1]);
      _isOrdinalOff |= ordinal != null && ordinal != position;
    }
    final id = item.id;
    final digits = positionDigitsOf(id, position, width);
    if (id == null || digits == null) return;
    final newId = '${id.prefix}$digits';
    if (item.landing case final landing?) landed[landing] = newId;
    if (held != null) oldToNew[id.written] = newId;
  }
}

/// Numbers the edge cases and scenarios of one doc after a move.
final class _DocNumbering {
  const new(
    this.index,
    this.doc, {
    required this.leaving,
    required this.landing,
    required this.order,
  });

  /// Numbers [doc], which the items of [positional] may leave or land in, its
  /// kept items in [order].
  factory of(
    DocIndex index,
    IndexedDoc doc,
    List<ItemLanding> positional,
    List<ItemTarget> order,
  ) => _DocNumbering(
    index,
    doc,
    leaving: [
      for (final landing in positional)
        if (landing.from.doc.docPath == doc.docPath) landing,
    ],
    landing: [
      for (final landing in positional)
        if (landing.to.docPath == doc.docPath) landing,
    ],
    order: order,
  );

  final DocIndex index;
  final IndexedDoc doc;
  final List<ItemLanding> leaving;
  final List<ItemLanding> landing;
  final List<ItemTarget> order;

  _DocNumbers number() {
    final content =
        landing.firstOrNull?.destinationContentOf(index) ??
        index.contentOf(doc);
    final numbers = _DocNumbers(toLf(content.text).split('\n'));
    for (final MapEntry(key: sectionKey, value: section) in _sectionsOf(
      content,
    ).entries) {
      numbers.addSection(
        section,
        sectionKey == acceptanceSectionId ? scenarioIdPrefix : edgeCaseIdPrefix,
      );
    }
    return numbers;
  }

  /// Returns each numbered section's items in the order they take, by key.
  Map<String, List<_Numbered>> _sectionsOf(DocContent content) {
    final type = index.typeOf(doc);
    if (type == null) return const {};
    final gone = {for (final item in leaving) _headLineOf(item.from)};
    final sections = <String, List<_Numbered>>{};
    for (final held in idsInDoc(content, type)) {
      if (!isPositionalPrefix(held.prefix) || gone.contains(held.line)) {
        continue;
      }
      (sections[held.sectionKey] ??= []).add(
        _Numbered(_addressIdOf(held.id), held: held),
      );
    }
    final ordered = [for (final target in order) _headLineOf(target)];
    for (final section in sections.values) {
      _reorder(section, ordered);
    }
    for (final item in landing) {
      (sections[item.sectionKey] ??= []).add(
        _Numbered(readItemIdOfWrittenPrefix(item.from.id), landing: item),
      );
    }
    return sections;
  }

  /// Gives the places of [section] whose item [ordered] names to those items,
  /// in the order of [ordered], the file lines of their heads.
  void _reorder(List<_Numbered> section, List<int> ordered) {
    final byLine = {for (final item in section) item.held!.line: item};
    final inOrder = [for (final line in ordered) ?byLine[line]];
    final places = [
      for (final (at, item) in section.indexed)
        if (ordered.contains(item.held!.line)) at,
    ];
    for (final (k, at) in places.indexed) {
      section[at] = inOrder[k];
    }
  }

  int _headLineOf(ItemTarget target) {
    final located = locateItem(index, target);
    final items = sectionItemsAt(
      index.contentOf(target.doc),
      located.sectionAt,
      index.typeOf(target.doc),
    );
    return items[itemIndexOf(items, located)].line;
  }
}

/// Returns [id] as an address writes it: a scenario's `Scenario 3` as `S3`.
IdRead? _addressIdOf(IdRead? id) => switch (id) {
  ItemId(prefix: scenarioIdPrefix, :final digits) => ItemId(
    prefix: _scenarioRefPrefix,
    digits: digits,
  ),
  LetteredId(prefix: scenarioIdPrefix, :final digits, :final letters) =>
    LetteredId(prefix: _scenarioRefPrefix, digits: digits, letters: letters),
  _ => id,
};

const _scenarioRefPrefix = 'S';
