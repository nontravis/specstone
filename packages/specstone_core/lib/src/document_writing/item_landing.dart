import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_items.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/doc_model/list_block_writer.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/document_writing/move_item.dart';
import 'package:specstone_core/src/document_writing/moved_paths.dart'
    show rebasedHref;
import 'package:specstone_core/src/document_writing/rewrite_refs.dart'
    show TextEdit;
import 'package:specstone_core/src/document_writing/scenario_items.dart'
    show landedScenarioHeading;
import 'package:specstone_core/src/document_writing/set_doc.dart'
    show markDraft;
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_facts.dart'
    show sectionItemsAt;
import 'package:specstone_core/src/index_query/item_links.dart'
    show CitedSection, citedSectionsOf;
import 'package:specstone_core/src/index_query/override_chain.dart';
import 'package:specstone_core/src/rendering/formatter.dart' show headerKey;
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

// MARK: - Landing edits

const _overridesKey = 'overrides';

/// Returns, by DocPath, the draft-marking edit of each doc the non-empty
/// [landings] change.
///
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
  final destination = landings.first.to;
  final entries = _entryMovesOf(index, destination, cuts);
  final bySource = <String, List<_Cut>>{};
  for (final cut in cuts) {
    bySource.putIfAbsent(cut.landing.from.doc.docPath, () => []).add(cut);
  }
  return {
    for (final MapEntry(:key, :value) in bySource.entries)
      key: _sourceEdit(
        index,
        value,
        entries.dropsOf(key),
        bodies[key],
        droppedLines[key] ?? const {},
      ),
    destination.docPath: _destinationEdit(
      index,
      destination,
      cuts,
      entries.adds,
      bodies[destination.docPath],
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
ItemSpan itemSpanOf(DocIndex index, ItemLanding landing) {
  final located = locateItem(index, landing.from);
  final content = index.contentOf(landing.from.doc);
  final items = sectionItemsAt(
    content,
    located.sectionAt,
    index.typeOf(landing.from.doc),
  );
  final at = itemIndexOf(items, located);
  return ItemSpan(
    located: located,
    head: items[at],
    first: items[at].line,
    last: _spanEnd(content, located.sectionAt, items, at),
  );
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
  final LocatedItem located;

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
  final bySource = <IndexedDoc, List<OverrideCite>>{};
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
      for (final cite in overrideCitesOf(index, source))
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

TextEdit _sourceEdit(
  DocIndex index,
  List<_Cut> cuts,
  Set<String> drops,
  String? body,
  Set<int> dropped,
) {
  final doc = cuts.first.landing.from.doc;
  final type = _typeOf(index, doc);
  final expected = toLf(index.contentOf(doc).text);
  final backwards = [...cuts]..sort((a, b) => b.first.compareTo(a.first));
  final staying = _descending([
    for (final line in dropped)
      if (!cuts.any((cut) => cut.first <= line && line <= cut.last)) line,
  ]);
  return (lfText) {
    requireUnchanged(doc, expected, lfText);
    final lines = (body ?? lfText).split('\n');
    var next = 0;
    for (final cut in backwards) {
      for (; next < staying.length && staying[next] > cut.last; next++) {
        _dropLine(lines, staying[next] - 1);
      }
      _removeLines(lines, cut.first, cut.last);
    }
    for (; next < staying.length; next++) {
      _dropLine(lines, staying[next] - 1);
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
  String? body,
) {
  final type = _typeOf(index, destination);
  final expected = toLf(index.contentOf(destination).text);
  final insertions = _insertionsOf(index, destination, cuts);
  final present = [
    for (final insertion in insertions)
      if (insertion.anchor != null) insertion,
  ]..sort((a, b) => b.anchor!.compareTo(a.anchor!));
  return (lfText) {
    requireUnchanged(destination, expected, lfText);
    final lines = (body ?? lfText).split('\n');
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
  DocIndex index,
  IndexedDoc destination,
  List<_Cut> cuts,
) {
  final byKey = <String, List<_Cut>>{};
  for (final cut in cuts) {
    byKey.putIfAbsent(cut.located.key, () => []).add(cut);
  }
  final content = index.contentOf(destination);
  final type = index.typeOf(destination);
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
