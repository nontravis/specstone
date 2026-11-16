import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart'
    show DocTarget, projectFilePathOf, relativeFilePathOf, resolveDocLink;
import 'package:specstone_core/src/doc_model/doc_splice.dart' show withKeyBlock;
import 'package:specstone_core/src/doc_model/list_block_writer.dart';
import 'package:specstone_core/src/doc_model/name_mentions.dart'
    show NameMention, docMentionsInFile, extensionOfCodePath, readsNameMentions;
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/doc_model/task_ref.dart';
import 'package:specstone_core/src/document_writing/agent_file_walk.dart';
import 'package:specstone_core/src/document_writing/item_landing.dart';
import 'package:specstone_core/src/document_writing/move_item.dart';
import 'package:specstone_core/src/document_writing/moved_paths.dart'
    show rebasedHref, relativeHref;
import 'package:specstone_core/src/document_writing/rewrite_refs.dart'
    show TextEdit;
import 'package:specstone_core/src/document_writing/stale_mentions.dart'
    show MentionScope, StaleMention;
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/code_root_files.dart'
    show ProjectPathReader;
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/held_sections.dart'
    show sectionBodyLines;
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_links.dart';
import 'package:specstone_core/src/index_query/link_places.dart' show LinkText;
import 'package:specstone_core/src/index_query/link_scan.dart'
    show LinkScan, LinkSource, linkScanOf;
import 'package:specstone_core/src/index_query/override_chain.dart';
import 'package:specstone_core/src/plan_hash.dart' show readPlanInput;
import 'package:specstone_core/src/rendering/doc_reader.dart'
    show byteOrderMark;
import 'package:specstone_core/src/rendering/formatter.dart' show layOutDoc;
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/setup_migration/agent_targets.dart'
    show codeFilesOf;
import 'package:specstone_core/src/setup_migration/renumber_entries.dart'
    show withBlockValues;
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart'
    show FieldType;
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/template_fault.dart';

// MARK: - Edits

const _overridesKey = 'overrides';
const _separator = ', ';

/// Returns, by DocPath, the edit of every doc an item move writes: the
/// landing of [landings] and each reference that names a moved item.
///
/// A reference follows its item to the target doc and the new ID: an item
/// link, a range that holds the item, an `Overrides:` line and its `overrides`
/// entry, and a task ref. A link or range inside a moved item is read as it
/// sits in the target doc, so one that names an item of the source doc still
/// reaches it. Every doc edit refuses a doc that changed since the plan.
///
/// Throws [RenderFault] `output_not_writable` for entries that are not valid
/// YAML.
Map<String, TextEdit> itemRefEdits(
  WriteSession session,
  List<ItemLanding> landings,
) => planItemRefs(session, landings).edits;

/// What an item move writes, planned once: the edit of each doc, and the
/// references it leaves for the Agent, by DocPath.
final class ItemRefs {
  const new({required this.edits, required this.listed});

  final Map<String, TextEdit> edits;

  /// The text of each reference left as written, such as a definition that
  /// serves items that part ways, by the DocPath of the doc that holds it.
  final Map<String, List<ListedRef>> listed;
}

/// A reference an item move leaves as written: its text and the file line the
/// doc that held it before the move had it on.
final class ListedRef {
  const new(this.line, this.text);

  final int line;
  final String text;
}

/// Plans [itemRefEdits] and the references it leaves, in one read of the docs.
ItemRefs planItemRefs(WriteSession session, List<ItemLanding> landings) {
  if (landings.isEmpty) return const ItemRefs(edits: {}, listed: {});
  final index = session.index;
  final moves = _Moves(index, landings);
  final rewritten = {
    for (final doc in index.docs) doc: ?_linkBodyOf(index, doc, moves),
  };
  final landed = itemLandingEdits(
    session,
    landings,
    bodies: {
      for (final MapEntry(:key, :value) in rewritten.entries)
        key.docPath: value.after,
    },
  );
  final entries = _entryEdits(index, moves);
  final removals = <String, List<String>>{};
  for (final body in rewritten.values) {
    for (final MapEntry(key: path, value: lines) in body.removals.entries) {
      (removals[path] ??= []).addAll(lines);
    }
  }
  final paths = {
    for (final doc in rewritten.keys) doc.docPath,
    ...landed.keys,
    ...entries.keys,
    ...removals.keys,
  };
  return ItemRefs(
    edits: {
      for (final path in paths)
        path: _composed(
          index.at(path),
          [
            for (final MapEntry(:key, :value) in rewritten.entries)
              if (key.docPath == path) value,
          ].firstOrNull,
          landed[path],
          entries[path],
          removals[path] ?? const [],
        ),
    },
    listed: {
      for (final MapEntry(:key, :value) in rewritten.entries)
        if (value.listed.isNotEmpty) key.docPath: value.listed,
    },
  );
}

/// Returns the edit that runs the landing, or the link rewrite when the doc
/// has none, then drops the definition lines of [removals], then runs the
/// entry rewrite.
TextEdit _composed(
  IndexedDoc? doc,
  _Rewritten? body,
  TextEdit? landing,
  String Function(String lfText)? entries,
  List<String> removals,
) => (lfText) {
  final String text;
  if (landing != null) {
    text = landing(lfText) ?? lfText;
  } else if (body != null && doc != null) {
    requireUnchanged(doc, body.before, lfText);
    text = body.after;
  } else {
    text = lfText;
  }
  final kept = _withoutLines(text, removals);
  final result = entries?.call(kept) ?? kept;
  return result == lfText ? null : result;
};

/// Returns [lfText] without the first line equal to each of [removals]; a
/// blank line that would then stand twice stands once.
String _withoutLines(String lfText, List<String> removals) {
  if (removals.isEmpty) return lfText;
  final lines = lfText.split('\n');
  for (final text in removals) {
    final at = lines.indexOf(text);
    if (at < 0) continue;
    lines.removeAt(at);
    final isBlankBefore = at > 0 && lines[at - 1].trim().isEmpty;
    final isBlankAfter = at < lines.length && lines[at].trim().isEmpty;
    if (isBlankBefore && isBlankAfter) lines.removeAt(at - 1);
  }
  return lines.join('\n');
}

/// A doc text as the index holds it, and with its links set to their new
/// place.
final class _Rewritten {
  const new(this.before, this.after, this.listed, this.removals);

  final String before;
  final String after;
  final List<ListedRef> listed;

  /// The reference definition lines the move leaves unused, as [after] writes
  /// them, by the DocPath of the doc that holds each after the write.
  final Map<String, List<String>> removals;
}

// MARK: - Moved items

/// The lines of one moved item in its source doc.
final class _Span {
  const new({required this.first, required this.last, required this.landing});

  final int first;
  final int last;
  final ItemLanding landing;
}

/// One item as a reference names it: its doc and its ID there.
final class _Named {
  const new(this.docPath, this.id);

  final String docPath;
  final String id;
}

/// Where each moved item sits and lands, as every rewrite reads it.
final class _Moves {
  new(this.index, this.landings) {
    for (final landing in landings) {
      final docPath = landing.from.doc.docPath;
      final span = itemSpanOf(index, landing);
      byKey[_keyOf(docPath, landing.from.id)] = landing;
      (spans[docPath] ??= []).add(
        _Span(first: span.first, last: span.last, landing: landing),
      );
      prefixes.add(span.located.prefix);
      if (ownOverrideOf(index, span.located) case final own?) {
        (ownLines[docPath] ??= {}).add(own.cite.line);
      }
    }
  }

  final DocIndex index;
  final List<ItemLanding> landings;

  /// Each landing by its source doc's DocPath and the ID it moves.
  final byKey = <String, ItemLanding>{};
  final spans = <String, List<_Span>>{};
  final ownLines = <String, Set<int>>{};
  final prefixes = <String>{};

  static String _keyOf(String docPath, String id) => '$docPath#$id';

  ItemLanding? landingOf(String docPath, String id, {String? sectionKey}) {
    final landing = byKey[_keyOf(docPath, id)];
    if (landing == null) return null;
    return sectionKey == null || landing.sectionKey == sectionKey
        ? landing
        : null;
  }

  /// The span of a moved item that holds file [line] of [docPath].
  _Span? spanAt(String docPath, int line) {
    for (final span in spans[docPath] ?? const <_Span>[]) {
      if (span.first <= line && line <= span.last) return span;
    }
    return null;
  }

  /// The DocPath of the doc the text of [docPath]'s file [line] sits in once
  /// the items have moved.
  String placeOf(String docPath, int line) =>
      spanAt(docPath, line)?.landing.to.docPath ?? docPath;

  /// Whether file [line] of [docPath] is the `Overrides:` line of a moved
  /// item, which lands with its link rebased.
  bool isOwnLine(String docPath, int line) =>
      ownLines[docPath]?.contains(line) ?? false;
}

// MARK: - Links

/// A link of a doc and what it reads against the doc it reaches.
final class _ReadLink {
  const new(this.link, this.read);

  final LinkText link;
  final OverrideLinkRead read;

  ItemCite? get cite => switch (read.cite) {
    final ItemCite cite => cite,
    _ => null,
  };
}

/// One replacement in a line: the characters from [start] up to [end] take
/// [text].
final class _Edit {
  const new(this.start, this.end, this.text);

  final int start;
  final int end;
  final String text;
}

/// What one line of a doc is read against.
final class _Line {
  const new({
    required this.index,
    required this.doc,
    required this.moves,
    required this.number,
    required this.text,
  });

  final DocIndex index;
  final IndexedDoc doc;
  final _Moves moves;

  /// The file line.
  final int number;
  final String text;

  /// The DocPath of the doc this line's text sits in after the moves.
  String get place => moves.placeOf(doc.docPath, number);
}

/// Returns the LF text of [doc] with each link and range that names a moved
/// item set to its new place; null when none changes.
///
/// Every line keeps its place in the file, so the landing cuts the same lines.
_Rewritten? _linkBodyOf(DocIndex index, IndexedDoc doc, _Moves moves) {
  final lf = toLf(index.contentOf(doc).text);
  final lines = lf.split('\n');
  final plan = _linkPlanOf(index, doc, moves, lf, lines);
  if (plan.edits.isEmpty && plan.listed.isEmpty) return null;
  for (final MapEntry(key: number, value: edits) in plan.edits.entries) {
    lines[number - 1] = _withEdits(lines[number - 1], edits);
  }
  final removals = <String, List<String>>{};
  for (final number in plan.removals) {
    (removals[moves.placeOf(doc.docPath, number)] ??= []).add(
      lines[number - 1],
    );
  }
  return _Rewritten(lf, lines.join('\n'), plan.listed, removals);
}

/// What the link rewrite finds in one doc: the edits by file line, and the
/// references it leaves as written, each as the text a line holds.
final class _LinkPlan {
  final edits = <int, List<_Edit>>{};
  final listed = <ListedRef>[];

  /// The file lines of the reference definitions the move leaves unused.
  final removals = <int>[];

  /// Adds [edit] to file [line] unless an edit starts at the same column.
  void add(int line, _Edit edit) {
    final held = edits[line] ??= [];
    if (held.every((other) => other.start != edit.start)) held.add(edit);
  }
}

/// One doc body read once: its links, its prose, and where each line starts.
final class _BodyScan {
  new(this.lf);

  final String lf;
  late final String body = Doc.parse(lf).afterFrontmatter;

  /// The file line of the first body line.
  late final int firstLine =
      '\n'.allMatches(lf.substring(0, lf.length - body.length)).length + 1;
  late final LinkScan scan = linkScanOf(body, firstLine: firstLine);
  late final List<int> starts = _lineStartsOf(body);

  int _lineIndexOf(int offset) => starts.lastIndexWhere((s) => s <= offset);
  int fileLineOf(int offset) => firstLine + _lineIndexOf(offset);
  int columnOf(int offset) => offset - starts[_lineIndexOf(offset)];
}

_LinkPlan _linkPlanOf(
  DocIndex index,
  IndexedDoc doc,
  _Moves moves,
  String lf,
  List<String> lines,
) {
  final plan = _LinkPlan();
  final byLine = <int, List<_ReadLink>>{};
  for (final link in index.contentOf(doc).lineFacts.linkTexts) {
    if (moves.isOwnLine(doc.docPath, link.line)) continue;
    final read = readOverrideLink(index, link);
    if (read != null) (byLine[link.line] ??= []).add(_ReadLink(link, read));
  }
  final users = <String, List<_RefUser>>{};
  final itemLinks = <(int, int)>{};
  for (final MapEntry(key: number, value: links) in byLine.entries) {
    final line = _Line(
      index: index,
      doc: doc,
      moves: moves,
      number: number,
      text: lines[number - 1],
    );
    for (final edit in _editsOn(line, links, plan.listed)) {
      plan.add(number, edit);
    }
    for (final read in links) {
      if (read.cite == null) continue;
      itemLinks.add((number, read.link.column));
      if (_isPlain(line.text, read.link)) continue;
      if (_refUserOf(line, read) case final user?) {
        (users[user.label] ??= []).add(user);
      }
    }
  }
  final isSource = moves.spans.containsKey(doc.docPath);
  if (users.isEmpty && !isSource) return plan;
  final body = _BodyScan(lf);
  _planReferences(plan, body, lines, doc, moves, users);
  if (isSource) {
    _planRebased(plan, body, doc, moves, itemLinks);
    _planRebasedReferences(plan, body, lines, doc, moves, itemLinks);
  }
  return plan;
}

/// A reference-style item link: its label, and whether the label is its text.
final class _RefUser {
  const new(this.line, this.read, this.label, {required this.isText});

  final _Line line;
  final _ReadLink read;
  final String label;
  final bool isText;
}

String _labelKey(String label) =>
    label.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

_RefUser? _refUserOf(_Line line, _ReadLink read) {
  final link = read.link;
  final head = '[${link.text}]';
  final text = line.text;
  if (!text.startsWith(head, link.column)) return null;
  final after = link.column + head.length;
  if (!text.startsWith('[', after)) {
    return link.endColumn == after
        ? _RefUser(line, read, _labelKey(link.text), isText: true)
        : null;
  }
  final close = text.indexOf(']', after);
  if (close < 0 || link.endColumn != close + 1) return null;
  final label = text.substring(after + 1, close);
  return _RefUser(
    line,
    read,
    _labelKey(label.isEmpty ? link.text : label),
    isText: label.isEmpty,
  );
}

/// One `[label]: destination` line of a body.
final class _Definition {
  const new({
    required this.line,
    required this.labelStart,
    required this.labelEnd,
    required this.destStart,
    required this.destination,
  });

  final int line;
  final int labelStart;
  final int labelEnd;
  final int destStart;
  final String destination;
}

final _definitionOpen = RegExp(r'^ {0,3}\[((?:[^\]\\]|\\.)+)\]:\s*<?');

Map<String, _Definition> _definitionsOf(_BodyScan body, List<String> lines) {
  final found = <String, _Definition>{};
  for (final destination in body.scan.destinations) {
    if (destination.kind != DestinationKind.definition) continue;
    final number = body.fileLineOf(destination.start);
    final open = _definitionOpen.firstMatch(lines[number - 1]);
    if (open == null) continue;
    found.putIfAbsent(
      _labelKey(open.group(1)!),
      () => _Definition(
        line: number,
        labelStart: open.start + 1,
        labelEnd: open.start + 1 + open.group(1)!.length,
        destStart: body.columnOf(destination.start),
        destination: body.body.substring(destination.start, destination.end),
      ),
    );
  }
  return found;
}

/// A reference-style link of any kind: where it sits, its label, and whether
/// the label is its text.
final class _RefLink {
  const new({
    required this.line,
    required this.column,
    required this.textEnd,
    required this.end,
    required this.label,
  });

  final int line;

  /// The column of its `[`, of the `]` that ends its text, and after its end.
  final int column;
  final int textEnd;
  final int end;
  final String label;
}

/// Returns the reference-style links of [body], inline ones aside.
List<_RefLink> _refLinksOf(_BodyScan body, List<String> lines) {
  final found = <_RefLink>[];
  for (final source in body.scan.sources) {
    final textEnd = source.textEnd;
    if (source.shown == null || textEnd == null) continue;
    final number = source.line;
    if (body.fileLineOf(textEnd) != number ||
        body.fileLineOf(source.end - 1) != number) {
      continue;
    }
    final text = lines[number - 1];
    final column = body.columnOf(source.offset);
    final close = body.columnOf(textEnd);
    final end = column + (source.end - source.offset);
    final open = text.startsWith('!', column) ? column + 2 : column + 1;
    if (text.startsWith('(', close + 1)) continue;
    final written = text.substring(open, close);
    final label = text.startsWith('[', close + 1)
        ? text.substring(close + 2, end - 1)
        : written;
    found.add(
      _RefLink(
        line: number,
        column: column,
        textEnd: close,
        end: end,
        label: _labelKey(label.isEmpty ? written : label),
      ),
    );
  }
  return found;
}

/// Plans the definitions that reference-style item links share: one that
/// serves moved items alone takes the new path, and each link text and label
/// the new ID; one that serves items that part ways, or any other link, stays
/// and is listed.
void _planReferences(
  _LinkPlan plan,
  _BodyScan body,
  List<String> lines,
  IndexedDoc doc,
  _Moves moves,
  Map<String, List<_RefUser>> users,
) {
  if (users.isEmpty) return;
  final definitions = _definitionsOf(body, lines);
  final totals = <String, int>{};
  for (final link in _refLinksOf(body, lines)) {
    totals[link.label] = (totals[link.label] ?? 0) + 1;
  }
  for (final MapEntry(key: label, value: served) in users.entries) {
    final definition = definitions[label];
    if (definition == null) continue;
    final afters = [
      for (final user in served)
        _afterOf(
          user.line,
          user.read.read.target.docPath,
          user.read.cite!.sectionKey,
          user.read.cite!.itemId,
        ),
    ];
    final place = moves.placeOf(doc.docPath, definition.line);
    final first = afters.first;
    final isOneWay =
        first != null &&
        (totals[label] ?? 0) == served.length &&
        afters.every((after) => after?.docPath == first.docPath) &&
        served.every((user) => user.line.place == place);
    if (!isOneWay) {
      if (afters.any((after) => after != null)) {
        plan.listed.add(
          ListedRef(definition.line, lines[definition.line - 1].trim()),
        );
      }
      continue;
    }
    _planDefinition(plan, definition, first, place, served, afters);
  }
}

void _planDefinition(
  _LinkPlan plan,
  _Definition definition,
  _Named first,
  String place,
  List<_RefUser> served,
  List<_Named?> afters,
) {
  final at = definition.destination.indexOf(RegExp('[?#]'));
  if (at >= 0 && !_reaches(definition.destination, place, first.docPath)) {
    final path = _pathBetween(place, first);
    if (path != definition.destination.substring(0, at)) {
      plan.add(
        definition.line,
        _Edit(definition.destStart, definition.destStart + at, path),
      );
    }
  }
  for (final (index, user) in served.indexed) {
    final id = afters[index]!.id;
    final link = user.read.link;
    if (id == link.text) continue;
    plan.add(
      link.line,
      _Edit(link.column + 1, link.column + 1 + link.text.length, id),
    );
    if (user.isText) {
      plan.add(
        definition.line,
        _Edit(definition.labelStart, definition.labelEnd, id),
      );
    }
  }
}

/// Plans the relative destinations inside moved items that no item link
/// covers: each is set to reach from the target doc what it reaches from the
/// source doc.
void _planRebased(
  _LinkPlan plan,
  _BodyScan body,
  IndexedDoc doc,
  _Moves moves,
  Set<(int, int)> itemLinks,
) {
  for (final destination in body.scan.destinations) {
    final number = body.fileLineOf(destination.start);
    final span = moves.spanAt(doc.docPath, number);
    if (span == null || moves.isOwnLine(doc.docPath, number)) continue;
    if (destination.link case final at?) {
      final source = body.scan.sources[at];
      if (itemLinks.contains((source.line, body.columnOf(source.offset)))) {
        continue;
      }
    }
    final text = body.body.substring(destination.start, destination.end);
    if (readLinkTarget(text) case RelativeLink(:final pathEnd)) {
      if (_reachesSame(text, doc.docPath, span.landing.to.docPath)) continue;
      final rebased = rebasedHref(
        text.substring(0, pathEnd),
        doc.docPath,
        span.landing.to.docPath,
      );
      if (rebased == null) continue;
      final column = body.columnOf(destination.start);
      plan.add(number, _Edit(column, column + pathEnd, rebased));
    }
  }
}

String _withEdits(String text, List<_Edit> edits) {
  var result = text;
  for (final edit in [...edits]..sort((a, b) => b.start.compareTo(a.start))) {
    result = result.replaceRange(edit.start, edit.end, edit.text);
  }
  return result;
}

/// Plans the reference-style links that no item link covers and that the
/// moves land in another doc than their definition: each becomes an inline
/// link to what the definition names, as read from the doc the link lands in;
/// one whose definition carries a title stays and is listed. A definition no
/// link uses any more is removed.
void _planRebasedReferences(
  _LinkPlan plan,
  _BodyScan body,
  List<String> lines,
  IndexedDoc doc,
  _Moves moves,
  Set<(int, int)> itemLinks,
) {
  final definitions = _definitionsOf(body, lines);
  final links = _refLinksOf(body, lines);
  final converted = <String, int>{};
  for (final link in links) {
    if (moves.isOwnLine(doc.docPath, link.line)) continue;
    if (itemLinks.contains((link.line, link.column))) continue;
    final definition = definitions[link.label];
    if (definition == null) continue;
    final place = moves.placeOf(doc.docPath, link.line);
    if (place == moves.placeOf(doc.docPath, definition.line)) continue;
    if (_hasTitle(lines[definition.line - 1], definition)) {
      plan.listed.add(
        ListedRef(
          link.line,
          lines[link.line - 1].substring(link.column, link.end),
        ),
      );
      continue;
    }
    final written = _destinationFrom(
      definition.destination,
      doc.docPath,
      place,
    );
    final shown = written.contains(RegExp(r'\s')) ? '<$written>' : written;
    plan.add(link.line, _Edit(link.textEnd + 1, link.end, '($shown)'));
    converted[link.label] = (converted[link.label] ?? 0) + 1;
  }
  final totals = <String, int>{};
  for (final link in links) {
    totals[link.label] = (totals[link.label] ?? 0) + 1;
  }
  for (final MapEntry(key: label, value: count) in converted.entries) {
    if (totals[label] == count) plan.removals.add(definitions[label]!.line);
  }
}

/// Whether [definition], the definition on [line], carries a title after its
/// destination.
bool _hasTitle(String line, _Definition definition) => line
    .substring(definition.destStart + definition.destination.length)
    .replaceFirst(RegExp('^>'), '')
    .trim()
    .isNotEmpty;

/// Returns [destination], written in the doc at [from], as it reaches the same
/// target from the doc at [to]: a relative path rebased, unless it reaches the
/// same file as written; any other destination as written.
String _destinationFrom(String destination, String from, String to) {
  if (readLinkTarget(destination) case RelativeLink(:final pathEnd)
      when !_reachesSame(destination, from, to)) {
    final rebased = rebasedHref(destination.substring(0, pathEnd), from, to);
    if (rebased != null) return rebased + destination.substring(pathEnd);
  }
  return destination;
}

/// Returns the edits of the links of one [line]: one per range and one per
/// link outside a range, in no order.
List<_Edit> _editsOn(
  _Line line,
  List<_ReadLink> links,
  List<ListedRef> listed,
) {
  links.sort((a, b) => a.link.column.compareTo(b.link.column));
  final byLink = {for (final read in links) read.link: read};
  final ranges = itemRangesOn(line.text, [
    for (final read in links) (link: read.link, cite: read.read.cite),
  ]);
  final edits = <_Edit>[];
  final consumed = <LinkText>{};
  for (final range in ranges) {
    if (consumed.contains(range.first.link)) continue;
    final first = byLink[range.first.link]!;
    final ids = _spannedIds(line.index, range, first.read);
    if (ids == null) continue;
    consumed
      ..add(range.first.link)
      ..add(range.last.link);
    if (_rangeEdit(line, range, first, ids, listed) case final edit?) {
      edits.add(edit);
    }
  }
  for (final read in links) {
    if (consumed.contains(read.link) || read.cite == null) continue;
    if (_linkEdit(line, read) case final edit?) edits.add(edit);
  }
  return edits;
}

/// Returns the item [id] of [target] as it reads after the moves, with the
/// path the link to it takes from [line]; null when the link keeps its text.
///
/// A link names a moved item at its landing. Any other link inside a moved
/// item names the item it named, now from the target doc.
_Named? _afterOf(_Line line, String target, String sectionKey, String id) {
  if (line.moves.landingOf(target, id, sectionKey: sectionKey)
      case final landing?) {
    return _Named(landing.to.docPath, landing.newId);
  }
  return line.place == line.doc.docPath ? null : _Named(target, id);
}

_Edit? _linkEdit(_Line line, _ReadLink read) {
  final link = read.link;
  final cite = read.cite!;
  final after = _afterOf(
    line,
    read.read.target.docPath,
    cite.sectionKey,
    cite.itemId,
  );
  if (after == null || !_isPlain(line.text, link)) return null;
  if (after.id == link.text &&
      _reaches(link.shown, line.place, after.docPath)) {
    return null;
  }
  final written = _writtenOf(link.shown);
  final path = _pathBetween(line.place, after);
  final text = '[${after.id}]($path${written.suffix}';
  final old = '[${link.text}](${link.shown}';
  return text == old
      ? null
      : _Edit(link.column, link.column + old.length, text);
}

/// Whether [href] reaches the same file from the doc at [from] and from the
/// doc at [to], so a link moved from one to the other keeps every byte.
bool _reachesSame(String href, String from, String to) {
  final before = relativeFilePathOf(href, from);
  final after = relativeFilePathOf(href, to);
  if (before == null || after == null) return false;
  return projectFilePathOf(before, from) == projectFilePathOf(after, to);
}

/// Whether [destination], written in the doc at [place], reaches the doc at
/// [docPath] as it is, so a link keeps every byte.
bool _reaches(String destination, String place, String docPath) =>
    switch (resolveDocLink(destination, place)) {
      DocTarget(docPath: final reached) => reached == docPath,
      _ => false,
    };

/// Whether [link] is written `[text](destination` at its column.
bool _isPlain(String line, LinkText link) =>
    line.startsWith('[${link.text}](${link.shown}', link.column) &&
    link.shown.contains(RegExp('[?#]'));

/// A link destination as written, split before its `?` or `#`.
final class _Written {
  const new(this.path, this.suffix);

  final String path;
  final String suffix;
}

_Written _writtenOf(String shown) {
  final at = shown.indexOf(RegExp('[?#]'));
  return _Written(shown.substring(0, at), shown.substring(at));
}

String _pathBetween(String place, _Named after) => place == after.docPath
    ? ''
    : relativeHref(
        place,
        after.docPath,
      ).split('/').map(Uri.encodeComponent).join('/');

/// Returns the IDs [range] spans in the doc it reaches, null when it spans
/// none that can be read.
List<String>? _spannedIds(
  DocIndex index,
  ItemRange range,
  OverrideLinkRead read,
) {
  final at = switch (read.anchorTarget) {
    SectionTarget(:final sectionIndex) => sectionIndex,
    _ => null,
  };
  if (at == null || at >= read.sections.length) return null;
  final ids = itemIdsInRange(
    range,
    read.sections[at],
    index.contentOf(read.target).itemFacts.sectionItems[at],
  );
  return ids.isEmpty ? null : ids;
}

/// Returns the edit that sets the range to the links and ranges that name the
/// same items after the moves; null when it keeps its text.
_Edit? _rangeEdit(
  _Line line,
  ItemRange range,
  _ReadLink first,
  List<String> ids,
  List<ListedRef> listed,
) {
  final firstLink = range.first.link;
  final lastLink = range.last.link;
  final target = first.read.target.docPath;
  final sectionKey = range.first.cite.sectionKey;
  final afters = [for (final id in ids) _afterOf(line, target, sectionKey, id)];
  if (afters.every((after) => after == null)) return null;
  if (!_isOneLine(line.text, firstLink) || !_isOneLine(line.text, lastLink)) {
    if (firstLink.endLine == firstLink.line &&
        lastLink.endLine == lastLink.line) {
      listed.add(
        ListedRef(
          line.number,
          line.text.substring(firstLink.column, lastLink.endColumn),
        ),
      );
    }
    return null;
  }
  final steps = [
    for (final (at, id) in ids.indexed)
      _Step(afters[at] ?? _Named(target, id), id),
  ];
  final written = _writtenOf(firstLink.shown);
  final prefix = first.read.sections[_sectionAt(first.read)].prefixId;
  final closings = {
    range.first.cite.itemId: _closingOf(line.text, firstLink),
    range.last.cite.itemId: _closingOf(line.text, lastLink),
  };
  final pieces = [
    for (final run in _runs(steps))
      ..._pieces(line, run, written, closings, target, sectionKey, prefix),
  ];
  final text = pieces.join(_separator);
  final old = line.text.substring(firstLink.column, lastLink.endColumn);
  return text == old ? null : _Edit(firstLink.column, lastLink.endColumn, text);
}

int _sectionAt(OverrideLinkRead read) =>
    (read.anchorTarget! as SectionTarget).sectionIndex;

/// Whether [link] is written `[text](destination` and ends on its line.
bool _isOneLine(String line, LinkText link) =>
    link.endLine == link.line && _isPlain(line, link);

/// Returns what follows the destination of [link]: its title, if any, and the
/// closing parenthesis.
String _closingOf(String line, LinkText link) => line.substring(
  link.column + '[${link.text}](${link.shown}'.length,
  link.endColumn,
);

/// One item of a range after the moves, with the ID the range named it by.
final class _Step {
  const new(this.after, this.original);

  final _Named after;
  final String original;
}

/// Splits [steps] into runs of items that sit in one doc.
List<List<_Step>> _runs(List<_Step> steps) {
  final runs = <List<_Step>>[];
  for (final step in steps) {
    if (runs.isNotEmpty && runs.last.last.after.docPath == step.after.docPath) {
      runs.last.add(step);
    } else {
      runs.add([step]);
    }
  }
  return runs;
}

/// Returns the link, or the range, that names the items of [run].
List<String> _pieces(
  _Line line,
  List<_Step> run,
  _Written written,
  Map<String, String> closings,
  String target,
  String sectionKey,
  String? prefix,
) {
  final first = run.first.after;
  final keeps =
      first.docPath == target &&
      (line.place == line.doc.docPath ||
          _reaches(written.path + written.suffix, line.place, target));
  final path = keeps ? written.path : _pathBetween(line.place, first);
  String linkTo(_Step step) =>
      '[${step.after.id}]($path${written.suffix}'
      '${closings[step.original] ?? ')'}';
  final named = [for (final step in run) step.after];
  if (run.length > 1 && _isExactRange(line, named, sectionKey, prefix)) {
    return ['${linkTo(run.first)} to ${linkTo(run.last)}'];
  }
  return [for (final step in run) linkTo(step)];
}

/// Whether a range from the first to the last of [run] names exactly [run] in
/// its doc once the items have moved.
bool _isExactRange(
  _Line line,
  List<_Named> run,
  String sectionKey,
  String? prefix,
) {
  if (prefix == null) return false;
  final numbers = [for (final item in run) _numberOf(item.id, prefix)];
  if (numbers.any((number) => number == null)) return false;
  final low = numbers.reduce((a, b) => a! < b! ? a : b)!;
  final high = numbers.reduce((a, b) => a! > b! ? a : b)!;
  final held = _idsAfterMove(line, run.first.docPath, sectionKey, prefix);
  final between = {
    for (final id in held)
      if (_numberOf(id, prefix) case final number?)
        if (low <= number && number <= high) id,
  };
  return between.length == run.length &&
      between.containsAll([for (final item in run) item.id]);
}

BigInt? _numberOf(String id, String prefix) {
  final read = readItemId(id, prefix);
  return read is ItemId && read.written == id ? read.number : null;
}

/// Returns the IDs the section [sectionKey] of [docPath] holds after the
/// moves: its own less the items that leave it, and the IDs that land in it.
Set<String> _idsAfterMove(
  _Line line,
  String docPath,
  String sectionKey,
  String prefix,
) {
  final ids = {..._sectionIdsOf(line.index, docPath, sectionKey, prefix)};
  for (final landing in line.moves.landings) {
    if (landing.sectionKey != sectionKey) continue;
    if (landing.from.doc.docPath == docPath) ids.remove(landing.from.id);
    if (landing.to.docPath == docPath) ids.add(landing.newId);
  }
  return ids;
}

Iterable<String> _sectionIdsOf(
  DocIndex index,
  String docPath,
  String sectionKey,
  String prefix,
) {
  final doc = index.at(docPath);
  if (doc == null) return const [];
  final content = index.contentOf(doc);
  final sections = citedSectionsOf(content, index.typeOf(doc));
  final at = sections.indexWhere(
    (section) => section.key == sectionKey && section.prefixId == prefix,
  );
  if (at < 0) return const [];
  return [for (final fact in content.itemFacts.sectionItems[at]) ?fact.id];
}

// MARK: - Entries

/// Returns, by DocPath, the edit of each doc's frontmatter entries that follow
/// a moved item: an `overrides` entry that names it, and a task ref that
/// leaves its source doc for the target doc.
Map<String, String Function(String lfText)> _entryEdits(
  DocIndex index,
  _Moves moves,
) {
  final renames = <String, Map<String, String>>{};
  for (final doc in index.docs) {
    final renamed = _renamedEntries(index, doc, moves);
    if (renamed.isNotEmpty) renames[doc.docPath] = renamed;
  }
  final tasks = _taskMoves(index, moves);
  return {
    for (final path in {...renames.keys, ...tasks.keys})
      path: (lfText) {
        final renamed = renames[path];
        var text = renamed == null
            ? lfText
            : withBlockValues(
                lfText,
                _overridesKey,
                (value) => _renamedEntry(value, renamed),
              );
        if (index.at(path) case final doc?) {
          text = tasks[path]?.applyTo(text, index.typeOf(doc), path) ?? text;
        }
        return text;
      },
  };
}

/// Returns, by the identity of the label an `overrides` entry of [doc] holds,
/// the label of the moved item it names after the moves.
Map<String, String> _renamedEntries(
  DocIndex index,
  IndexedDoc doc,
  _Moves moves,
) {
  final renamed = <String, String>{};
  for (final cite in overrideCitesOf(index, doc)) {
    final landing = moves.landingOf(cite.upstream.docPath, cite.itemId);
    final typeId = landing?.to.docTypeId;
    if (landing == null || typeId == null) continue;
    renamed[linkIdentityOf(cite.entryLabel)] =
        '$typeId:${landing.to.name}#${landing.newId}';
  }
  return renamed;
}

String? _renamedEntry(String value, Map<String, String> renamed) {
  final space = value.indexOf(' ');
  final label = space < 0 ? value : value.substring(0, space);
  final to = renamed[linkIdentityOf(label)];
  if (to == null || to == label) return null;
  return space < 0 ? to : '$to${value.substring(space)}';
}

/// The task refs of one doc that leave it, and those it gains, by field.
final class _TaskMoves {
  final drops = <String, Set<String>>{};
  final adds = <String, List<String>>{};

  /// Returns [lfText] without the refs that leave and with those that join.
  String applyTo(String lfText, MergedDocType? type, String docPath) {
    var text = lfText;
    for (final field in {...drops.keys, ...adds.keys}) {
      text = _withTaskRefs(
        text,
        type,
        docPath,
        field,
        drops[field] ?? const {},
        adds[field] ?? const [],
      );
    }
    return text;
  }
}

Map<String, _TaskMoves> _taskMoves(DocIndex index, _Moves moves) {
  final byDoc = <String, _TaskMoves>{};
  for (final landing in moves.landings) {
    final source = landing.from.doc;
    final fields = [
      for (final field in index.typeOf(source)?.fields ?? const <MergedField>[])
        if (field.type == FieldType.taskRef) field.id,
    ];
    for (final field in fields) {
      if (!_holdsTaskField(index, landing.to, field)) continue;
      for (final entry in source.valuesOf(field)) {
        final ref = TaskRef.parse(entry);
        if (ref == null || ref.item != landing.from.id) continue;
        (byDoc[source.docPath] ??= _TaskMoves()).drops
            .putIfAbsent(field, () => {})
            .add(entry);
        (byDoc[landing.to.docPath] ??= _TaskMoves()).adds
            .putIfAbsent(field, () => [])
            .add('${landing.newId}:${ref.task}');
      }
    }
  }
  return byDoc;
}

bool _holdsTaskField(DocIndex index, IndexedDoc doc, String fieldId) =>
    index
        .typeOf(doc)
        ?.fields
        .any(
          (field) => field.id == fieldId && field.type == FieldType.taskRef,
        ) ??
    false;

String _withTaskRefs(
  String lfText,
  MergedDocType? type,
  String docPath,
  String field,
  Set<String> drop,
  List<String> add,
) {
  final block = (Doc.parse(lfText).frontmatter ?? const <KeyBlock>[])
      .where((candidate) => candidate.name == field)
      .firstOrNull;
  final held = block == null ? const <Object?>[] : listEntriesOf(block);
  if (held == null) {
    throw RenderFault(
      RenderFaultCode.outputNotWritable,
      'cannot write $docPath: its $field is not valid YAML',
    );
  }
  final kept = [
    for (final entry in held)
      if (!(entry is String && drop.contains(entry))) entry,
  ];
  final joined = [
    ...kept,
    for (final entry in add)
      if (!kept.contains(entry)) entry,
  ];
  if (joined.length == held.length && drop.isEmpty) return lfText;
  return withKeyBlock(
    lfText,
    field,
    joined.isEmpty ? null : listBlockOf(field, joined, onDisk: block),
    fieldOrder: [
      for (final field in type?.fields ?? const <MergedField>[]) field.id,
    ],
  );
}

// MARK: - Mentions

/// Returns the mentions an item move leaves, by file path then line: each bare
/// ID that names a moved item in its source doc, or right after that doc's
/// address, in any file; each bare ID inside a moved item that names an item
/// of its source doc that stays or that the move renumbers; and each reference
/// definition left because it serves items that part ways.
///
/// A mention in a code file or an agent file reads as a doc address and an ID.
/// A doc the move writes is read as it reads after the write, so a line is
/// where the text then lives. Nothing is written.
List<StaleMention> itemMentions(
  WriteSession session,
  List<ItemLanding> landings, {
  ItemRefs? refs,
}) {
  if (landings.isEmpty) return const [];
  final index = session.index;
  final moves = _Moves(index, landings);
  final planned = refs ?? planItemRefs(session, landings);
  final edits = planned.edits;
  final found = <StaleMention>[];
  final afters = <String, String>{};
  for (final doc in index.docs) {
    final before = toLf(index.contentOf(doc).text);
    final edit = edits[doc.docPath];
    afters[doc.docPath] = edit == null
        ? before
        : layOutDoc(edit(before) ?? before, session.docTypeAt(doc.docPath));
  }
  final landed = {
    for (final doc in index.docs)
      doc.docPath: _landedSpans(index, moves, doc, afters[doc.docPath]!),
  };
  for (final doc in index.docs) {
    final after = afters[doc.docPath]!;
    found
      ..addAll(_addressMentions(index, moves, doc.docPath, after, '.md'))
      ..addAll(_bareMentions(index, moves, doc, after, landed[doc.docPath]!))
      ..addAll(
        _listedMentions(
          index,
          moves,
          doc,
          planned.listed[doc.docPath],
          afters,
          landed,
        ),
      );
  }
  final scope = MentionScope.of(session);
  final files = _mentionFiles(scope);
  for (final projectPath in files.keys) {
    final lf = _lfTextOf(files[projectPath]!);
    if (lf == null) continue;
    found.addAll(
      _addressMentions(
        index,
        moves,
        projectPath,
        lf,
        extensionOfCodePath(projectPath),
      ),
    );
  }
  found.sort((a, b) {
    final byPath = compareCodePoints(a.path, b.path);
    return byPath != 0 ? byPath : a.line.compareTo(b.line);
  });
  return found;
}

/// Returns the lines each item that lands in [doc] spans in [lf], the doc as
/// it reads after the write.
List<_Span> _landedSpans(
  DocIndex index,
  _Moves moves,
  IndexedDoc doc,
  String lf,
) {
  final landings = [
    for (final landing in moves.landings)
      if (landing.to.docPath == doc.docPath) landing,
  ];
  if (landings.isEmpty) return const [];
  final type = index.typeOf(doc);
  final content = docStructureOf(lf, type);
  final sections = citedSectionsOf(content, type);
  final spans = <_Span>[];
  for (final landing in landings) {
    final at = sections.indexWhere(
      (section) => section.key == landing.sectionKey,
    );
    if (at < 0) continue;
    final extent = itemExtentOf(
      sectionBodyLines(content.sections, content.lineFacts, at),
      landing.newId,
      prefixId: sections[at].prefixId,
      isAcceptanceCriteria: false,
    );
    if (extent != null) {
      spans.add(
        _Span(first: extent.first, last: extent.last, landing: landing),
      );
    }
  }
  return spans;
}

/// The references [doc] keeps as written, each at the line its text sits on
/// after the write: in the doc it stayed in, or in the target doc when it sat
/// inside a moved item.
///
/// A line is found by the place of its text among the lines that hold it in
/// its region, so a repeated text lands on its own line.
List<StaleMention> _listedMentions(
  DocIndex index,
  _Moves moves,
  IndexedDoc doc,
  List<ListedRef>? listed,
  Map<String, String> afters,
  Map<String, List<_Span>> landed,
) {
  if (listed == null) return const [];
  final before = toLf(index.contentOf(doc).text).split('\n');
  final movedBefore = _linesOf(moves.spans[doc.docPath] ?? const []);
  final afterLines = <String, List<String>>{};
  final landedLines = <String, Set<int>>{};
  final mentions = <StaleMention>[];
  for (final ref in listed) {
    final span = moves.spanAt(doc.docPath, ref.line);
    final path = span?.landing.to.docPath ?? doc.docPath;
    final after = afterLines[path] ??= afters[path]!.split('\n');
    final landedAfter = landedLines[path] ??= _linesOf(landed[path]!);
    final region = span == null
        ? null
        : landed[path]!.where((s) => s.landing == span.landing).firstOrNull;
    final nth = _linesHolding(
      before,
      ref.text,
      span?.first ?? 1,
      span?.last ?? before.length,
      (line) => span != null || !movedBefore.contains(line),
    ).where((line) => line < ref.line).length;
    final lines = _linesHolding(
      after,
      ref.text,
      region?.first ?? 1,
      region?.last ?? after.length,
      (line) => span != null || !landedAfter.contains(line),
    );
    final line = nth < lines.length
        ? lines[nth]
        : lines.lastOrNull ?? region?.first ?? ref.line;
    mentions.add((path: path, line: line, mention: ref.text));
  }
  return mentions;
}

/// Returns every file line [spans] cover.
Set<int> _linesOf(List<_Span> spans) => {
  for (final span in spans)
    for (var at = span.first; at <= span.last; at++) at,
};

/// Returns the file lines from [first] to [last] of [lines] that hold [text]
/// and that [isKept] keeps.
List<int> _linesHolding(
  List<String> lines,
  String text,
  int first,
  int last,
  bool Function(int line) isKept,
) => [
  for (var at = first; at <= last && at <= lines.length; at++)
    if (lines[at - 1].contains(text) && isKept(at)) at,
];

/// The mentions of [lf] that read `<doc address>#<ID>` and name a moved item.
List<StaleMention> _addressMentions(
  DocIndex index,
  _Moves moves,
  String path,
  String lf,
  String extension,
) => [
  for (final mention in docMentionsInFile(lf, extension))
    if (_namesMovedItem(index, moves, mention))
      (path: path, line: mention.line, mention: mention.text),
];

bool _namesMovedItem(DocIndex index, _Moves moves, NameMention mention) {
  final key = mention.address.sectionKey;
  if (key == null || key.isEmpty) return false;
  return [
    for (final doc in _resolved(index, mention.address.docPart))
      if (moves.landingOf(doc.docPath, key) != null) doc,
  ].isNotEmpty;
}

List<IndexedDoc> _resolved(DocIndex index, String address) {
  try {
    return index.resolve(address);
  } on IndexFault {
    return const [];
  } on TemplateFault {
    return const [];
  }
}

/// The bare IDs of the prose of [doc], as [lf] reads after the write, that
/// name a moved item; [spans] are the lines of the moved items [doc] holds.
List<StaleMention> _bareMentions(
  DocIndex index,
  _Moves moves,
  IndexedDoc doc,
  String lf,
  List<_Span> spans,
) {
  final body = _BodyScan(lf);
  final prose = _outsideLinks(body.scan.prose, body.scan.sources);
  final lines = body.body.split('\n');
  final skippedHeads = <_Span>{};
  final mentions = <StaleMention>[];
  for (final (:at, :id) in itemIdsInProse(prose, prefixes: moves.prefixes)) {
    final number = body.fileLineOf(at);
    final span = spans
        .where((span) => span.first <= number && number <= span.last)
        .firstOrNull;
    if (span != null &&
        number == span.first &&
        id.written == span.landing.newId &&
        skippedHeads.add(span)) {
      continue;
    }
    final lineIndex = number - body.firstLine;
    final cited = _citedBefore(
      index,
      doc,
      body.scan.sources,
      lines[lineIndex],
      body.columnOf(at),
      body.starts[lineIndex],
    );
    if (_namesMoved(index, moves, doc, cited, id.written, span)) {
      mentions.add((path: doc.docPath, line: number, mention: id.written));
    }
  }
  return mentions;
}

/// Whether the bare ID [id], cited by the doc at [cited] or by none, is one
/// the move leaves a mention for; [span] is the moved item that holds it.
bool _namesMoved(
  DocIndex index,
  _Moves moves,
  IndexedDoc doc,
  String? cited,
  String id,
  _Span? span,
) {
  final authored = span?.landing.from.doc ?? doc;
  final landing = moves.landingOf(cited ?? authored.docPath, id);
  if (cited != null || span == null) return landing != null;
  if (landing != null) return landing.newId != id;
  return _holdsItem(index, authored, id);
}

/// Whether some section of [doc] holds the item [id].
bool _holdsItem(DocIndex index, IndexedDoc doc, String id) => index
    .contentOf(doc)
    .itemFacts
    .sectionItems
    .any((items) => items.any((fact) => fact.id == id));

/// Returns [prose] with each of [sources] blanked, line ends kept.
String _outsideLinks(String prose, List<LinkSource> sources) {
  final units = prose.codeUnits.toList();
  for (final source in sources) {
    for (var at = source.offset; at < source.end && at < units.length; at++) {
      if (units[at] != 0x0A) units[at] = 0x20;
    }
  }
  return String.fromCharCodes(units);
}

List<int> _lineStartsOf(String text) => [
  0,
  for (var at = 0; at < text.length; at++)
    if (text.codeUnitAt(at) == 0x0A) at + 1,
];

/// Returns the DocPath the nearest doc address or doc link before [column] of
/// [line] names, the empty string for one that names no doc, or null when none
/// precedes it.
String? _citedBefore(
  DocIndex index,
  IndexedDoc doc,
  List<LinkSource> sources,
  String line,
  int column,
  int lineStart,
) {
  String? cited;
  var nearest = -1;
  for (final (:start, :end, :ticks) in codeSpansOf(line)) {
    if (start >= column || start < nearest) continue;
    final address = readDocAddress(line.substring(start + ticks, end - ticks));
    if (address.sectionKey != null || !address.isReferenceWithoutLookup) {
      continue;
    }
    final docs = _resolved(index, address.docPart);
    cited = docs.length == 1 ? docs.single.docPath : '';
    nearest = start;
  }
  for (final source in sources) {
    final shown = source.shown;
    final start = source.offset - lineStart;
    if (shown == null || start < 0 || start >= column || start < nearest) {
      continue;
    }
    if (source.offset >= lineStart + line.length) continue;
    cited = switch (resolveDocLink(shown, doc.docPath)) {
      DocTarget(:final docPath) => docPath,
      _ => '',
    };
    nearest = start;
  }
  return cited;
}

/// Returns the code files and agent files whose mentions are read, by their
/// path from the project root.
Map<String, File> _mentionFiles(MentionScope scope) {
  final files = <String, File>{};
  final paths = ProjectPathReader(
    projectRoot: scope.projectRoot,
    docsRoot: scope.docsRoot,
  );
  for (final (root: codeRoot, path: codePath) in codeFilesOf(
    scope.projectRoot,
    scope.set,
    targets: scope.targets,
    moves: scope.docMoves,
  )) {
    if (!readsNameMentions(extensionOfCodePath(codePath))) continue;
    final projectPath = paths.projectPathOf(codePath, codeRoot);
    if (projectPath == null) continue;
    files[projectPath] = _fileIn(codeRoot, codePath);
  }
  for (final path in agentFilesOf(
    scope.projectRoot,
    scope.agentFileRoots,
    scope.runGit,
  )) {
    if (!readsNameMentions(extensionOfCodePath(path))) continue;
    if (scope.listedPathOf(path) != path) continue;
    files.putIfAbsent(path, () => _fileIn(scope.projectRoot, path));
  }
  return files;
}

File _fileIn(Directory folder, String path) => File(
  '${folder.path}${Platform.pathSeparator}'
  '${path.split('/').join(Platform.pathSeparator)}',
);

/// Returns the text of [file] with LF line ends and no byte-order mark, or
/// null when it cannot be read or is not UTF-8.
String? _lfTextOf(File file) {
  try {
    final text = utf8.decode(readPlanInput(file));
    return toLf(text.startsWith(byteOrderMark) ? text.substring(1) : text);
  } on FormatException {
    return null;
  } on FileSystemException {
    return null;
  }
}
