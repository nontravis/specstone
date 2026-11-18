import 'package:specstone_core/src/consistency_check/fingerprint.dart'
    show fingerprintOf;
import 'package:specstone_core/src/consistency_check/scenario_blocks.dart'
    show scenarioBlocksOfContent;
import 'package:specstone_core/src/doc_model/doc_anchors.dart'
    show anchorsOfBody;
import 'package:specstone_core/src/doc_model/doc_items.dart'
    show SectionItemKind;
import 'package:specstone_core/src/doc_model/doc_link.dart'
    show DocTarget, projectFilePathOf, relativeFilePathOf, resolveDocLink;
import 'package:specstone_core/src/doc_model/models/id_read.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/document_writing/body_scan.dart';
import 'package:specstone_core/src/document_writing/item_landing.dart';
import 'package:specstone_core/src/document_writing/item_moves.dart';
import 'package:specstone_core/src/document_writing/item_ref_entries.dart';
import 'package:specstone_core/src/document_writing/models/text_edit.dart';
import 'package:specstone_core/src/document_writing/move_item.dart';
import 'package:specstone_core/src/document_writing/moved_paths.dart'
    show rebasedHref, relativeHref;
import 'package:specstone_core/src/document_writing/rewrite_labels.dart'
    show MovedFingerprints, rewriteScenarioSteps, rewriteScenarioTraces;
import 'package:specstone_core/src/document_writing/scenario_items.dart'
    show landedScenarioHeading;
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_facts.dart'
    show itemKeyOfHead, sectionItemsAt;
import 'package:specstone_core/src/index_query/item_links.dart';
import 'package:specstone_core/src/index_query/link_blocks.dart'
    show leafTextOf, linkLabel;
import 'package:specstone_core/src/index_query/link_places.dart' show LinkText;
import 'package:specstone_core/src/index_query/link_scan.dart' show LinkSource;
import 'package:specstone_core/src/index_query/override_chain.dart';
import 'package:specstone_core/src/journeys/journey_steps.dart'
    show journeyTypeId;
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart'
    show MergedDocType;
import 'package:specstone_core/src/templates/template_fault.dart';

// MARK: - Edits

const _separator = ', ';

/// Returns, by DocPath, the edit of every doc an item move writes: the
/// landing of [landings] and each reference that names a moved item, a
/// scenario's traces and heading links included; each edit refuses a doc
/// that changed since the plan.
///
/// Throws [RenderFault] `output_not_writable` for entries not valid YAML.
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

/// A reference an item move leaves for the Agent: the file line the doc that
/// held it before the move had it on, and its text before and after the write.
final class ListedRef {
  const new(this.line, this.textBefore, this.text);

  final int line;
  final String textBefore;

  /// The text once the move's rewrites of its line apply.
  final String text;
}

/// A reference the link rewrite leaves: the characters from [start] up to
/// [end] of file [line].
final class _Listed {
  const new(this.line, this.start, this.end);

  final int line;
  final int start;
  final int end;
}

/// Plans [itemRefEdits] and the references it leaves, in one read of the docs.
ItemRefs planItemRefs(WriteSession session, List<ItemLanding> landings) {
  if (landings.isEmpty) return const ItemRefs(edits: {}, listed: {});
  final index = session.index;
  final moves = ItemMoves(index, landings);
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
    droppedLines: {
      for (final MapEntry(:key, :value) in rewritten.entries)
        if (value.removals.isNotEmpty) key.docPath: value.removals,
    },
  );
  final fingerprints = _fingerprintsOf(index, landings, landed);
  final entries = itemEntryEdits(index, moves, fingerprints: fingerprints);
  final traces = _scenarioTraceEdits(index, landings, fingerprints);
  final paths = {
    for (final doc in rewritten.keys) doc.docPath,
    ...landed.keys,
    ...entries.keys,
    ...traces.keys,
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
          [?entries[path], ?traces[path]],
        ),
    },
    listed: {
      for (final MapEntry(:key, :value) in rewritten.entries)
        if (value.listed.isNotEmpty) key.docPath: value.listed,
    },
  );
}

/// Returns the edit that runs the landing, or the link rewrite when the doc
/// has none, then runs each of [entries] in turn.
TextEdit _composed(
  IndexedDoc? doc,
  _Rewritten? body,
  TextEdit? landing,
  List<String Function(String lfText)> entries,
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
  final result = entries.fold(text, (text, edit) => edit(text));
  return result == lfText ? null : result;
};

// MARK: - Fingerprints

/// Returns the fingerprint of the block each landing's entries track, before
/// the move and in the target doc as [landed] writes it.
Map<ItemLanding, MovedFingerprints> _fingerprintsOf(
  DocIndex index,
  List<ItemLanding> landings,
  Map<String, TextEdit> landed,
) {
  final target = landings.first.to;
  final type = index.typeOf(target);
  final lf = toLf(index.contentOf(target).text);
  final after = docStructureOf(landed[target.docPath]?.call(lf) ?? lf, type);
  final fingerprints = <ItemLanding, MovedFingerprints>{};
  for (final landing in landings) {
    final source = landing.from.doc;
    final located = locateItem(index, landing.from);
    final before = _trackedText(
      index.contentOf(source),
      index.typeOf(source),
      located,
      landing.from.id,
    );
    if (before == null) continue;
    final landedText = _trackedText(after, type, located, landing.newId);
    fingerprints[landing] = MovedFingerprints(
      before: fingerprintOf(before),
      after: landedText == null ? null : fingerprintOf(landedText),
    );
  }
  return fingerprints;
}

/// Returns the text an entry tracks of the item [located], held as [id] in
/// [content], a doc of [type]: a scenario's block, as an FR or a journey
/// traces it, else the item's own lines, as an `Overrides:` line does; null
/// when [content] holds no such item.
String? _trackedText(
  DocContent content,
  MergedDocType? type,
  LocatedItem located,
  String id,
) {
  if (located.isScenario) return scenarioBlocksOfContent(content, type)[id];
  for (final (at, section) in citedSectionsOf(content, type).indexed) {
    if (!located.isTakenBy(section.key, section.prefixId)) continue;
    for (final item in sectionItemsAt(content, at, type)) {
      final key = itemKeyOfHead(
        item.head,
        isHeading: item.kind == SectionItemKind.heading,
        prefixId: located.prefix,
        isAcceptanceCriteria: false,
      );
      if (key == id) return item.text;
    }
  }
  return null;
}

// MARK: - Scenario traces

/// Returns, by DocPath, the edit of each FR and journey whose trace entries
/// or steps name a moved scenario: each set to its landing, and a matched
/// `confirmed` entry re-stamped from [fingerprints].
Map<String, String Function(String lfText)> _scenarioTraceEdits(
  DocIndex index,
  List<ItemLanding> landings,
  Map<ItemLanding, MovedFingerprints> fingerprints,
) {
  final scenarios = [
    for (final landing in landings)
      if (landing.isScenario) landing,
  ];
  if (scenarios.isEmpty) return const {};
  final edits = <String, String Function(String lfText)>{};
  for (final doc in index.docs) {
    final edit = _scenarioTraceEditOf(index, doc, scenarios, fingerprints);
    if (edit == null) continue;
    final lf = toLf(index.contentOf(doc).text);
    if (edit(lf) != lf) edits[doc.docPath] = edit;
  }
  return edits;
}

/// Returns the edit that sets the traces of [doc], an FR or a journey, for
/// each of [scenarios] in turn; null for any other doc.
///
/// Each edit names its landing's target story, so no later one matches it.
String Function(String lfText)? _scenarioTraceEditOf(
  DocIndex index,
  IndexedDoc doc,
  List<ItemLanding> scenarios,
  Map<ItemLanding, MovedFingerprints> fingerprints,
) {
  final type = index.typeOf(doc);
  final story = index.parentOf(doc)?.docPath;
  final traceOf = switch (doc.docTypeId) {
    frType => (String text, ItemLanding landing) => rewriteScenarioTraces(
      text,
      fromNumber: _scenarioNumberOf(landing.from.id),
      targetStory: landing.to.name,
      toNumber: _scenarioNumberOf(landing.newId),
      fingerprints: fingerprints[landing],
      isSourceStory: (name) => _namesStory(index, name, landing.from.doc),
      isInSourceStory: story == landing.from.doc.docPath,
      isInTargetStory: story == landing.to.docPath,
    ),
    journeyTypeId when type != null =>
      (String text, ItemLanding landing) => rewriteScenarioSteps(
        text,
        docType: type,
        fromNumber: _scenarioNumberOf(landing.from.id),
        targetStory: landing.to.name,
        toNumber: _scenarioNumberOf(landing.newId),
        fingerprints: fingerprints[landing],
        isSourceStory: (name) => _namesStory(index, name, landing.from.doc),
      ),
    _ => null,
  };
  if (traceOf == null) return null;
  return (lfText) =>
      scenarios.fold(lfText, (text, landing) => traceOf(text, landing) ?? text);
}

/// Returns the number of the scenario ID [id], `S<N>` by its value.
int _scenarioNumberOf(String id) =>
    int.parse(id.substring(_scenarioRef.length));

const _scenarioRef = 'S';

/// Whether [storyName], in any name form, names [story] alone.
bool _namesStory(DocIndex index, String storyName, IndexedDoc story) {
  try {
    final named = index.resolve('$storyType:$storyName');
    return named.length == 1 && named.single.docPath == story.docPath;
  } on IndexFault {
    return false;
  } on TemplateFault {
    return false;
  }
}

/// A doc text as the index holds it, and with its links set to their new
/// place.
final class _Rewritten {
  const new(this.before, this.after, this.listed, this.removals);

  final String before;
  final String after;
  final List<ListedRef> listed;

  /// The file lines of the reference definitions the move leaves unused.
  final Set<int> removals;
}

/// One item as a reference names it: its doc and its ID there.
final class _Named {
  const new(this.docPath, this.id);

  final String docPath;
  final String id;
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

/// A place in a doc's file: its 1-based line and its column.
final class _LineColumn {
  const new({required this.line, required this.column});

  final int line;
  final int column;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is _LineColumn && other.line == line && other.column == column;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(line, column);
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
  final ItemMoves moves;

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
_Rewritten? _linkBodyOf(DocIndex index, IndexedDoc doc, ItemMoves moves) {
  final lf = toLf(index.contentOf(doc).text);
  final lines = lf.split('\n');
  final plan = _linkPlanOf(index, doc, moves, lf, lines);
  if (plan.edits.isEmpty && plan.listed.isEmpty) return null;
  final listed = [
    for (final span in plan.listed)
      ListedRef(
        span.line,
        lines[span.line - 1].substring(span.start, span.end),
        _editedSpan(lines[span.line - 1], span, plan.edits[span.line]),
      ),
  ];
  for (final MapEntry(key: number, value: edits) in plan.edits.entries) {
    lines[number - 1] = _withEdits(lines[number - 1], edits);
  }
  return _Rewritten(lf, lines.join('\n'), listed, plan.removals);
}

/// Returns the text [span] covers of [line] once those of [edits] that sit
/// inside it apply.
String _editedSpan(String line, _Listed span, List<_Edit>? edits) =>
    _withEdits(line.substring(span.start, span.end), [
      for (final edit in edits ?? const <_Edit>[])
        if (span.start <= edit.start && edit.end <= span.end)
          _Edit(edit.start - span.start, edit.end - span.start, edit.text),
    ]);

/// What the link rewrite finds in one doc: the edits by file line, and the
/// references it leaves for the Agent.
final class _LinkPlan {
  final edits = <int, List<_Edit>>{};
  final listed = <_Listed>[];

  /// The file lines of the reference definitions the move leaves unused.
  final removals = <int>{};

  /// Adds [edit] to file [line] unless an edit starts at the same column.
  void add(int line, _Edit edit) {
    final held = edits[line] ??= [];
    if (held.every((other) => other.start != edit.start)) held.add(edit);
  }
}

_LinkPlan _linkPlanOf(
  DocIndex index,
  IndexedDoc doc,
  ItemMoves moves,
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
  final itemLinks = <_LineColumn, _ReadLink>{};
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
      itemLinks[_LineColumn(line: number, column: read.link.column)] = read;
      if (_isPlain(line.text, read.link)) continue;
      if (_refUserOf(line, read) case final user?) {
        (users[user.label] ??= []).add(user);
      }
    }
  }
  BodyScan? scanned;
  BodyScan scanOf() => scanned ??= BodyScan(lf);
  final headingLinks = _planHeadingLinks(plan, doc, moves, scanOf, lines);
  final isSource = moves.spans.containsKey(doc.docPath);
  if (users.isEmpty && !isSource) return plan;
  final refs = _References(scanOf(), lines, doc, moves);
  _planReferences(plan, refs, users);
  if (isSource) {
    _planRebased(plan, refs.scan, doc, moves, {
      ...itemLinks.keys,
      ...headingLinks,
    });
    _planRebasedReferences(plan, refs, itemLinks);
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

_RefUser? _refUserOf(_Line line, _ReadLink read) {
  final link = read.link;
  final head = '[${link.text}]';
  final text = line.text;
  if (!text.startsWith(head, link.column)) return null;
  final after = link.column + head.length;
  if (!text.startsWith('[', after)) {
    return link.endColumn == after
        ? _RefUser(line, read, linkLabel(link.text), isText: true)
        : null;
  }
  final close = text.indexOf(']', after);
  if (close < 0 || link.endColumn != close + 1) return null;
  final label = text.substring(after + 1, close);
  return _RefUser(
    line,
    read,
    linkLabel(label.isEmpty ? link.text : label),
    isText: label.isEmpty,
  );
}

// MARK: - Reference definitions

/// One `[label]: destination` definition of a body, written on one line.
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

/// The reference-style links and definitions of one doc body, read once, and
/// where each sits after the moves.
final class _References {
  new(this.scan, this.lines, this.doc, this.moves);

  final BodyScan scan;
  final List<String> lines;
  final IndexedDoc doc;
  final ItemMoves moves;

  /// Each definition by its label as `markdown` folds it, the first of a
  /// label winning; null for one written over more than one line.
  late final Map<String, _Definition?> definitions = _definitionsOf(scan);
  late final List<_RefLink> links = _refLinksOf(scan, lines);

  /// The DocPath of the doc file [line] sits in after the moves.
  String placeOf(int line) => moves.placeOf(doc.docPath, line);

  /// The number of reference-style links of [label] that sit in [place]
  /// after the moves.
  int usesIn(String label, String place) => links
      .where((link) => link.label == label && placeOf(link.line) == place)
      .length;
}

Map<String, _Definition?> _definitionsOf(BodyScan body) {
  final leaf = leafTextOf(body.body);
  final found = <String, _Definition?>{};
  for (final (at, label) in leaf.definitionLabels.indexed) {
    final key = linkLabel(body.body.substring(label.start, label.end));
    if (found.containsKey(key)) continue;
    final destination = leaf.definitionDestinations[at];
    final number = body.fileLineOf(destination.start);
    found[key] = body.fileLineOf(label.start) != number
        ? null
        : _Definition(
            line: number,
            labelStart: body.columnOf(label.start),
            labelEnd: body.columnOf(label.end),
            destStart: body.columnOf(destination.start),
            destination: body.body.substring(
              destination.start,
              destination.end,
            ),
          );
  }
  return found;
}

/// Returns the reference-style links of [body], inline ones aside.
List<_RefLink> _refLinksOf(BodyScan body, List<String> lines) {
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
        label: linkLabel(label.isEmpty ? written : label),
      ),
    );
  }
  return found;
}

/// Plans the definitions that reference-style item links share with the links
/// that sit in the same doc after the moves: one that serves moved items
/// alone takes the new path, and each link text and label the new ID; one
/// that serves items that part ways, or any other link, stays and is listed.
void _planReferences(
  _LinkPlan plan,
  _References refs,
  Map<String, List<_RefUser>> users,
) {
  for (final MapEntry(key: label, value: using) in users.entries) {
    final definition = refs.definitions[label];
    if (definition == null) continue;
    final place = refs.placeOf(definition.line);
    final served = [
      for (final user in using)
        if (user.line.place == place) user,
    ];
    if (served.isEmpty) continue;
    final afters = [
      for (final user in served)
        _afterOf(
          user.line,
          user.read.read.target.docPath,
          user.read.cite!.sectionKey,
          user.read.cite!.itemId,
        ),
    ];
    final first = afters.first;
    final isOneWay =
        first != null &&
        refs.usesIn(label, place) == served.length &&
        afters.every((after) => after?.docPath == first.docPath);
    if (!isOneWay) {
      if (afters.any((after) => after != null)) {
        final text = refs.lines[definition.line - 1];
        plan.listed.add(
          _Listed(
            definition.line,
            text.length - text.trimLeft().length,
            text.trimRight().length,
          ),
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
  final written = _writtenOf(
    definition.destination,
    DestinationKind.definition,
  );
  if (written.suffix.isNotEmpty &&
      !_reaches(definition.destination, place, first.docPath)) {
    final path = _pathBetween(place, first);
    if (path != written.path) {
      plan.add(
        definition.line,
        _Edit(
          definition.destStart,
          definition.destStart + written.path.length,
          path,
        ),
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

/// Plans the relative destinations inside moved items that no link of
/// [covered], by file line and column, holds: each is set to reach from the
/// target doc what it reaches from the source doc.
void _planRebased(
  _LinkPlan plan,
  BodyScan body,
  IndexedDoc doc,
  ItemMoves moves,
  Set<_LineColumn> covered,
) {
  for (final destination in body.scan.destinations) {
    final number = body.fileLineOf(destination.start);
    final span = moves.spanAt(doc.docPath, number);
    if (span == null || moves.isOwnLine(doc.docPath, number)) continue;
    if (destination.link case final at?) {
      final source = body.scan.sources[at];
      final place = _LineColumn(
        line: source.line,
        column: body.columnOf(source.offset),
      );
      if (covered.contains(place)) continue;
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

/// Plans the reference-style links that the moves land in another doc than
/// their definition: each becomes an inline link to what the definition
/// names, as read from the doc the link lands in, an item link to its item
/// after the moves; one whose definition carries a title stays and is listed.
/// A definition no link uses any more is removed.
void _planRebasedReferences(
  _LinkPlan plan,
  _References refs,
  Map<_LineColumn, _ReadLink> itemLinks,
) {
  final converted = <String, int>{};
  for (final link in refs.links) {
    if (refs.moves.isOwnLine(refs.doc.docPath, link.line)) continue;
    final definition = refs.definitions[link.label];
    if (definition == null) continue;
    final place = refs.placeOf(link.line);
    if (place == refs.placeOf(definition.line)) continue;
    if (_hasTitle(refs.lines[definition.line - 1], definition)) {
      plan.listed.add(_Listed(link.line, link.column, link.end));
      continue;
    }
    final item = itemLinks[_LineColumn(line: link.line, column: link.column)];
    plan.add(
      link.line,
      item == null
          ? _referenceInline(
              refs.moves,
              link,
              definition,
              refs.doc.docPath,
              place,
            )
          : _itemLinkInline(refs, item, link, definition),
    );
    converted[link.label] = (converted[link.label] ?? 0) + 1;
  }
  final totals = <String, int>{};
  for (final link in refs.links) {
    totals[link.label] = (totals[link.label] ?? 0) + 1;
  }
  for (final MapEntry(key: label, value: count) in converted.entries) {
    if (totals[label] != count) continue;
    plan.removals.add(refs.definitions[label]!.line);
  }
}

/// Returns the edit that writes the reference-style [link] as an inline link
/// to what [definition], written in the doc at [from], names from [place]:
/// a moved scenario's heading at its landed heading.
_Edit _referenceInline(
  ItemMoves moves,
  _RefLink link,
  _Definition definition,
  String from,
  String place,
) {
  final written =
      _headingDestination(
        moves,
        definition.destination,
        from,
        place,
        DestinationKind.definition,
      ) ??
      _destinationFrom(definition.destination, from, place);
  return _Edit(link.textEnd + 1, link.end, '(${_shownOf(written)})');
}

/// Returns the edit that writes the reference-style item [link] as an inline
/// link to its item after the moves, read from the doc the link lands in.
_Edit _itemLinkInline(
  _References refs,
  _ReadLink read,
  _RefLink link,
  _Definition definition,
) {
  final line = _Line(
    index: refs.moves.index,
    doc: refs.doc,
    moves: refs.moves,
    number: link.line,
    text: refs.lines[link.line - 1],
  );
  final cite = read.cite!;
  final after = _afterOf(
    line,
    read.read.target.docPath,
    cite.sectionKey,
    cite.itemId,
  );
  final written = definition.destination;
  final keeps =
      after == null ||
      (after.id == read.link.text &&
          _reaches(written, line.place, after.docPath));
  final destination = keeps
      ? written
      : _pathBetween(line.place, after) +
            _writtenOf(written, DestinationKind.definition).suffix;
  final id = after?.id ?? read.link.text;
  return _Edit(link.column, link.end, '[$id](${_shownOf(destination)})');
}

/// Returns [destination] as an inline link writes it: in angle brackets when
/// it holds whitespace.
String _shownOf(String destination) =>
    destination.contains(RegExp(r'\s')) ? '<$destination>' : destination;

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

// MARK: - Heading links

/// Plans each inline link and reference definition of [doc] that reaches the
/// heading of a moved scenario: its path set to the target story and its
/// anchor to the landed heading's, its text and query kept.
///
/// Returns the file line and column of each such inline link. [scanOf] reads
/// the body only when a link of [doc] reaches such a heading.
Set<_LineColumn> _planHeadingLinks(
  _LinkPlan plan,
  IndexedDoc doc,
  ItemMoves moves,
  BodyScan Function() scanOf,
  List<String> lines,
) {
  final facts = moves.index.contentOf(doc).lineFacts;
  final isCited = [
    ...facts.links,
    ...facts.selfLinks,
  ].any((place) => _movedHeadingAt(moves, place.target, place.anchor) != null);
  if (!isCited) return const <_LineColumn>{};
  final body = scanOf();
  final covered = <_LineColumn>{};
  for (final source in body.scan.sources) {
    final edit = _headingEdit(moves, doc, body, lines, source);
    if (edit == null) continue;
    plan.add(source.line, edit);
    covered.add(
      _LineColumn(line: source.line, column: body.columnOf(source.offset)),
    );
  }
  for (final definition in _definitionsOf(body).values) {
    if (definition == null) continue;
    final written = _headingDestination(
      moves,
      definition.destination,
      doc.docPath,
      moves.placeOf(doc.docPath, definition.line),
      DestinationKind.definition,
    );
    if (written == null) continue;
    final start = definition.destStart;
    plan.add(
      definition.line,
      _Edit(start, start + definition.destination.length, written),
    );
  }
  return covered;
}

/// Returns the edit that sets the destination of the inline link [source],
/// in angle brackets or not, when it reaches the heading of a moved scenario;
/// null for any other link.
_Edit? _headingEdit(
  ItemMoves moves,
  IndexedDoc doc,
  BodyScan body,
  List<String> lines,
  LinkSource source,
) {
  final shown = source.shown;
  final textEnd = source.textEnd;
  if (shown == null ||
      textEnd == null ||
      body.fileLineOf(textEnd) != source.line) {
    return null;
  }
  final close = body.columnOf(textEnd);
  final line = lines[source.line - 1];
  final start = line.startsWith('](<$shown>', close)
      ? close + 3
      : line.startsWith(']($shown', close)
      ? close + 2
      : null;
  if (start == null) return null;
  final written = _headingDestination(
    moves,
    shown,
    doc.docPath,
    moves.placeOf(doc.docPath, source.line),
    DestinationKind.inline,
  );
  return written == null ? null : _Edit(start, start + shown.length, written);
}

/// Returns the [kind] [destination], written in the doc at [from] and read
/// from the doc at [place] after the moves, set to the landed heading of the
/// moved scenario it reaches, its query kept; null when it reaches none.
String? _headingDestination(
  ItemMoves moves,
  String destination,
  String from,
  String place,
  DestinationKind kind,
) {
  if (resolveDocLink(destination, from) case DocTarget(
    :final docPath,
    :final anchor,
  )) {
    final span = _movedHeadingAt(moves, docPath, anchor);
    final slug = span == null ? null : _landedSlugOf(moves, span);
    if (span == null || slug == null) return null;
    final parts = destinationPartsOf(destination, kind);
    final anchorStart = parts.anchorStart;
    if (anchorStart == null) return null;
    final landing = span.landing;
    final path = _pathBetween(place, _Named(landing.to.docPath, landing.newId));
    return '$path${destination.substring(parts.pathEnd, anchorStart)}$slug';
  }
  return null;
}

/// Returns the moved scenario whose heading [anchor] names in the doc at
/// [docPath], or null.
MovedSpan? _movedHeadingAt(ItemMoves moves, String docPath, String? anchor) {
  final spans = moves.spans[docPath];
  final doc = moves.index.at(docPath);
  if (spans == null || doc == null || anchor == null || anchor.isEmpty) {
    return null;
  }
  final facts = moves.index.contentOf(doc).lineFacts;
  if (anchorTargetOf(facts, anchor) case HeadingBlockTarget(
    :final headingLine,
  )) {
    return spans
        .where((span) => span.landing.isScenario && span.first == headingLine)
        .firstOrNull;
  }
  return null;
}

/// Returns the anchor of the heading the scenario of [span] lands with, or
/// null when it reads none.
String? _landedSlugOf(ItemMoves moves, MovedSpan span) {
  final landing = span.landing;
  final source = landing.from.doc;
  final heading = toLf(moves.index.contentOf(source).text)
      .split('\n')[span.first - 1];
  final renamed = {
    for (final other in moves.landings)
      if (!other.isScenario &&
          other.from.doc.docPath == source.docPath &&
          other.newId != other.from.id)
        other.from.id: other.newId,
  };
  final landed = landedScenarioHeading(heading, landing, renamed);
  return anchorsOfBody(landed)?.headingSlugs.firstOrNull;
}

// MARK: - Item links and ranges

/// Returns the edits of the links of one [line]: one per range and one per
/// link outside a range, in no order.
List<_Edit> _editsOn(_Line line, List<_ReadLink> links, List<_Listed> listed) {
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
  final written = _linkIdOf(id);
  if (line.moves.landingOf(target, written, sectionKey: sectionKey)
      case final landing?) {
    return _Named(landing.to.docPath, landing.newId);
  }
  return line.place == line.doc.docPath ? null : _Named(target, written);
}

/// Returns the ID a link writes for the item the index holds by [key]:
/// `S<N>` for a scenario's `Scenario <N>`, else [key] itself.
String _linkIdOf(String key) => switch (readItemId(key, scenarioIdPrefix)) {
  ItemId(:final number) => '$_scenarioRef$number',
  _ => key,
};

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
  final written = _writtenOf(link.shown, DestinationKind.inline);
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

/// Whether [link] is written `[text](destination` at its column, its
/// destination holding a `?` or `#` part.
bool _isPlain(String line, LinkText link) =>
    line.startsWith('[${link.text}](${link.shown}', link.column) &&
    _writtenOf(link.shown, DestinationKind.inline).suffix.isNotEmpty;

/// A link destination as written, split before its `?` or `#`.
final class _Written {
  const new(this.path, this.suffix);

  final String path;
  final String suffix;
}

/// Splits [written], a [kind] destination as written, where `markdown` reads
/// its first `?` or `#`; the suffix is empty when it holds none.
_Written _writtenOf(String written, DestinationKind kind) {
  final at = destinationPartsOf(written, kind).pathEnd;
  return _Written(written.substring(0, at), written.substring(at));
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
  List<_Listed> listed,
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
      listed.add(_Listed(line.number, firstLink.column, lastLink.endColumn));
    }
    return null;
  }
  final steps = [
    for (final (at, id) in ids.indexed)
      _Step(afters[at] ?? _Named(target, _linkIdOf(id)), id),
  ];
  final written = _writtenOf(firstLink.shown, DestinationKind.inline);
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
