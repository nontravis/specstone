import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_items.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/doc_model/list_block_writer.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/document_writing/moved_paths.dart'
    show rebasedHref;
import 'package:specstone_core/src/document_writing/rewrite_refs.dart'
    show TextEdit;
import 'package:specstone_core/src/document_writing/set_doc.dart'
    show markDraft;
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_facts.dart'
    show itemKeyOfHead;
import 'package:specstone_core/src/index_query/item_links.dart'
    show CitedSection, ItemCite, citedSectionsOf;
import 'package:specstone_core/src/index_query/override_chain.dart';
import 'package:specstone_core/src/rendering/formatter.dart' show headerKey;
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

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
    '${destination.docPath} has no ${item.key} section for ${item.prefix} '
    'items',
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
  List<_Located> moving,
) {
  final moved = {
    for (final item in moving) _keyOf(item.target.doc.docPath, item.target.id),
  };
  final own = [for (final item in moving) ?_ownOverrideOf(index, item)];
  final ownLines = {for (final line in own) line.cite.lineKey};
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

List<SectionItem> _itemsOf(DocContent content, int at) =>
    sectionItemsOf(sectionBodyLines(content.sections, content.lineFacts, at));

/// Returns the `Overrides:` lines of [doc] that link an item, in file order.
List<_OverrideCite> _overrideCitesOf(DocIndex index, IndexedDoc doc) {
  if (!holdsOverrideLines(index, doc)) return const [];
  final content = index.contentOf(doc);
  final items = [
    for (var at = 0; at < content.sections.length; at++)
      ..._itemsOf(content, at).where(isOverrideLine),
  ];
  if (items.isEmpty) return const [];
  final lines = toLf(content.text).split('\n');
  return [
    for (final item in items)
      ?_citeAt(index, doc, content, item.line, lines[item.line - 1]),
  ];
}

/// A moved item and the `Overrides:` line right after it.
final class _OwnLine {
  const new(this.item, this.cite);

  final _Located item;
  final _OverrideCite cite;
}

/// Returns the index of the item [located] names among [items], its section's.
int _itemAt(List<SectionItem> items, _Located located) => items.indexWhere(
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
/// nested under it included.
_OwnLine? _ownOverrideOf(DocIndex index, _Located located) {
  final doc = located.target.doc;
  final content = index.contentOf(doc);
  final items = _itemsOf(content, located.sectionAt);
  final at = _itemAt(items, located);
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
      return cite == null ? null : _OwnLine(located, cite);
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
  final link = overrideLinkAt(content, line, overrideTextStart(raw));
  final read = link == null ? null : readOverrideLink(index, link);
  return switch (read) {
    OverrideLinkRead(cite: ItemCite(:final itemId), :final target) =>
      _OverrideCite(doc, line, target, itemId),
    _ => null,
  };
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

// MARK: - Landing edits

const _overridesKey = 'overrides';

/// Returns, by DocPath, the edit of each doc [landings] change: every source
/// doc loses its items and the destination doc gains them, each marked draft.
///
/// [landings] are the non-empty result of [planItemMove], so one destination.
/// An item lands last in its section with its nested items, its ID set to
/// the landing's; its `Overrides:` line lands right after it with its link
/// rebased, and that line's `overrides` entry follows. A doc that changed since
/// the plan is refused when its edit runs.
///
/// Throws [RenderFault] `output_not_writable` for a doc whose `overrides`
/// entries are not valid YAML.
Map<String, TextEdit> itemLandingEdits(
  WriteSession session,
  List<ItemLanding> landings,
) {
  final index = session.index;
  final cuts = [for (final landing in landings) _cutOf(index, landing)];
  final destination = landings.first.to;
  final entries = _entryMovesOf(index, destination, cuts);
  final bySource = <String, List<_Cut>>{};
  for (final cut in cuts) {
    bySource.putIfAbsent(cut.landing.from.doc.docPath, () => []).add(cut);
  }
  return {
    for (final MapEntry(:key, :value) in bySource.entries)
      key: _sourceEdit(index, value, entries.dropsOf(key)),
    destination.docPath: _destinationEdit(
      index,
      destination,
      cuts,
      entries.adds,
    ),
  };
}

/// One item cut out of its source doc, as it lands.
final class _Cut {
  const new({
    required this.landing,
    required this.located,
    required this.first,
    required this.last,
    required this.kind,
    required this.lines,
    required this.own,
  });

  final ItemLanding landing;
  final _Located located;

  /// The first and last file line the item spans, nested items and its own
  /// `Overrides:` line included.
  final int first;
  final int last;
  final SectionItemKind kind;

  /// The spanned lines with the landing's ID and the rebased override link.
  final List<String> lines;

  /// The `Overrides:` line right after the item; null when it has none.
  final _OverrideCite? own;
}

_Cut _cutOf(DocIndex index, ItemLanding landing) {
  final located = _locate(index, landing.from);
  final doc = landing.from.doc;
  final content = index.contentOf(doc);
  final items = _itemsOf(content, located.sectionAt);
  final at = _itemAt(items, located);
  final head = items[at];
  final last = _spanEnd(content, located.sectionAt, items, at);
  final own = _ownOverrideOf(index, located)?.cite;
  final lines = toLf(content.text).split('\n').sublist(head.line - 1, last);
  if (landing.newId != landing.from.id) {
    lines[0] = _withId(lines[0], head.head, landing.from.id, landing.newId);
  }
  if (own != null) {
    final ownAt = own.line - head.line;
    lines[ownAt] = _withRebasedLink(
      lines[ownAt],
      doc.docPath,
      landing.to.docPath,
    );
  }
  return _Cut(
    landing: landing,
    located: located,
    first: head.line,
    last: last,
    kind: head.kind,
    lines: lines,
    own: own,
  );
}

/// Returns the last file line of the item at [at] of [items], the nested items
/// it spans and the `Overrides:` line right after it included; a heading item
/// spans its block, up to the next heading item.
int _spanEnd(
  DocContent content,
  int sectionAt,
  List<SectionItem> items,
  int at,
) {
  final head = items[at];
  if (head.kind == SectionItemKind.heading) {
    return _blockEnd(content, sectionAt, items, at);
  }
  var last = at;
  var hasOwn = false;
  for (var k = at + 1; k < items.length; k++) {
    final next = items[k];
    if (!hasOwn && isOverrideLine(next)) {
      hasOwn = true;
    } else if (!next.nested) {
      break;
    }
    last = k;
  }
  return _endOf(items[last]);
}

int _endOf(SectionItem item) => item.line + item.text.split('\n').length - 1;

/// Returns the last non-blank file line before the next heading item after the
/// heading item at [at], or the section's last.
int _blockEnd(
  DocContent content,
  int sectionAt,
  List<SectionItem> items,
  int at,
) {
  final body = sectionBodyLines(content.sections, content.lineFacts, sectionAt);
  final next = items
      .skip(at + 1)
      .where((item) => item.kind == SectionItemKind.heading)
      .firstOrNull;
  var end = next == null ? body.last.line : next.line - 1;
  while (end > items[at].line && _isBlank(body[end - body.first.line].text)) {
    end--;
  }
  return end;
}

bool _isBlank(String line) => line.trim().isEmpty;

/// Returns [raw] with [id], where its [head] opens it, set to [newId].
String _withId(String raw, String head, String id, String newId) {
  final at = raw.length - head.length + (head.startsWith('**') ? 2 : 0);
  if (!raw.startsWith(id, at)) {
    throw StateError('$raw does not open with $id');
  }
  return raw.replaceRange(at, at + id.length, newId);
}

/// Returns the `Overrides:` line [raw] with the path of its link, written in
/// the doc at [fromDocPath], set to reach the same doc from [toDocPath].
String _withRebasedLink(String raw, String fromDocPath, String toDocPath) {
  final start = overrideTextStart(raw);
  final rest = raw.substring(start);
  final destination = readLeadingLinkTarget(rest);
  if (destination == null) return raw;
  final suffixAt = destination.indexOf(RegExp('[?#]'));
  final path = suffixAt < 0 ? destination : destination.substring(0, suffixAt);
  final rebased = rebasedHref(path, fromDocPath, toDocPath);
  if (rebased == null) return raw;
  final at = start + rest.indexOf('](') + 2;
  return raw.replaceRange(at, at + path.length, rebased);
}

// MARK: - Overrides entries

/// What an item move does to the `overrides` entries of its docs.
final class _EntryMoves {
  const new({required this.drops, required this.adds});

  /// The identities of the entries each source doc loses, by its DocPath.
  final Map<String, Set<String>> drops;

  /// The entries the destination doc gains, as written.
  final List<Object?> adds;

  Set<String> dropsOf(String docPath) => drops[docPath] ?? const {};
}

/// The `overrides` key block of a doc and its entries.
final class _Overrides {
  const new(this.block, this.entries);

  /// The key block as written; null when the doc has none.
  final KeyBlock? block;
  final List<Object?> entries;
}

_Overrides _overridesIn(String docPath, String lfText) {
  final block = (Doc.parse(lfText).frontmatter ?? const <KeyBlock>[])
      .where((block) => block.name == _overridesKey)
      .firstOrNull;
  if (block == null) return const _Overrides(null, []);
  final entries = listEntriesOf(block);
  if (entries == null) {
    throw RenderFault(
      RenderFaultCode.outputNotWritable,
      'cannot write $docPath: its $_overridesKey is not valid YAML',
    );
  }
  return _Overrides(block, entries);
}

String? _identityOfEntry(Object? entry) =>
    entry is String ? linkIdentityOf(entry.split(' ').first) : null;

/// Plans the entries of the `Overrides:` lines [cuts] carry.
///
/// An entry leaves its source doc unless another line that stays there names
/// the same item, and the destination takes it unless it holds one for that
/// item already.
_EntryMoves _entryMovesOf(
  DocIndex index,
  IndexedDoc destination,
  List<_Cut> cuts,
) {
  final bySource = <IndexedDoc, List<_OverrideCite>>{};
  for (final cut in cuts) {
    if (cut.own case final own?) {
      bySource.putIfAbsent(cut.landing.from.doc, () => []).add(own);
    }
  }
  if (bySource.isEmpty) return const _EntryMoves(drops: {}, adds: []);
  final held = {
    for (final entry in _overridesIn(
      destination.docPath,
      toLf(index.contentOf(destination).text),
    ).entries)
      ?_identityOfEntry(entry),
  };
  final drops = <String, Set<String>>{};
  final adds = <Object?>[];
  for (final MapEntry(key: source, value: moved) in bySource.entries) {
    final movedLines = {for (final own in moved) own.lineKey};
    final staying = {
      for (final cite in _overrideCitesOf(index, source))
        if (!movedLines.contains(cite.lineKey)) linkIdentityOf(cite.entryLabel),
    };
    final recorded = _overridesIn(
      source.docPath,
      toLf(index.contentOf(source).text),
    ).entries;
    for (final own in moved) {
      final identity = linkIdentityOf(own.entryLabel);
      final entry = recorded
          .where((entry) => _identityOfEntry(entry) == identity)
          .firstOrNull;
      if (entry == null) continue;
      if (!staying.contains(identity)) {
        drops.putIfAbsent(source.docPath, () => {}).add(identity);
      }
      if (held.add(identity)) adds.add(entry);
    }
  }
  return _EntryMoves(drops: drops, adds: adds);
}

String _withoutEntries(String docPath, String lfText, Set<String> identities) {
  if (identities.isEmpty) return lfText;
  final held = _overridesIn(docPath, lfText);
  final kept = [
    for (final entry in held.entries)
      if (!identities.contains(_identityOfEntry(entry))) entry,
  ];
  if (held.block == null || kept.length == held.entries.length) return lfText;
  return withKeyBlock(
    lfText,
    _overridesKey,
    kept.isEmpty ? null : listBlockOf(_overridesKey, kept, onDisk: held.block),
  );
}

String _withEntries(
  String docPath,
  String lfText,
  List<Object?> added,
  MergedDocType type,
) {
  if (added.isEmpty) return lfText;
  final held = _overridesIn(docPath, lfText);
  return withKeyBlock(
    lfText,
    _overridesKey,
    listBlockOf(_overridesKey, [...held.entries, ...added], onDisk: held.block),
    fieldOrder: [for (final field in type.fields) field.id],
  );
}

// MARK: - Source and destination edits

TextEdit _sourceEdit(DocIndex index, List<_Cut> cuts, Set<String> drops) {
  final doc = cuts.first.landing.from.doc;
  final type = _typeOf(index, doc);
  final expected = toLf(index.contentOf(doc).text);
  final backwards = [...cuts]..sort((a, b) => b.first.compareTo(a.first));
  return (lfText) {
    _requireUnchanged(doc, expected, lfText);
    final lines = lfText.split('\n');
    for (final cut in backwards) {
      _removeLines(lines, cut.first, cut.last);
    }
    final text = _withoutEntries(doc.docPath, lines.join('\n'), drops);
    return markDraft(text, type);
  };
}

/// Removes the file lines [first] to [last] from [lines]; a blank line before
/// the gap and one after it leave one blank line, not two.
void _removeLines(List<String> lines, int first, int last) {
  lines.removeRange(first - 1, last);
  if (first < 2 || !_isBlank(lines[first - 2])) return;
  // The last element is what follows the final line feed, never a line.
  while (first - 1 < lines.length - 1 && _isBlank(lines[first - 1])) {
    lines.removeAt(first - 1);
  }
}

TextEdit _destinationEdit(
  DocIndex index,
  IndexedDoc destination,
  List<_Cut> cuts,
  List<Object?> added,
) {
  final type = _typeOf(index, destination);
  final expected = toLf(index.contentOf(destination).text);
  final insertions = _insertionsOf(index, destination, cuts);
  final present = [
    for (final insertion in insertions)
      if (insertion.anchor != null) insertion,
  ]..sort((a, b) => b.anchor!.compareTo(a.anchor!));
  return (lfText) {
    _requireUnchanged(destination, expected, lfText);
    final lines = lfText.split('\n');
    for (final insertion in present) {
      lines.insertAll(insertion.anchor!, insertion.lines);
    }
    var text = lines.join('\n');
    for (final insertion in insertions) {
      if (insertion.anchor != null) continue;
      text = _withTemplateSection(text, type, insertion.key, insertion.lines);
    }
    text = _withEntries(destination.docPath, text, added, type);
    return markDraft(text, type);
  };
}

MergedDocType _typeOf(DocIndex index, IndexedDoc doc) =>
    index.typeOf(doc) ?? (throw StateError('${doc.docPath} has no doc type'));

void _requireUnchanged(IndexedDoc doc, String expected, String lfText) {
  if (lfText == expected) return;
  throw RenderFault(
    RenderFaultCode.outputNotWritable,
    'cannot write ${doc.docPath}: changed since the move was planned',
  );
}

/// The lines the destination doc gains in the section [key].
final class _Insertion {
  const new({required this.key, required this.lines, this.anchor});

  final String key;
  final List<String> lines;

  /// The file line after which [lines] land; null when the doc lacks the
  /// section and gains it with [lines] as its body.
  final int? anchor;
}

List<_Insertion> _insertionsOf(
  DocIndex index,
  IndexedDoc destination,
  List<_Cut> cuts,
) {
  final byKey = <String, List<_Cut>>{};
  for (final cut in cuts) {
    byKey.putIfAbsent(cut.located.key, () => []).add(cut);
  }
  final content = index.contentOf(destination);
  final held = citedSectionsOf(content, index.typeOf(destination));
  return [
    for (final MapEntry(:key, :value) in byKey.entries)
      _insertionIn(content, held, key, value),
  ];
}

_Insertion _insertionIn(
  DocContent content,
  List<CitedSection> held,
  String key,
  List<_Cut> cuts,
) {
  final prefix = cuts.first.located.prefix;
  final at = held.indexWhere(
    (section) => section.key == key && section.prefixId == prefix,
  );
  if (at < 0) return _Insertion(key: key, lines: _stacked(cuts, null));
  final filled = sectionBodyLines(
    content.sections,
    content.lineFacts,
    at,
  ).where((line) => !_isBlank(line.text));
  if (filled.isEmpty) {
    return _Insertion(
      key: key,
      lines: ['', ..._stacked(cuts, null)],
      anchor: content.lineFacts.sectionLines[at],
    );
  }
  final previous =
      _itemsOf(content, at).lastOrNull?.kind ?? SectionItemKind.paragraph;
  return _Insertion(
    key: key,
    lines: _stacked(cuts, previous),
    anchor: filled.last.line,
  );
}

/// Returns the lines of [cuts] one after the other: list items packed, any
/// other pair, and the first against [previous], one blank line apart.
List<String> _stacked(List<_Cut> cuts, SectionItemKind? previous) {
  final lines = <String>[];
  var before = previous;
  for (final cut in cuts) {
    final packed =
        before == SectionItemKind.listItem &&
        cut.kind == SectionItemKind.listItem;
    if (before != null && !packed) lines.add('');
    lines.addAll(cut.lines);
    before = cut.kind;
  }
  return lines;
}

/// Returns [lfText] with the template section [key] added before the first
/// held section that follows it in the template, else at the end.
String _withTemplateSection(
  String lfText,
  MergedDocType type,
  String key,
  List<String> body,
) {
  final template = type.sections.firstWhere((section) => section.id == key);
  final held = [
    for (final section in Doc.parse(lfText).sections)
      headerKey(section.headerText),
  ];
  int? before;
  for (final later in type.sections.skipWhile((s) => s.id != key).skip(1)) {
    final at = held.indexOf(headerKey(later.header));
    if (at >= 0) {
      before = at;
      break;
    }
  }
  return withSectionAdded(
    lfText,
    headerLine: '## ${template.header}',
    body: body.join('\n'),
    before: before,
  );
}
