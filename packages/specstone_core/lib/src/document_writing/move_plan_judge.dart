import 'package:specstone_core/src/doc_model/doc_path_shape.dart';
import 'package:specstone_core/src/doc_model/models/doc_address.dart';
import 'package:specstone_core/src/doc_model/models/section_item.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show KeyedUnitAddress, readKeyedUnitAddress;
import 'package:specstone_core/src/document_writing/item_landing.dart'
    show holderOf, unitIdsIn;
import 'package:specstone_core/src/document_writing/keyed_units.dart';
import 'package:specstone_core/src/document_writing/move_item.dart';
import 'package:specstone_core/src/document_writing/move_plan.dart';
import 'package:specstone_core/src/document_writing/move_work.dart';
import 'package:specstone_core/src/document_writing/new_doc.dart';
import 'package:specstone_core/src/document_writing/scenario_items.dart';
import 'package:specstone_core/src/document_writing/sibling_ledger.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/fault.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_facts.dart'
    show itemKeyOfHead;
import 'package:specstone_core/src/index_query/item_links.dart'
    show citedSectionsOf;
import 'package:specstone_core/src/index_query/override_chain.dart'
    show overrideChainAbove;
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// Returns the work of [plan], each line judged against the index in plan
/// line order and every address resolved among [codeTarget]'s docs and the
/// shared docs.
///
/// Throws the fault of the first line refused, then an item move's fault per
/// destination.
MoveWork judgeMovePlan(
  WriteSession session,
  MovePlan plan, {
  String? codeTarget,
}) => _PlanJudge(session, plan, codeTarget).judge();

/// Returns the doc type of [target] when `move` takes it: a story, an FR, an
/// nf, or a feature.
///
/// Throws [WriteFault] `doc_type_not_movable` for any other type.
MergedDocType movableTypeOf(WriteSession session, IndexedDoc target) {
  const movable = {storyType, frType, nfType, featureType};
  final type =
      session.index.typeOf(target) ??
      (throw StateError('${target.docPath} has no doc type'));
  if (movable.contains(type.id)) return type;
  throw WriteFault(
    WriteFaultCode.docTypeNotMovable,
    '${type.id} docs cannot move; move takes a $storyType, an $frType, an '
    '$nfType, or a $featureType',
  );
}

/// The unit one plan line names, resolved, with its instruction.
final class _Judged {
  const new(this.line, this.written, this.key, this.instruction);

  final PlanLine line;

  /// The unit as the line writes it.
  final String written;

  /// The unit's identity: its DocPath, then `#` and its ID for an item.
  final String key;

  /// `keep`, or the identity of the destination.
  final String instruction;
}

/// Judges each line of one plan against the index, in plan line order.
final class _PlanJudge {
  new(this.session, this.plan, this.codeTarget);

  final WriteSession session;
  final MovePlan plan;
  final String? codeTarget;

  final _creates = <NewDocPlace>[];
  final _created = <PlannedDoc>[];
  final _groups = <String, _GroupDraft>{};
  final _items = <String, _ItemGroup>{};
  final _keeps = <String, List<ItemTarget>>{};
  final _named = <String, Set<String>>{};
  final _seen = <String, _Judged>{};
  final _keptDocs = <String, int>{};
  final _children = <String, Set<String>>{};
  final _keyed = <KeyedLanding>[];

  /// The block and row addresses of each doc's `keep` lines, by DocPath.
  final _keyedKeeps = <String, List<String>>{};

  /// The docs a `keep` line names a unit of, by DocPath.
  final _orderedDocs = <String, IndexedDoc>{};

  /// Each `<DocPath>#<section key>/<key>` a block or row lands at.
  final _landedKeys = <String>{};

  /// The docs a `keep` line names, or holds a unit of, by DocPath.
  final _keptInPlace = <String, IndexedDoc>{};

  /// The line of the `new` line that creates each doc of [_ahead], by
  /// DocPath.
  final _createdOn = <String, int>{};

  /// Each doc the plan's `new` lines create, planned before any line is
  /// judged, so an address names it by the index's name rules.
  late final List<IndexedDoc> _ahead = _plannedAhead();

  DocIndex get _index => session.index;

  /// Returns the work of the plan.
  ///
  /// Throws the fault of the first line refused, then an item move's fault
  /// per destination.
  MoveWork judge() {
    for (final line in plan.lines) {
      switch (line) {
        case SourceLine():
          continue;
        case NewLine():
          _create(line);
        case MoveLine(:final unit, :final destination):
          _move(line, unit, destination);
        case KeepLine(:final unit):
          _keep(line, unit);
      }
    }
    final ordered = _fullyNamed();
    final orders = {
      for (final MapEntry(key: docPath, value: kept) in _keeps.entries)
        if (ordered.contains(docPath)) docPath: kept,
    };
    final numbers = numberByPosition(
      _index,
      [for (final group in _items.values) ..._landingsOf(group)],
      orders: orders,
      kept: [..._keptInPlace.values],
    );
    return MoveWork(
      creates: _creates,
      groups: [for (final draft in _groups.values) draft.group],
      landings: numbers.landings,
      keyed: _keyed,
      orders: orders,
      keyedOrders: {
        for (final MapEntry(key: docPath, value: kept) in _keyedKeeps.entries)
          if (ordered.contains(docPath)) docPath: kept,
      },
      renumberings: numbers.renumberings,
    );
  }

  void _create(NewLine line) {
    final type = _index.set.lookup(line.docType);
    if (type != null &&
        type.isPerTarget &&
        _index.hasTwins &&
        codeTarget == null) {
      throw _lineFault(
        line,
        'new ${type.id} needs --target: the code targets are '
        '${_index.twinNames.join(', ')}',
      );
    }
    final place = planNewDoc(
      session,
      docTypeId: line.docType,
      parent: line.parent?.docPart,
      slug: line.slug,
      codeTarget: codeTarget,
      parentNamed: (value, parentTypeId) =>
          _parentNamed(line, value, parentTypeId),
    );
    _creates.add(place);
    _created
      ..clear()
      ..addAll(plannedDocsOf(session, _creates, SiblingLedger()));
    if (place.parentDoc case final parent?) {
      _requireOneKind(line, parent, place.docType.id);
    }
  }

  void _move(MoveLine line, DocAddress unit, DocAddress? destination) {
    final written = _writtenOf(unit);
    if (readKeyedUnitAddress(written) case final keyed?) {
      _moveKeyed(line, written, keyed, destination);
      return;
    }
    if (isItemAddress(_index, written)) {
      final target = _itemOf(line, unit, written);
      _requireUnit(line, written, unit, target);
      final under = destination == null
          ? throw _topFault(line, written)
          : _docNamed(line, destination.docPart);
      if (!_isNew(line, written, _itemKey(target), under.docPath)) return;
      _items
          .putIfAbsent(under.docPath, () => _ItemGroup(under))
          .addresses
          .add(written);
      (_named[target.doc.docPath] ??= {}).add(target.id);
      return;
    }
    final doc = _standingDocOf(line, written);
    final type = movableTypeOf(session, doc);
    final place = _docDestinationOf(line, written, type, destination);
    final parent = switch (place) {
      TopDestination() => null,
      DocDestination(:final doc) => doc,
      CreatedDestination(:final at) => _created[at].doc,
    };
    final identity = parent?.docPath ?? 'top';
    if (!_isNew(line, written, doc.docPath, identity)) return;
    if (parent != null) _requireOneKind(line, parent, type.id);
    _groups
        .putIfAbsent('${type.id} $identity', () => _GroupDraft(type, place))
        .targets
        .add(doc);
  }

  void _keep(KeepLine line, DocAddress unit) {
    final written = _writtenOf(unit);
    if (readKeyedUnitAddress(written) case final keyed?) {
      _keepKeyed(line, written, keyed);
      return;
    }
    if (!isItemAddress(_index, written)) {
      final doc = _standingDocOf(line, written);
      if (_isNew(line, written, doc.docPath, 'keep')) {
        _requireSiblingOrder(line, written, doc);
        _keptInPlace[doc.docPath] = doc;
      }
      return;
    }
    final target = _itemOf(line, unit, written);
    _requireUnit(line, written, unit, target);
    if (!_isNew(line, written, _itemKey(target), 'keep')) return;
    _keptInPlace[target.doc.docPath] = target.doc;
    _orderedDocs[target.doc.docPath] = target.doc;
    (_keeps[target.doc.docPath] ??= []).add(target);
    (_named[target.doc.docPath] ??= {}).add(target.id);
  }

  /// Judges a block or row move: its units, then the room for them in the
  /// section of their key in [destination].
  void _moveKeyed(
    MoveLine line,
    String written,
    KeyedUnitAddress keyed,
    DocAddress? destination,
  ) {
    final source = _keyedSourceOf(line, keyed);
    final address = _addressOf(keyed);
    final units = requireKeyedUnits(_index, source, address);
    final to = destination == null
        ? throw _topFault(line, written)
        : _docNamed(line, destination.docPart);
    if (!_isNew(line, written, '${source.docPath}#$address', to.docPath)) {
      return;
    }
    (_named[source.docPath] ??= {}).add(address);
    if (to.docPath == source.docPath) return;
    final landing = KeyedLanding(
      from: source,
      to: to,
      sectionKey: keyed.sectionKey,
      key: keyed.key,
    );
    final created = _created.where((c) => c.docPath == to.docPath).firstOrNull;
    final content = created?.content ?? _index.contentOf(to);
    requireKeyedRoom(landing, _index.typeOf(to), content, units);
    _requireFirstLanding(landing);
    _keyed.add(landing);
  }

  /// Judges a block or row `keep` line: its units stay, and their address
  /// joins its doc's order.
  void _keepKeyed(KeepLine line, String written, KeyedUnitAddress keyed) {
    final source = _keyedSourceOf(line, keyed);
    final address = _addressOf(keyed);
    requireKeyedUnits(_index, source, address);
    if (!_isNew(line, written, '${source.docPath}#$address', 'keep')) return;
    _keptInPlace[source.docPath] = source;
    _orderedDocs[source.docPath] = source;
    (_keyedKeeps[source.docPath] ??= []).add(address);
    (_named[source.docPath] ??= {}).add(address);
  }

  /// Throws [IndexFault] `argument_invalid` when an earlier line lands units
  /// of [landing]'s address in its destination.
  void _requireFirstLanding(KeyedLanding landing) {
    if (_landedKeys.add('${landing.to.docPath}#${landing.address}')) return;
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      '${landing.to.docPath} already holds ${landing.address}',
    );
  }

  /// Returns the doc whose units [keyed] names.
  ///
  /// Throws [WriteFault] `item_not_found` for a doc the plan creates, which
  /// holds none.
  IndexedDoc _keyedSourceOf(PlanLine line, KeyedUnitAddress keyed) {
    final doc = _docNamed(line, keyed.doc.docPart);
    if (_isCreated(doc)) throw keyedNotFoundOf(doc.docPath, _addressOf(keyed));
    return doc;
  }

  /// Whether [line] names its unit first; an equal instruction on a later
  /// line counts once.
  ///
  /// Throws [IndexFault] `argument_invalid` for a unit an earlier line
  /// instructs otherwise.
  bool _isNew(PlanLine line, String written, String key, String instruction) {
    final first = _seen[key];
    if (first == null) {
      _seen[key] = _Judged(line, written, key, instruction);
      return true;
    }
    if (first.instruction == instruction) return false;
    throw _lineFault(
      line,
      '$written is on line ${first.line.lineNumber} and line '
      '${line.lineNumber} with different instructions',
    );
  }

  ItemTarget _itemOf(PlanLine line, DocAddress unit, String written) {
    final id = unit.sectionKey!;
    final doc = _docNamed(line, unit.docPart);
    if (_isCreated(doc)) throw itemNotFoundOf(ItemTarget(doc: doc, id: id));
    final isScenario = doc.docTypeId == storyType && isScenarioId(id);
    return ItemTarget(doc: doc, id: isScenario ? scenarioIdByValue(id) : id);
  }

  /// Throws [IndexFault] `argument_invalid` when [target] is nested in
  /// another item, which it moves with; [WriteFault] `item_not_found` when
  /// its doc holds no such item.
  void _requireUnit(
    PlanLine line,
    String written,
    DocAddress unit,
    ItemTarget target,
  ) {
    final located = locateItem(_index, target);
    final holder = holderOf(_index, located);
    if (holder == null) return;
    final id = itemKeyOfHead(
      holder.head,
      isHeading: holder.kind == SectionItemKind.heading,
      prefixId: located.prefix,
      isAcceptanceCriteria: false,
    );
    final parent = id == null
        ? 'the item at line ${holder.line} of ${unit.docPart}'
        : '${unit.docPart}#$id';
    throw _lineFault(line, '$written is nested in $parent and moves with it');
  }

  /// Returns where the items of [group] land, in a doc the plan creates
  /// read as its skeleton.
  List<ItemLanding> _landingsOf(_ItemGroup group) {
    final created = [
      for (final doc in _created)
        if (doc.docPath == group.destination.docPath) doc,
    ].firstOrNull;
    return planItemLandings(
      session,
      group.addresses,
      destination: created?.doc ?? group.destination,
      created: created == null
          ? null
          : CreatedDoc(
              doc: created.doc,
              content: created.content,
              chain: overrideChainAbove(
                _index,
                _firstIndexedAbove(created.parent),
                target: created.doc.target,
              ),
            ),
      codeTarget: codeTarget,
    );
  }

  /// Returns the parent of the feature [feature] names, or the first parent
  /// above it the index holds, passing each doc the plan creates.
  IndexedDoc? _firstIndexedAbove(IndexedDoc? feature) {
    var above = feature == null ? null : _parentOf(feature);
    while (above != null && _isCreated(above)) {
      above = _parentOf(above);
    }
    return above;
  }

  IndexedDoc? _parentOf(IndexedDoc doc) => _isCreated(doc)
      ? _created.firstWhere((c) => c.docPath == doc.docPath).parent
      : _index.parentOf(doc);

  bool _isCreated(IndexedDoc doc) =>
      _created.any((created) => created.docPath == doc.docPath);

  MoveDestination _docDestinationOf(
    PlanLine line,
    String written,
    MergedDocType type,
    DocAddress? destination,
  ) {
    if (destination == null) {
      if (type.id == featureType) return const TopDestination();
      throw _topFault(line, written);
    }
    final parentTypeId = type.id == featureType
        ? featureType
        : type.parent ?? (throw StateError('${type.id} has no parent type'));
    final parent = _parentNamed(line, destination.docPart, parentTypeId);
    final at = _created.indexWhere((c) => c.docPath == parent.docPath);
    return at < 0 ? DocDestination(parent) : CreatedDestination(at);
  }

  /// Returns the one doc [value] names among the docs the index holds and
  /// the docs the plan creates, by the index's name rules.
  ///
  /// Throws [IndexFault] `argument_invalid` naming [line] for a doc a later
  /// `new` line creates, then as [WriteSession.target] does.
  IndexedDoc _docNamed(PlanLine line, String value) => _createdBefore(
    line,
    value,
    session.target(value, codeTarget: codeTarget, planned: _ahead),
  );

  /// Returns the one doc of [typeId] [value] names, as [_docNamed] does and
  /// [WriteSession.parentTarget] reads it.
  IndexedDoc _parentNamed(PlanLine line, String value, String typeId) =>
      _createdBefore(
        line,
        value,
        session.parentTarget(
          value,
          typeId,
          codeTarget: codeTarget,
          planned: _ahead,
        ),
      );

  /// Returns [doc], which [value] on [line] names, unless a later `new` line
  /// creates it.
  ///
  /// Throws [IndexFault] `argument_invalid` naming [line] when one does.
  IndexedDoc _createdBefore(PlanLine line, String value, IndexedDoc doc) {
    final createdOn = _createdOn[doc.docPath];
    if (createdOn == null || createdOn < line.lineNumber) return doc;
    throw _lineFault(
      line,
      '$value names a doc that line $createdOn creates; name it after that '
      'line',
    );
  }

  /// Returns the doc [written], a doc unit, names: one that stands before
  /// the plan.
  ///
  /// Throws [IndexFault] `argument_invalid` naming [line] for a doc the plan
  /// creates, which no move or keep line takes.
  IndexedDoc _standingDocOf(PlanLine line, String written) {
    final doc = _docNamed(line, written);
    if (!_isCreated(doc)) return doc;
    throw _lineFault(
      line,
      '$written names a doc this plan creates; a plan line moves or keeps a '
      'doc that stands before the plan',
    );
  }

  /// Plans each `new` line of the plan, the docs of earlier lines as their
  /// parents; a line refused here is refused again at its turn.
  List<IndexedDoc> _plannedAhead() {
    final places = <NewDocPlace>[];
    var planned = const <PlannedDoc>[];
    for (final line in plan.lines.whereType<NewLine>()) {
      final docs = [for (final doc in planned) doc.doc];
      try {
        final place = planNewDoc(
          session,
          docTypeId: line.docType,
          parent: line.parent?.docPart,
          slug: line.slug,
          codeTarget: codeTarget,
          parentNamed: (value, typeId) => session.parentTarget(
            value,
            typeId,
            codeTarget: codeTarget,
            planned: docs,
          ),
        );
        planned = plannedDocsOf(session, [...places, place], SiblingLedger());
        places.add(place);
      } on SpecstoneFault {
        continue;
      }
      _createdOn[planned.last.docPath] = line.lineNumber;
    }
    return [for (final doc in planned) doc.doc];
  }

  /// Returns the DocPath of each doc a `keep` line names a unit of whose
  /// every unit, blocks and rows included, the plan names.
  Set<String> _fullyNamed() => {
    for (final MapEntry(key: docPath, value: doc) in _orderedDocs.entries)
      if (_unitNamesOf(doc).every(_named[docPath]!.contains)) docPath,
  };

  /// Returns the ID of every item and scenario [doc] holds, and the address
  /// of each of its blocks and rows.
  Iterable<String> _unitNamesOf(IndexedDoc doc) sync* {
    if (_index.typeOf(doc) case final type?) {
      for (final unit in keyedUnitsOf(_index.contentOf(doc), type)) {
        yield unit.address;
      }
    }
    yield* _unitIdsOf(doc);
  }

  /// Returns the ID of every item and scenario [doc] holds that is a unit,
  /// nested items left to the unit that holds them.
  Iterable<String> _unitIdsOf(IndexedDoc doc) sync* {
    final content = _index.contentOf(doc);
    final type = _index.typeOf(doc);
    for (final (at, section) in citedSectionsOf(content, type).indexed) {
      if (section.prefixId case final prefix?) {
        yield* unitIdsIn(content, at, type, prefix);
      }
    }
    if (doc.docTypeId != storyType) return;
    for (final id in scenarioIdsIn(_index, doc)) {
      yield id.written;
    }
  }

  IndexFault _topFault(PlanLine line, String written) =>
      _lineFault(line, '$written cannot move to top; top takes a feature');

  /// Throws [IndexFault] `argument_invalid` when [doc], kept in place, comes
  /// before a sibling of its type an earlier `keep` line names.
  void _requireSiblingOrder(PlanLine line, String written, IndexedDoc doc) {
    final number = _siblingNumberOf(doc);
    if (number == null) return;
    final key = '${_index.parentOf(doc)?.docPath} ${doc.docTypeId}';
    final last = _keptDocs[key];
    _keptDocs[key] = number;
    if (last == null || last < number) return;
    throw _lineFault(
      line,
      '$written keeps its place among its siblings; reorder them with '
      'specstone reorder',
    );
  }

  /// Returns the number [doc]'s own segment carries among its siblings; null
  /// for a doc type that numbers none.
  int? _siblingNumberOf(IndexedDoc doc) {
    final type = _index.typeOf(doc);
    final shape = type == null
        ? null
        : DocPathShape.ofDoc(type, _index.set, doc.docPath, target: doc.target);
    if (shape == null) return null;
    return shape.matchOwn(doc.docPath.split('/')[shape.ownIndex])?.number;
  }

  /// Throws [IndexFault] `argument_invalid` when [parent] would hold stories
  /// and sub-features once a doc of [typeId] lands under it.
  void _requireOneKind(PlanLine line, IndexedDoc parent, String typeId) {
    final nestingId = _index.set.nestingType?.id;
    if (typeId != storyType && typeId != nestingId) return;
    final kinds = _children.putIfAbsent(parent.docPath, () => {})..add(typeId);
    if (kinds.length < 2) return;
    throw _lineFault(
      line,
      typeId == storyType
          ? '${nameWithType(parent)} holds sub-${parent.docTypeId}s, so it '
                'takes no story'
          : '${nameWithType(parent)} holds stories, so it takes no '
                'sub-${parent.docTypeId}',
    );
  }

  IndexFault _lineFault(PlanLine line, String reason) => IndexFault(
    IndexFaultCode.argumentInvalid,
    '${plan.path}:${line.lineNumber}: $reason',
  );
}

/// The item addresses that land in one doc, gathered line by line.
final class _ItemGroup {
  new(this.destination);

  final IndexedDoc destination;
  final addresses = <String>[];
}

/// The doc targets of one doc type and destination, gathered line by line.
final class _GroupDraft {
  new(this.docType, this.destination);

  final MergedDocType docType;
  final MoveDestination destination;
  final targets = <IndexedDoc>[];

  DocMoveGroup get group => DocMoveGroup(
    docType: docType,
    targets: targets,
    destination: destination,
  );
}

String _itemKey(ItemTarget target) => '${target.doc.docPath}#${target.id}';

/// Returns `<section key>/<key>` of [keyed].
String _addressOf(KeyedUnitAddress keyed) => '${keyed.sectionKey}/${keyed.key}';

String _writtenOf(DocAddress unit) => unit.sectionKey == null
    ? unit.docPart
    : '${unit.docPart}#${unit.sectionKey}';
