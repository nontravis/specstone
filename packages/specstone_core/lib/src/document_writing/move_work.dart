import 'dart:convert';
import 'dart:math';

import 'package:specstone_core/src/doc_model/doc_path_shape.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart'
    show MatchedDocType;
import 'package:specstone_core/src/document_writing/item_landing.dart'
    show numberedByPosition;
import 'package:specstone_core/src/document_writing/item_mentions.dart';
import 'package:specstone_core/src/document_writing/item_moves.dart';
import 'package:specstone_core/src/document_writing/keyed_edits.dart';
import 'package:specstone_core/src/document_writing/keyed_units.dart'
    show KeyedLanding;
import 'package:specstone_core/src/document_writing/models/new_item.dart';
import 'package:specstone_core/src/document_writing/models/path_move.dart';
import 'package:specstone_core/src/document_writing/models/renamed_names.dart'
    show RenamedNames;
import 'package:specstone_core/src/document_writing/models/text_edit.dart';
import 'package:specstone_core/src/document_writing/move_feature.dart';
import 'package:specstone_core/src/document_writing/move_item.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/move_reply.dart';
import 'package:specstone_core/src/document_writing/new_doc.dart';
import 'package:specstone_core/src/document_writing/own_segment.dart';
import 'package:specstone_core/src/document_writing/record_edit.dart'
    show plannedLinesOf;
import 'package:specstone_core/src/document_writing/restamp_pass.dart';
import 'package:specstone_core/src/document_writing/rewrite_item_refs.dart';
import 'package:specstone_core/src/document_writing/rewrite_labels.dart'
    show rewriteMovedFrTraces;
import 'package:specstone_core/src/document_writing/rewrite_records.dart';
import 'package:specstone_core/src/document_writing/rewrite_refs.dart';
import 'package:specstone_core/src/document_writing/sibling_ledger.dart';
import 'package:specstone_core/src/document_writing/stale_mentions.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/formatter.dart' show layOutDoc;
import 'package:specstone_core/src/rendering/line_ending.dart' show toLf;
import 'package:specstone_core/src/templates/merged_doc_type.dart';

// MARK: - Work

/// Where a group of doc targets lands.
sealed class MoveDestination {
  const new();
}

/// Among the top features.
final class TopDestination extends MoveDestination {
  const new();
}

/// Under a doc the index holds.
final class DocDestination extends MoveDestination {
  const new(this.doc);

  final IndexedDoc doc;
}

/// Under the doc the plan's `new` line at [at], among its creations, makes.
final class CreatedDestination extends MoveDestination {
  const new(this.at);

  final int at;
}

/// Doc targets of one doc type that land under one destination, in order.
final class DocMoveGroup {
  const new({
    required this.docType,
    required this.targets,
    required this.destination,
  });

  final MergedDocType docType;
  final List<IndexedDoc> targets;
  final MoveDestination destination;
}

/// What one move call does, judged against the index before the lock.
final class MoveWork {
  const new({
    this.creates = const [],
    this.groups = const [],
    this.landings = const [],
    this.keyed = const [],
    this.orders = const {},
    this.keyedOrders = const {},
    this.renumberings = const [],
  });

  /// Where each doc a `new` line creates goes, in plan line order.
  final List<NewDocPlace> creates;
  final List<DocMoveGroup> groups;

  /// Where each item lands, in plan line order per destination, each edge
  /// case and scenario at its position.
  final List<ItemLanding> landings;

  /// Where each block and row address lands, in plan line order.
  final List<KeyedLanding> keyed;

  /// The items of each doc whose units the plan all names, by DocPath, in
  /// the order of its `keep` lines.
  final Map<String, List<ItemTarget>> orders;

  /// The block and row addresses of each doc whose units the plan all names,
  /// by DocPath, in the order of its `keep` lines.
  final Map<String, List<String>> keyedOrders;

  /// The docs whose edge cases and scenarios the call numbers by position.
  final List<Renumbering> renumberings;
}

// MARK: - Apply

/// Applies [work], refusing before the lock as the lock would.
///
/// The numbers of created docs and moved docs are taken again under the
/// lock, since a concurrent `new` can claim one in between.
/// Throws the faults of [DocMoveGroup]'s move, [planNewDoc], and
/// `RenderFault` `output_not_writable`.
ReadAnswer applyMoveWork(
  WriteSession session,
  MoveWork work, {
  required MoveReplyShape shape,
  required bool dryRun,
}) {
  final placed = _Placed.of(session, work);
  if (placed.isEmpty &&
      work.landings.isEmpty &&
      work.keyed.isEmpty &&
      work.orders.isEmpty &&
      work.keyedOrders.isEmpty &&
      work.renumberings.isEmpty) {
    return moveReplyOf(session, shape: shape, dryRun: dryRun);
  }
  return session.locked(() {
    final now = _Placed.of(session, work);
    _requireSameCreated(placed, now);
    session.journalTarget.requireTrusted();
    final writes = session.withPlannedDocs(
      [for (final created in now.created) created.doc],
      {for (final created in now.created) created.docPath: created.content},
      () => _Writes.of(session, work, now),
    );
    if (!dryRun) {
      MoveJournal([
        for (final created in now.created)
          CreateStep(
            session.projectPathOf(created.docPath),
            writes.createdTexts[created.docPath]!,
          ),
        ...now.steps(session),
        ...writes.planned.rewrites,
        ...writes.planned.creates,
      ]).run(session.journalTarget);
    }
    return moveReplyOf(
      session,
      shape: shape,
      created: [for (final created in now.created) created.docPath],
      moves: now.moves,
      landings: work.landings,
      keyed: work.keyed,
      renumberings: work.renumberings,
      rewrites: writes.planned.rewrites,
      recordCreates: writes.planned.creates,
      mentions: writes.mentions,
      dryRun: dryRun,
    );
  });
}

/// Returns the names the doc moves of [work] change, read as the apply reads
/// them, so a judge can name a doc as it stands once every line has landed.
///
/// Throws the faults of [DocMoveGroup]'s move and [planNewDoc].
RenamedNames renamedNamesAfter(WriteSession session, MoveWork work) =>
    renamedNamesOf(session, _Placed.of(session, work).moves);

/// The writes of one move call, planned under its lock, and the mentions
/// they leave.
final class _Writes {
  const new(this.planned, this.createdTexts, this.mentions);

  /// Plans the reference rewrites, record edits, item landings, and position
  /// numbers of [work] with [now]'s moves, through one re-stamp pass.
  ///
  /// The `planned` line of each story or FR [now] creates goes to its
  /// feature's records after their other edits, as `new` writes it.
  factory of(WriteSession session, MoveWork work, _Placed now) {
    final renamed = renamedNamesOf(session, now.moves);
    final records = planRecordRewrites(session, renamed);
    final plannedLines = {
      for (final lines in plannedLinesOf(session, [
        for (final created in now.created) created.item,
      ]))
        lines.docPath: lines.edit,
    };
    final itemRefs = planItemRefs(
      session,
      work.landings,
      orders: work.orders,
      renumberings: work.renumberings,
    );
    final items = ItemMoves(
      session.index,
      work.landings,
      renumberings: work.renumberings,
    );
    final numbered = chainedEdits(
      itemRefs.edits,
      _numberingEdits(session, work.renumberings, now),
    );
    final itemEdits = chainedEdits(
      numbered,
      _keyedEdits(session, work, numbered, now),
    );
    final rows = planEdgeCaseRowMoves(
      session,
      work.landings,
      renumberings: work.renumberings,
    );
    final docEdits = chainedEdits(
      chainedEdits(
        chainedEdits(records.edits, now.frEdits(session)),
        rows.edits,
      ),
      plannedLines,
    );
    final createdEdits = chainedEdits(itemEdits, docEdits);
    final createdTexts = {
      for (final created in now.created)
        created.docPath: _createdText(
          session,
          created,
          createdEdits,
          now.moves,
        ),
    };
    final planned = planRewrites(
      session,
      now.moves,
      renamed: renamed,
      docEdits: {
        for (final MapEntry(key: docPath, value: edit) in docEdits.entries)
          if (!now.creates(docPath)) docPath: edit,
      },
      readEdits: {
        for (final MapEntry(key: docPath, value: edit) in itemEdits.entries)
          if (!now.creates(docPath)) docPath: edit,
      },
      createdTexts: createdTexts,
      creates: [...records.creates, ...rows.creates],
      blocks: items.isEmpty ? const BlockMoves.none() : BlockMoves.of(items),
    );
    return _Writes(planned, createdTexts, [
      if (now.moves.isNotEmpty)
        ...staleMentions(
          session,
          now.moves,
          namesChange: true,
          docWrites: planned.rewrites,
        ),
      if (!items.isEmpty)
        ...itemMentions(
          session,
          work.landings,
          renumberings: work.renumberings,
          refs: ItemRefs(
            edits: chainedEdits(itemRefs.edits, rows.edits),
            listed: itemRefs.listed,
          ),
        ),
    ]);
  }

  final PlannedRewrites planned;

  /// The text of each doc the call creates, by DocPath.
  final Map<String, String> createdTexts;
  final List<StaleMention> mentions;
}

/// Throws [WriteFault] `doc_exists` when a doc took the place of a doc the
/// call creates between [judged] and [now], which items were planned to land
/// in.
void _requireSameCreated(_Placed judged, _Placed now) {
  for (final (at, created) in now.created.indexed) {
    final planned = judged.created[at].docPath;
    if (created.docPath == planned) continue;
    throw WriteFault(
      WriteFaultCode.docExists,
      'a doc took $planned while the move was planned; run it again',
      file: planned,
    );
  }
}

/// Returns the text [created] is written with: its skeleton with the items
/// [edits] land in it and the links to [moves] rewritten, laid out.
String _createdText(
  WriteSession session,
  PlannedDoc created,
  Map<String, TextEdit> edits,
  List<PathMove> moves,
) {
  final landed = edits[created.docPath]?.call(created.text) ?? created.text;
  final linked =
      rewriteDocLinks(landed, docPath: created.docPath, moves: moves) ?? landed;
  return layOutDoc(linked, session.index.typeOf(created.doc));
}

/// Returns, by DocPath, the edits that move and order the blocks and rows of
/// [work], each doc read from its text once [itemEdits] ran on it, a doc
/// [now] creates from its skeleton.
Map<String, TextEdit> _keyedEdits(
  WriteSession session,
  MoveWork work,
  Map<String, TextEdit> itemEdits,
  _Placed now,
) {
  final docs = <String, IndexedDoc>{
    for (final KeyedLanding(:from, :to) in work.keyed) ...{
      from.docPath: from,
      to.docPath: to,
    },
    for (final docPath in work.keyedOrders.keys)
      docPath: session.index.at(docPath)!,
  };
  return keyedEdits(
    session,
    landings: work.keyed,
    orders: work.keyedOrders,
    docs: [
      for (final doc in docs.values)
        KeyedDoc(doc, _textBeforeKeyed(session, doc, itemEdits, now)),
    ],
    alsoFollowIn: [for (final landing in work.landings) landing.to],
  );
}

/// Returns the LF text of [doc] once [itemEdits] ran on it, a doc [now]
/// creates read from its skeleton.
String _textBeforeKeyed(
  WriteSession session,
  IndexedDoc doc,
  Map<String, TextEdit> itemEdits,
  _Placed now,
) {
  final created = now.created
      .where((created) => created.docPath == doc.docPath)
      .firstOrNull;
  final lfText = created?.text ?? toLf(session.index.contentOf(doc).text);
  return itemEdits[doc.docPath]?.call(lfText) ?? lfText;
}

/// Returns, by DocPath, the edit that numbers by position the edge cases and
/// scenarios of each doc [renumberings] names, run after its landing.
Map<String, TextEdit> _numberingEdits(
  WriteSession session,
  List<Renumbering> renumberings,
  _Placed now,
) {
  final edits = <String, TextEdit>{};
  for (final Renumbering(:docPath) in renumberings) {
    final doc =
        session.index.at(docPath) ??
        now.created.firstWhere((created) => created.docPath == docPath).doc;
    final type = session.index.typeOf(doc);
    if (type == null) continue;
    edits[docPath] = (lfText) {
      final numbered = numberedByPosition(lfText, type);
      return numbered == lfText ? null : numbered;
    };
  }
  return edits;
}

/// A doc a `new` line creates, placed at its DocPath.
final class PlannedDoc {
  const new({
    required this.docPath,
    required this.text,
    required this.doc,
    required this.content,
    required this.parent,
  });

  final String docPath;

  /// The laid-out skeleton, a draft.
  final String text;

  /// The doc and its content as the index would hold them once created.
  final IndexedDoc doc;
  final DocContent content;

  /// The doc it nests under, indexed or created; null for none.
  final IndexedDoc? parent;

  /// The doc as its feature's records read it.
  NewItem get item => NewItem(
    docTypeId: doc.docTypeId,
    docPath: docPath,
    name: doc.name,
    parent: parent,
  );
}

/// The moves of one group and where its targets land.
final class _GroupMoves {
  const new(this.group, this.parent, this.moves);

  final DocMoveGroup group;

  /// The doc the targets land under; null among the top features.
  final IndexedDoc? parent;
  final List<PathMove> moves;
}

/// The created docs and doc moves of a [MoveWork], numbered as the disk
/// stands.
final class _Placed {
  const new(this.created, this.groups);

  /// Numbers the created docs first, then the moves in group order, from one
  /// [SiblingLedger], so no two take one number or one slug in a folder.
  factory of(WriteSession session, MoveWork work) {
    final ledger = SiblingLedger();
    final created = plannedDocsOf(session, work.creates, ledger);
    return _Placed(created, [
      for (final group in work.groups)
        _groupMovesOf(session, group, created: created, ledger: ledger),
    ]);
  }

  final List<PlannedDoc> created;
  final List<_GroupMoves> groups;

  bool get isEmpty => created.isEmpty && moves.isEmpty;

  /// Whether the call creates the doc at [docPath].
  bool creates(String docPath) =>
      created.any((created) => created.docPath == docPath);

  List<PathMove> get moves => [for (final group in groups) ...group.moves];

  /// Returns the edits that set each moved FR's own scenario traces.
  Map<String, TextEdit> frEdits(WriteSession session) => {
    for (final group in groups)
      if (group.group.docType.id == frType && group.parent != null)
        ..._movedFrEdits(session, group.group.targets, group.parent!),
  };

  /// Returns the journal steps of the moves: a feature's staged, since a
  /// folder may land where another move leaves, any other's direct.
  List<MoveStep> steps(WriteSession session) => [
    for (final group in groups)
      if (group.group.docType.id == featureType)
        ...stagedMoveSteps(session, group.moves)
      else
        for (final move in group.moves)
          MoveStep(
            moveStepPath(session, move.from),
            moveStepPath(session, move.to),
          ),
  ];
}

/// Returns each doc [places] create, numbered after the siblings on disk and
/// the numbers [ledger] gave in the same folder.
///
/// Throws [WriteFault] `doc_exists` as `new` does, and for a doc whose slug,
/// or unnumbered path, [ledger] already gave in that folder.
List<PlannedDoc> plannedDocsOf(
  WriteSession session,
  List<NewDocPlace> places,
  SiblingLedger ledger,
) {
  final created = <PlannedDoc>[];
  for (final place in places) {
    final container = place.shape.containerOf(place.parentValues);
    final typeId = place.docType.id;
    final docPath = place.docPathAt(
      ledger.nextNumber(container, typeId, place.highestOnDisk(session)),
    );
    if (!ledger.claim(container, typeId, place.slug ?? docPath)) {
      throw existsFault(place.docType, docPath, docPath);
    }
    final text = skeletonOf(place.docType, place.title);
    final parsed = parseIndexedDoc(
      docPath: docPath,
      bytes: utf8.encode(text),
      match: MatchedDocType(place.docType, target: place.placedIn),
    );
    created.add(
      PlannedDoc(
        docPath: docPath,
        text: text,
        doc: parsed.doc,
        content: parsed.content,
        parent: place.parentDoc,
      ),
    );
  }
  return created;
}

String? _slugOf(DocPathShape shape, String docPath) =>
    shape.matchOwn(docPath.split('/')[shape.ownIndex])?.slug;

/// Returns the moves of [group], refusing as its doc type's move refuses.
_GroupMoves _groupMovesOf(
  WriteSession session,
  DocMoveGroup group, {
  required List<PlannedDoc> created,
  required SiblingLedger ledger,
}) {
  final parent = switch (group.destination) {
    TopDestination() => null,
    DocDestination(:final doc) => doc,
    CreatedDestination(:final at) => created[at].doc,
  };
  if (group.docType.id == featureType) {
    return _GroupMoves(
      group,
      parent,
      planFeatureMoves(
        session,
        group.targets,
        newParent: parent,
        ledger: ledger,
      ),
    );
  }
  final newParent =
      parent ?? (throw StateError('${group.docType.id} move reached as top'));
  final moving = [
    for (final target in group.targets)
      if (session.index.parentOf(target)?.docPath != newParent.docPath) target,
  ];
  if (moving.isEmpty) return _GroupMoves(group, newParent, const []);
  if (group.docType.id == storyType) _checkTakesStory(session, newParent);
  return _GroupMoves(
    group,
    newParent,
    _landingMoves(session, moving, group.docType, newParent, ledger),
  );
}

/// Throws [IndexFault] `argument_invalid` when [parent] holds a doc of the
/// nesting type, since a feature holds stories or features.
void _checkTakesStory(WriteSession session, IndexedDoc parent) {
  final nestingId = session.index.set.nestingType?.id;
  final holdsSubFeature = session.index
      .childrenOf(parent)
      .any((child) => child.docTypeId == nestingId);
  if (!holdsSubFeature) return;
  throw IndexFault(
    IndexFaultCode.argumentInvalid,
    '${nameWithType(parent)} holds sub-${parent.docTypeId}s, so it takes no '
    'story',
  );
}

/// Returns the moves that put [targets] last among the children of
/// [newParent], in order, each slug kept.
///
/// Throws [WriteFault] `doc_exists` when two targets carry one slug, naming
/// the first of them, or as [checkNoClash] does.
List<PathMove> _landingMoves(
  WriteSession session,
  List<IndexedDoc> targets,
  MergedDocType docType,
  IndexedDoc newParent,
  SiblingLedger ledger,
) {
  final set = session.index.set;
  final parentType =
      set.lookup(newParent.docTypeId!) ??
      (throw StateError('${newParent.docPath} has no doc type'));
  final parentShape =
      DocPathShape.ofDoc(
        parentType,
        set,
        newParent.docPath,
        target: newParent.target,
      ) ??
      (throw StateError('${newParent.docPath} does not match its doc type'));
  final parentValues =
      parentShape.valuesOf(newParent.docPath) ??
      (throw StateError('${newParent.docPath} does not match its doc type'));
  final landedShape =
      DocPathShape.of(docType, set, depth: parentShape.depth) ??
      (throw StateError(
        '${docType.id} has no path at depth ${parentShape.depth}',
      ));
  final siblings = siblingsOnDisk(session.project, landedShape, parentValues);
  final highest = siblings.fold(0, (top, s) => max(top, s.number ?? 0));
  final container = landedShape.containerOf(parentValues);
  final firstOfSlug = <String, IndexedDoc>{};
  final moves = <PathMove>[];
  for (final target in targets) {
    final shape =
        DocPathShape.ofDoc(
          docType,
          set,
          target.docPath,
          target: target.target,
        ) ??
        (throw StateError('${target.docPath} does not match its doc type'));
    final slug =
        _slugOf(shape, target.docPath) ??
        (throw StateError('${target.docPath} carries no slug'));
    final first = firstOfSlug[slug];
    if (first != null) {
      throw existsFault(docType, first.docPath, first.docPath);
    }
    firstOfSlug[slug] = target;
    final newDocPath = landedShape.build([
      ...parentValues,
      ...landedShape.ownValues(
        number: padNumber(ledger.nextNumber(container, docType.id, highest)),
        slug: slug,
      ),
    ]);
    if (!ledger.claim(container, docType.id, slug)) {
      throw existsFault(docType, newDocPath, newDocPath);
    }
    final move = PathMove(
      from: shape.ownPathOf(target.docPath),
      to: landedShape.ownPathOf(newDocPath),
    );
    checkNoClash(
      session,
      docType,
      landedShape,
      parentValues,
      siblings,
      slug: slug,
      newDocPath: newDocPath,
      moves: [move],
    );
    moves.add(move);
  }
  return moves;
}

/// Returns, by DocPath before the move, the edit that sets the own scenario
/// traces of each FR of [targets] that moves into [newParent].
Map<String, TextEdit> _movedFrEdits(
  WriteSession session,
  List<IndexedDoc> targets,
  IndexedDoc newParent,
) => {
  for (final fr in targets)
    if (session.index.parentOf(fr) case final source?)
      if (source.docPath != newParent.docPath)
        fr.docPath: (lfText) => rewriteMovedFrTraces(
          lfText,
          sourceStory: source.name,
          isTargetStory: (storyName) =>
              _namesStory(session, storyName, newParent),
        ),
};

/// Whether [storyName], in any name form, names [story] alone.
bool _namesStory(WriteSession session, String storyName, IndexedDoc story) {
  try {
    final named = session.index.resolve('$storyType:$storyName');
    return named.length == 1 && named.single.docPath == story.docPath;
  } on IndexFault {
    return false;
  }
}

/// Returns [first] and [then] by DocPath, the edit of a doc in both running
/// [first] and then [then] on its result.
Map<String, TextEdit> chainedEdits(
  Map<String, TextEdit> first,
  Map<String, TextEdit> then,
) => {
  ...first,
  for (final MapEntry(key: path, value: next) in then.entries)
    path: switch (first[path]) {
      final earlier? => (lfText) {
        final written = earlier(lfText);
        return next(written ?? lfText) ?? written;
      },
      null => next,
    },
};

/// Returns every move twice, as a [MoveStep]: each path to its stage slot,
/// then each stage slot to its target, so no move lands on a path another
/// has not yet left.
List<MoveStep> stagedMoveSteps(WriteSession session, List<PathMove> moves) => [
  for (final (i, move) in moves.indexed)
    MoveStep(moveStepPath(session, move.from), '${MoveJournal.stagePath}/$i'),
  for (final (i, move) in moves.indexed)
    MoveStep('${MoveJournal.stagePath}/$i', moveStepPath(session, move.to)),
];

/// Returns [docPath] as a [MoveStep] takes it: a project path with no
/// closing `/`.
String moveStepPath(WriteSession session, String docPath) {
  final path = session.projectPathOf(docPath);
  return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
}
