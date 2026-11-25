import 'dart:convert';

import 'package:specstone_core/src/consistency_check/item_id_rules.dart'
    show idsInDoc;
import 'package:specstone_core/src/consistency_check/models/id_at.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_items.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart'
    show MatchedDocType;
import 'package:specstone_core/src/doc_model/list_block_writer.dart';
import 'package:specstone_core/src/doc_model/models/destination_kind.dart';
import 'package:specstone_core/src/doc_model/models/id_read.dart';
import 'package:specstone_core/src/doc_model/models/section_item.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/document_writing/models/text_edit.dart';
import 'package:specstone_core/src/document_writing/move_item.dart';
import 'package:specstone_core/src/document_writing/moved_paths.dart'
    show rebasedHref;
import 'package:specstone_core/src/document_writing/retired_ids.dart';
import 'package:specstone_core/src/document_writing/scenario_items.dart'
    show landedScenarioHeading;
import 'package:specstone_core/src/document_writing/set_doc.dart'
    show markDraft;
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_facts.dart'
    show itemKeyOfHead, sectionItemsAt;
import 'package:specstone_core/src/index_query/item_links.dart'
    show citedSectionsOf;
import 'package:specstone_core/src/index_query/models/cited_section.dart';
import 'package:specstone_core/src/index_query/override_chain.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart'
    show withTemplateSection;
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

// MARK: - Landing edits

const _overridesKey = 'overrides';

/// Returns, by DocPath, the edit of each doc [landings] change, each landing
/// in its own destination doc and marking each doc it changes draft, and of
/// each doc [orders] reorders.
///
/// [orders] gives, by DocPath, the items of a doc in the order they take; the
/// items of one section take the places that section's items of [orders] hold.
/// An edit refuses a doc that changed since the plan. [bodies] gives, by
/// DocPath, the text a doc holds in place of its indexed text, with every line
/// where the index has it, so a landing carries the reference rewrites of its
/// lines. [droppedLines] gives, by a source doc's DocPath, file lines that go:
/// one inside a moved item leaves it as it lands, any other leaves the source.
/// Throws [RenderFault] `output_not_writable` for `overrides` entries that
/// are not valid YAML.
Map<String, TextEdit> itemLandingEdits(
  WriteSession session,
  List<ItemLanding> landings, {
  Map<String, String> bodies = const {},
  Map<String, Set<int>> droppedLines = const {},
  Map<String, List<ItemTarget>> orders = const {},
}) {
  final index = session.index;
  final renamed = _renamedOf(landings);
  final cuts = [
    for (final landing in landings)
      _cutOf(
        index,
        landing,
        bodies,
        droppedLines,
        renamed[landing.from.doc.docPath] ?? const {},
      ),
  ];
  final entries = _entryMovesOf(index, cuts);
  final docs = <String, IndexedDoc>{};
  final created = <String, DocContent>{};
  final leaving = <String, List<_Cut>>{};
  final landing = <String, List<_Cut>>{};
  for (final cut in cuts) {
    final from = cut.landing.from.doc;
    final to = cut.landing.to;
    docs[from.docPath] = from;
    docs[to.docPath] = to;
    leaving.putIfAbsent(from.docPath, () => []).add(cut);
    landing.putIfAbsent(to.docPath, () => []).add(cut);
    if (cut.landing.created case final doc?) created[to.docPath] = doc.content;
  }
  for (final MapEntry(key: docPath, value: order) in orders.entries) {
    docs[docPath] = order.first.doc;
  }
  return {
    for (final MapEntry(key: docPath, value: doc) in docs.entries)
      docPath: _docEdit(
        index,
        doc,
        content: created[docPath] ?? index.contentOf(doc),
        leaving: leaving[docPath] ?? const [],
        landing: landing[docPath] ?? const [],
        drops: entries.dropsOf(docPath),
        adds: entries.addsOf(docPath),
        body: bodies[docPath],
        dropped: droppedLines[docPath] ?? const {},
        slots: _slotsOf(index, orders[docPath] ?? const []),
      ),
  };
}

/// Returns, by a source doc's DocPath, the new ID of each item of it that
/// [landings] renumber, by its old ID; scenarios left out.
Map<String, Map<String, String>> _renamedOf(List<ItemLanding> landings) {
  final renamed = <String, Map<String, String>>{};
  for (final landing in landings) {
    if (landing.isScenario || landing.newId == landing.from.id) continue;
    (renamed[landing.from.doc.docPath] ??= {})[landing.from.id] = landing.newId;
  }
  return renamed;
}

/// The file lines an item spans in its source doc.
final class ItemSpan {
  const new({
    required this.located,
    required this.head,
    required this.first,
    required this.last,
  });

  final LocatedItem located;

  /// The item's first list item or heading.
  final SectionItem head;

  /// The first and last file line the item spans, nested items and its own
  /// `Overrides:` line included.
  final int first;
  final int last;
}

/// Returns the lines the item [landing] moves spans in its source doc.
ItemSpan itemSpanOf(DocIndex index, ItemLanding landing) =>
    _spanOf(index, locateItem(index, landing.from));

ItemSpan _spanOf(DocIndex index, LocatedItem located) {
  final doc = located.target.doc;
  final content = index.contentOf(doc);
  final items = sectionItemsAt(content, located.sectionAt, index.typeOf(doc));
  final at = itemIndexOf(items, located);
  return ItemSpan(
    located: located,
    head: items[at],
    first: items[at].line,
    last: _spanEnd(content, located.sectionAt, items, at),
  );
}

/// Returns the ID of each unit of the held section [sectionAt] of [content],
/// a doc of [type] whose items carry IDs of [prefix], in file order.
///
/// A unit is an item no earlier item's span holds; a nested item moves with
/// the unit that holds it.
List<String> unitIdsIn(
  DocContent content,
  int sectionAt,
  MergedDocType? type,
  String prefix,
) {
  final items = sectionItemsAt(content, sectionAt, type);
  return [
    for (final at in _unitsAt(content, sectionAt, items))
      ?_idOf(items[at], prefix),
  ];
}

/// Returns the unit whose span holds the item [located] names; null when that
/// item is a unit itself.
SectionItem? holderOf(DocIndex index, LocatedItem located) {
  final doc = located.target.doc;
  final content = index.contentOf(doc);
  final items = sectionItemsAt(content, located.sectionAt, index.typeOf(doc));
  final at = itemIndexOf(items, located);
  final holder = _unitsAt(
    content,
    located.sectionAt,
    items,
  ).lastWhere((unit) => unit <= at);
  return holder == at ? null : items[holder];
}

/// Returns the ID of each item the span of the item [located] names holds
/// below its head, in file order; an edge case or scenario holds none.
List<String> nestedIdsOf(DocIndex index, LocatedItem located) {
  if (located.isScenario || isPositionalPrefix(located.prefix)) return const [];
  final span = _spanOf(index, located);
  final doc = located.target.doc;
  final items = sectionItemsAt(
    index.contentOf(doc),
    located.sectionAt,
    index.typeOf(doc),
  );
  return [
    for (final item in items)
      if (item.line > span.first && item.line <= span.last)
        ?_idOf(item, located.prefix),
  ];
}

/// Returns the index of each unit of [items], the held section [sectionAt] of
/// [content], in file order.
List<int> _unitsAt(DocContent content, int sectionAt, List<SectionItem> items) {
  final units = <int>[];
  var at = 0;
  while (at >= 0 && at < items.length) {
    units.add(at);
    final last = _spanEnd(content, sectionAt, items, at);
    at = items.indexWhere((item) => item.line > last, at + 1);
  }
  return units;
}

String? _idOf(SectionItem item, String prefix) => itemKeyOfHead(
  item.head,
  isHeading: item.kind == SectionItemKind.heading,
  prefixId: prefix,
  isAcceptanceCriteria: false,
);

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
    required this.nestedIds,
  });

  final ItemLanding landing;
  final LocatedItem located;

  /// The IDs of the items nested in the item, which leave with it.
  final List<String> nestedIds;

  /// The first and last file line the item spans, nested items and its own
  /// `Overrides:` line included.
  final int first;
  final int last;
  final SectionItemKind kind;

  /// The spanned lines with the landing's ID and the rebased override link.
  final List<String> lines;

  /// The `Overrides:` line right after the item; null when it has none.
  final OverrideCite? own;
}

/// Cuts the item [landing] moves, its heading renumbered and, for a
/// scenario, each item ID of [renamed] in its title set to the new one.
_Cut _cutOf(
  DocIndex index,
  ItemLanding landing,
  Map<String, String> bodies,
  Map<String, Set<int>> droppedLines,
  Map<String, String> renamed,
) {
  final span = itemSpanOf(index, landing);
  final located = span.located;
  final head = span.head;
  final last = span.last;
  final doc = landing.from.doc;
  final own = ownOverrideOf(index, located)?.cite;
  final indexed = toLf(index.contentOf(doc).text).split('\n');
  final lines = (bodies[doc.docPath]?.split('\n') ?? indexed).sublist(
    head.line - 1,
    last,
  );
  if (located.isScenario) {
    lines[0] = landedScenarioHeading(lines[0], landing, renamed);
  } else if (landing.newId != landing.from.id) {
    lines[0] = _withId(
      lines[0],
      at: _idAt(indexed[head.line - 1], head.head),
      id: landing.from.id,
      newId: landing.newId,
    );
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
    lines: _withoutLines(
      lines,
      head.line,
      droppedLines[doc.docPath] ?? const {},
    ),
    own: own,
    nestedIds: nestedIdsOf(index, located),
  );
}

/// Returns [lines], whose first is file line [firstLine], without the file
/// lines [dropped] names.
List<String> _withoutLines(
  List<String> lines,
  int firstLine,
  Set<int> dropped,
) {
  final kept = [...lines];
  for (final line in _descending(dropped)) {
    final at = line - firstLine;
    if (at >= 0 && at < kept.length) _dropLine(kept, at);
  }
  return kept;
}

List<int> _descending(Iterable<int> lines) =>
    lines.toList()..sort((a, b) => b.compareTo(a));

/// Removes the line at [at] of [lines]; a blank line before it and one after
/// it, or the end, leave one blank line, or none at the end.
void _dropLine(List<String> lines, int at) {
  lines.removeAt(at);
  final isBlankBefore = at > 0 && _isBlank(lines[at - 1]);
  final isBlankAfter = at == lines.length || _isBlank(lines[at]);
  if (isBlankBefore && isBlankAfter) lines.removeAt(at - 1);
}

/// Returns the last file line of the item at [at] of [items], the nested items
/// it spans and the `Overrides:` line right after it included; a heading item
/// spans its block (see [_blockEnd]).
int _spanEnd(
  DocContent content,
  int sectionAt,
  List<SectionItem> items,
  int at,
) {
  final head = items[at];
  if (head.kind == SectionItemKind.heading) {
    return _blockEnd(content, sectionAt, head.line);
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

/// Returns the last non-blank file line of the block whose heading is file
/// line [headLine]: up to the next unfenced [opensHeadingItem] line, as
/// `check` reads a block, or the section's last.
int _blockEnd(DocContent content, int sectionAt, int headLine) {
  final body = sectionBodyLines(content.sections, content.lineFacts, sectionAt);
  final next = body
      .where((line) => line.line > headLine)
      .where((line) => !line.fenced && opensHeadingItem(line.text))
      .firstOrNull;
  var end = next == null ? body.last.line : next.line - 1;
  while (end > headLine && _isBlank(body[end - body.first.line].text)) {
    end--;
  }
  return end;
}

bool _isBlank(String line) => line.trim().isEmpty;

/// Returns the offset of the ID in [raw], the file line whose tail is [head].
int _idAt(String raw, String head) =>
    raw.length - head.length + (head.startsWith('**') ? 2 : 0);

/// Returns [raw] with [id], which starts at [at], set to [newId].
String _withId(
  String raw, {
  required int at,
  required String id,
  required String newId,
}) {
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
  final path = destination.substring(
    0,
    destinationPartsOf(destination, DestinationKind.inline).pathEnd,
  );
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

  /// The entries each destination doc gains, as written, by its DocPath.
  final Map<String, List<Object?>> adds;

  Set<String> dropsOf(String docPath) => drops[docPath] ?? const {};

  List<Object?> addsOf(String docPath) => adds[docPath] ?? const [];
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
/// the same item, and each destination takes it unless it holds one for that
/// item already.
_EntryMoves _entryMovesOf(DocIndex index, List<_Cut> cuts) {
  final bySource = <IndexedDoc, List<_Cut>>{};
  for (final cut in cuts) {
    if (cut.own != null) {
      bySource.putIfAbsent(cut.landing.from.doc, () => []).add(cut);
    }
  }
  if (bySource.isEmpty) return const _EntryMoves(drops: {}, adds: {});
  final held = <String, Set<String>>{};
  Set<String> heldIn(ItemLanding landing) => held.putIfAbsent(
    landing.to.docPath,
    () => {
      for (final entry in _overridesIn(
        landing.to.docPath,
        toLf(landing.destinationContentOf(index).text),
      ).entries)
        ?_identityOfEntry(entry),
    },
  );
  final drops = <String, Set<String>>{};
  final adds = <String, List<Object?>>{};
  for (final MapEntry(key: source, value: moved) in bySource.entries) {
    final movedLines = {for (final cut in moved) cut.own!.lineKey};
    final staying = {
      for (final cite in overrideCitesOf(index, source))
        if (!movedLines.contains(cite.lineKey)) linkIdentityOf(cite.entryLabel),
    };
    final recorded = _overridesIn(
      source.docPath,
      toLf(index.contentOf(source).text),
    ).entries;
    for (final cut in moved) {
      final identity = linkIdentityOf(cut.own!.entryLabel);
      final entry = recorded
          .where((entry) => _identityOfEntry(entry) == identity)
          .firstOrNull;
      if (entry == null) continue;
      if (!staying.contains(identity)) {
        drops.putIfAbsent(source.docPath, () => {}).add(identity);
      }
      if (heldIn(cut.landing).add(identity)) {
        adds.putIfAbsent(cut.landing.to.docPath, () => []).add(entry);
      }
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

/// Returns the edit of [doc], which the items of [leaving] leave, the items of
/// [landing] land in, and each of [slots] gives its place to another item.
///
/// The lines of [body], else of the text, change from the last up, so each
/// change keeps the file lines above it where the index has them. A doc that
/// items leave also loses the [dropped] lines outside them. [content] is the
/// doc before the call. A doc an item leaves or lands in is marked draft.
TextEdit _docEdit(
  DocIndex index,
  IndexedDoc doc, {
  required DocContent content,
  required List<_Cut> leaving,
  required List<_Cut> landing,
  required Set<String> drops,
  required List<Object?> adds,
  required String? body,
  required Set<int> dropped,
  required List<_Slot> slots,
}) {
  final type = _typeOf(index, doc);
  final gone = leaving.isEmpty ? const <int>{} : dropped;
  final expected = toLf(content.text);
  final insertions = _insertionsOf(content, index.typeOf(doc), landing);
  final changes = <_LineChange>[
    for (final cut in leaving)
      _LineChange(
        cut.first,
        (lines) => _removeLines(lines, cut.first, cut.last),
      ),
    for (final line in gone)
      if (!leaving.any((cut) => cut.first <= line && line <= cut.last) &&
          !slots.any((slot) => slot.first <= line && line <= slot.last))
        _LineChange(line, (lines) => _dropLine(lines, line - 1)),
    for (final insertion in insertions)
      if (insertion.anchor case final anchor?)
        // They land after the anchor line, below a change that starts there.
        _LineChange(
          anchor + 0.5,
          (lines) => lines.insertAll(anchor, insertion.lines),
        ),
  ]..sort((a, b) => b.at.compareTo(a.at));
  return (lfText) {
    requireUnchanged(doc, expected, lfText);
    final read = (body ?? lfText).split('\n');
    final lines = _withSlotMarks(read, slots);
    for (final change in changes) {
      change.apply(lines);
    }
    var text = _withSlotsFilled(lines, read, slots, gone).join('\n');
    for (final insertion in insertions) {
      if (insertion.anchor != null) continue;
      text = withTemplateSection(
        text,
        type,
        insertion.key,
        insertion.lines.join('\n'),
      );
    }
    text = _withoutEntries(doc.docPath, text, drops);
    text = _withEntries(doc.docPath, text, adds, type);
    text = _withRetired(doc.docPath, text, leaving);
    return leaving.isEmpty && landing.isEmpty ? text : markDraft(text, type);
  };
}

/// Returns [lfText], the text of the doc at [docPath], with the ID of each
/// item of [leaving] that is no edge case or scenario, and of each item
/// nested in it, added to its `retired_ids`.
///
/// Throws as [RetiredIds.writeInto] does.
String _withRetired(String docPath, String lfText, List<_Cut> leaving) {
  final retired = [
    for (final cut in leaving) ...[
      if (!cut.landing.isPositional) cut.landing.from.id,
      ...cut.nestedIds,
    ],
  ];
  if (retired.isEmpty) return lfText;
  return RetiredIds.readFrom(lfText)
      .grownBy(retired)
      .writeInto(lfText, docPath: docPath);
}

// MARK: - Position numbers

/// Returns [lfText], a doc of [type], with each edge case and scenario
/// numbered by its position in its section: its ID and its list ordinal.
///
/// An item whose number already equals its position keeps its ID as written.
String numberedByPosition(String lfText, MergedDocType type) {
  final content = parseIndexedDoc(
    docPath: _numberedDocPath,
    bytes: utf8.encode(lfText),
    match: MatchedDocType(type),
  ).content;
  final lines = lfText.split('\n');
  final sections = <String, List<IdAt>>{};
  for (final item in idsInDoc(content, type)) {
    if (isPositionalPrefix(item.prefix)) {
      (sections[item.sectionKey] ??= []).add(item);
    }
  }
  for (final held in sections.values) {
    final width = positionWidthOf(held.first.prefix, [
      for (final item in held) item.id,
    ]);
    for (final (at, item) in held.indexed) {
      lines[item.line - 1] = _numberedLine(
        lines[item.line - 1],
        item.id,
        at + 1,
        width,
      );
    }
  }
  return lines.join('\n');
}

// Only item IDs and lines are read, so the placeholder doc path changes no
// result.
const _numberedDocPath = 'doc.md';

/// Returns [raw], an item's first line whose ID reads [id], with its ID and
/// list ordinal set to [position].
String _numberedLine(String raw, IdRead? id, int position, int width) {
  final digits = positionDigitsOf(id, position, width);
  var line = raw;
  if (id != null && digits != null) {
    final at = line.indexOf(id.written);
    line = line.replaceRange(at, at + id.written.length, '${id.prefix}$digits');
  }
  final ordinal = listOrdinalOf(line);
  if (ordinal == null || ordinal == position) return line;
  return line.replaceFirst(_leadingDigits, '$position');
}

final _leadingDigits = RegExp(r'^\d+');

// MARK: - Item order

/// The lines of one item a reorder places where another item of its section
/// stood.
final class _Slot {
  const new(this.first, this.last, this.item);

  /// The first and last file line of the place.
  final int first;
  final int last;

  /// The item that takes the place.
  final ItemSpan item;
}

/// Returns the places [order] gives its items: per section, the k-th place in
/// file order goes to the k-th item of [order]; a place its own item keeps is
/// left out.
List<_Slot> _slotsOf(DocIndex index, List<ItemTarget> order) {
  final bySection = <int, List<ItemSpan>>{};
  for (final target in order) {
    final span = _spanOf(index, locateItem(index, target));
    bySection.putIfAbsent(span.located.sectionAt, () => []).add(span);
  }
  return [
    for (final ordered in bySection.values)
      for (final (k, place)
          in (ordered.toList()..sort((a, b) => a.first.compareTo(b.first)))
              .indexed)
        if (ordered[k].first != place.first)
          _Slot(place.first, place.last, ordered[k]),
  ];
}

const _slotMark = '\u0000slot ';
const _goneMark = '\u0000gone';

/// Returns [lines] with the first line of each of [slots] set to a mark that
/// names it and every other line of it set to a mark that drops it.
List<String> _withSlotMarks(List<String> lines, List<_Slot> slots) {
  final marked = [...lines];
  for (final (k, slot) in slots.indexed) {
    marked[slot.first - 1] = '$_slotMark$k';
    for (var line = slot.first; line < slot.last; line++) {
      marked[line] = _goneMark;
    }
  }
  return marked;
}

/// Returns [lines] with each slot mark replaced by the lines of [read], the
/// file lines, its item spans, less the [gone] lines in it.
List<String> _withSlotsFilled(
  List<String> lines,
  List<String> read,
  List<_Slot> slots,
  Set<int> gone,
) => [
  for (final line in lines)
    if (line == _goneMark)
      ...const <String>[]
    else if (line.startsWith(_slotMark))
      ..._itemLines(
        read,
        slots[int.parse(line.substring(_slotMark.length))],
        gone,
      )
    else
      line,
];

List<String> _itemLines(List<String> read, _Slot slot, Set<int> gone) {
  final span = slot.item;
  return _withoutLines(
    read.sublist(span.first - 1, span.last),
    span.first,
    gone,
  );
}

/// One change of a doc's lines, at file line [at].
final class _LineChange {
  const new(this.at, this.apply);

  final num at;
  final void Function(List<String> lines) apply;
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

MergedDocType _typeOf(DocIndex index, IndexedDoc doc) =>
    index.typeOf(doc) ?? (throw StateError('${doc.docPath} has no doc type'));

/// Throws [RenderFault] `output_not_writable` when [lfText] is not the
/// [expected] text [doc] held when the move was planned.
void requireUnchanged(IndexedDoc doc, String expected, String lfText) {
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
  DocContent content,
  MergedDocType? type,
  List<_Cut> cuts,
) {
  final byKey = <String, List<_Cut>>{};
  for (final cut in cuts) {
    byKey.putIfAbsent(cut.located.key, () => []).add(cut);
  }
  final held = citedSectionsOf(content, type);
  return [
    for (final MapEntry(:key, :value) in byKey.entries)
      _insertionIn(content, type, held, key, value),
  ];
}

_Insertion _insertionIn(
  DocContent content,
  MergedDocType? type,
  List<CitedSection> held,
  String key,
  List<_Cut> cuts,
) {
  final located = cuts.first.located;
  final at = held.indexWhere(
    (section) => located.isTakenBy(section.key, section.prefixId),
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
      sectionItemsAt(content, at, type).lastOrNull?.kind ??
      SectionItemKind.paragraph;
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
