import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart'
    show withoutKeyBlocks;
import 'package:specstone_core/src/doc_model/records_root.dart';
import 'package:specstone_core/src/document_writing/models/new_record.dart';
import 'package:specstone_core/src/document_writing/rewrite_records.dart'
    as rewrite_records;
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/models/frontmatter_yaml.dart';
import 'package:specstone_core/src/index_query/parents.dart'
    show resolveParents;
import 'package:specstone_core/src/index_query/record_entries.dart';
import 'package:specstone_core/src/setup_migration/feature_relative.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/models/placement_doc.dart';
import 'package:specstone_core/src/setup_migration/models/record_placement.dart';
import 'package:specstone_core/src/setup_migration/run_plan.dart'
    show PlannedCreate, draftNote;
import 'package:specstone_core/src/templates/code_link_entry.dart'
    show CodeLinkEntry;
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/models/migration_step.dart';
import 'package:specstone_core/src/templates/models/record_status.dart';

// MARK: - Constants

const _statusKey = 'status';
const _fixThenMigrate = 'fix it, then run specstone migrate again';

// MARK: - Before the steps

/// Returns [type] as it stood before the [steps] moved its code fields into a
/// record: each field of a `move_to_record` step that [type] no longer
/// declares and that is no `status` comes back as an `output_ref` list, which
/// the approval hash leaves out, so a doc approved before the run still
/// compares as approved.
MergedDocType typeBeforeMoves(MergedDocType type, List<MigrationStep> steps) {
  final held = {for (final field in type.fields) field.id};
  final dropped = {
    for (final step in steps.whereType<MoveToRecord>())
      if (step.touches(type.id))
        for (final field in step.fields)
          if (field != _statusKey && !held.contains(field)) field,
  };
  if (dropped.isEmpty) return type;
  return type.copyWith(
    fields: [
      ...type.fields,
      for (final field in dropped)
        MergedField(
          id: field,
          type: FieldType.outputRef,
          list: true,
          pointer: PointerKind.exact,
        ),
    ],
  );
}

/// Returns the fields of [step] that a doc of [type] gives up: all of them for
/// a story or an FR, else those [type] held as path lists before the step.
Set<String> _movableFields(MergedDocType type, MoveToRecord step) {
  if (_isItemType(type.id)) return step.fields.toSet();
  return {
    for (final field in typeBeforeMoves(type, [step]).fields)
      if (field.type == FieldType.outputRef && field.list) field.id,
  };
}

bool _isItemType(String docTypeId) =>
    docTypeId == storyType || docTypeId == frType;

// MARK: - RecordMoves

/// The values the `move_to_record` steps of a run take from their docs, kept
/// until [place] gives each its entry in its feature's record.
final class RecordMoves {
  final _taken = <_Taken>[];

  /// Returns [lf], a doc of [type] at [docPath], without the fields of [step]
  /// it holds, and notes their values for [place]; [lf] itself when it holds
  /// none. A doc that is no story or FR gives up only the fields [type] held
  /// as path lists before the step. A frontmatter the take leaves with no key
  /// goes, with the one blank line after it.
  ///
  /// [plannedPath] is the doc's DocPath after the moves.
  String take({
    required String docPath,
    required String plannedPath,
    required MergedDocType type,
    required MoveToRecord step,
    required String lf,
  }) {
    final names = {
      for (final block in Doc.parse(lf).frontmatter ?? const <KeyBlock>[])
        block.name,
    };
    final movable = _movableFields(type, step);
    final held = [
      for (final field in step.fields)
        if (movable.contains(field) && names.contains(field)) field,
    ];
    if (held.isEmpty) return lf;
    _taken.add(_Taken(docPath, plannedPath, type, held, lf));
    return withoutKeyBlocks(lf, held);
  }

  /// Plans where every value taken lands, in the records of [recordType] of
  /// [set], over [docs], the typed docs of the run.
  ///
  /// With no [recordType] no value has a place; with no value taken there is
  /// nothing to place.
  ///
  /// A value lands in its feature's record: added to the record the feature
  /// has, or in a new draft record at the record doc type's path. With two or
  /// more code targets a story's or an FR's value lands in the record of
  /// [firstTarget], the target the spec tree moves to, and the list field of
  /// any other doc in the record of the doc's own target. A value the record
  /// already holds for its item is kept as it is; a different one, or any
  /// value no record entry takes, is `value_unplaced`, listed for every such
  /// doc at once. A list entry whose prefix the record holds is skipped, the
  /// code fingerprints left out of the compare.
  ///
  /// [isTaken] is the run's `takenAfterMoves` read for a DocPath; a new
  /// record whose path it holds is `value_unplaced` for each doc whose value
  /// it carries, since that entry is none of [docs]' records.
  RecordPlacement place({
    required MergedSet set,
    required MergedDocType? recordType,
    required String? firstTarget,
    required List<PlacementDoc> docs,
    required bool Function(String docPath) isTaken,
  }) {
    if (_taken.isEmpty) {
      return const RecordPlacement(unplaced: [], edits: {}, creates: []);
    }
    if (recordType == null) {
      return RecordPlacement(
        unplaced: [
          for (final taken in _taken)
            _fault(
              taken,
              taken.fields.first,
              'no doc type holds a record_status field, so no record takes '
              '${taken.fields.first}',
            ),
        ],
        edits: const {},
        creates: const [],
      );
    }
    final tree = _Tree(set, recordType, firstTarget, docs);
    final unplaced = <MigrateFault>[];
    final groups = <String, _Group>{};
    for (final taken in _taken) {
      switch (tree.landingOf(taken)) {
        case null:
          unplaced.add(
            _fault(
              taken,
              taken.fields.first,
              'no feature holds this ${taken.type.id}, so no record takes its '
              '${taken.fields.first}',
            ),
          );
        case final landing:
          switch (_read(taken, isList: landing.item == null)) {
            case _Bad(:final key, :final why):
              unplaced.add(_fault(taken, key, why));
            case final _Values values:
              (groups[landing.key] ??= _Group(
                landing.feature,
                landing.target,
              )).movers.add(_Mover(taken, landing.item, values));
          }
      }
    }
    final edits = <String, String>{};
    final creates = <NewRecord>[];
    for (final group in groups.values) {
      final landed = _land(tree, recordType, group, isTaken);
      unplaced.addAll(landed.unplaced);
      switch (landed.record) {
        case _LandedRecord(:final docPath, :final text, isNew: true):
          creates.add(NewRecord(docPath: docPath, text: text));
        case _LandedRecord(:final docPath, :final text, isNew: false):
          edits[docPath] = text;
        case null:
          break;
      }
    }
    unplaced.sort((a, b) => compareCodePoints(a.file!, b.file!));
    return RecordPlacement(unplaced: unplaced, edits: edits, creates: creates);
  }
}

// MARK: - Plan output

/// Throws the first of [faults] on each doc, the first as the fault and the
/// rest chained through `more`; nothing when [faults] is empty.
///
/// A doc can collide once per rival and once per step, or hold several values
/// no record takes; it is listed once.
void throwFaultsPerDoc(List<MigrateFault> faults) {
  final seen = <String?>{};
  final perDoc = [
    for (final fault in faults)
      if (seen.add(fault.file)) fault,
  ];
  if (perDoc.isEmpty) return;
  final first = perDoc.first;
  throw MigrateFault(
    first.code,
    first.message,
    file: first.file,
    key: first.key,
    more: perDoc.sublist(1),
  );
}

/// Returns the records [placement] creates as plan creates, each a draft, in
/// code point order of their paths.
List<PlannedCreate> recordCreatesOf(RecordPlacement placement) => [
  for (final record in placement.creates)
    PlannedCreate(
      path: projectPathOfDocPath(record.docPath),
      text: record.text,
      note: draftNote,
    ),
]..sort((a, b) => compareCodePoints(a.path, b.path));

// MARK: - Landing

/// The record of one feature after its movers land: its DocPath and text, and
/// whether it is new; null when nothing lands.
final class _Landed {
  const new({required this.unplaced, required this.record});

  final List<MigrateFault> unplaced;
  final _LandedRecord? record;
}

/// A record's DocPath and text once its movers land, and whether the record is
/// new.
final class _LandedRecord {
  const new({required this.docPath, required this.text, required this.isNew});

  final String docPath;
  final String text;
  final bool isNew;
}

/// Which movers a refusal names: all, those moving a code path, or those
/// moving a `covers` list.
enum _Scope {
  all,
  code,
  covers;

  bool names(_Mover mover) => switch (this) {
    all => true,
    code => !mover.isList && mover.values.code.isNotEmpty,
    covers => mover.isList,
  };
}

/// Returns the scope of the movers whose values the [field] of [recordType]
/// holds.
_Scope _scopeOfField(String field, MergedDocType recordType) {
  if (field == recordCodeFieldOf(recordType)?.id) return _Scope.code;
  if (field == recordCoversFieldOf(recordType)?.id) return _Scope.covers;
  return _Scope.all;
}

/// The lines the movers of one record give it, and the faults of the values
/// no entry takes.
final class _Gathered {
  new(this.unplaced);

  final List<MigrateFault> unplaced;
  final statuses = <String>[];
  final code = <String>[];
  final covers = <String>[];

  bool get isEmpty => statuses.isEmpty && code.isEmpty && covers.isEmpty;

  RecordLines get lines =>
      RecordLines(statuses: statuses, code: code, covers: covers);
}

_Landed _land(
  _Tree tree,
  MergedDocType recordType,
  _Group group,
  bool Function(String docPath) isTaken,
) {
  final feature = group.feature;
  final held = tree.recordOf(feature, group.target);
  if (held != null && !_hasValidFrontmatter(held.lf)) {
    return _refused(
      group,
      const [],
      'the record of ${feature.name} has frontmatter that is not valid YAML',
    );
  }
  final gathered = _gather(
    group,
    recordType,
    tree.indexedRecordOf(held, feature),
  );
  if (gathered.isEmpty) {
    return _Landed(unplaced: gathered.unplaced, record: null);
  }
  final lacking = _lackingFields(recordType, gathered);
  if (lacking.isNotEmpty) {
    return _Landed(
      unplaced: [
        ...gathered.unplaced,
        for (final reason in lacking)
          ..._refusalsOf(group, reason.why, scope: reason.scope),
      ],
      record: null,
    );
  }
  return held == null
      ? _create(tree, recordType, group, gathered, isTaken)
      : _addTo(held, recordType, group, gathered);
}

_Landed _refused(
  _Group group,
  List<MigrateFault> unplaced,
  String why, {
  _Scope scope = _Scope.all,
}) => _Landed(
  unplaced: [
    ...unplaced,
    ..._refusalsOf(group, why, scope: scope),
  ],
  record: null,
);

/// Returns one fault giving [why] for each mover of [group] that [scope]
/// names.
List<MigrateFault> _refusalsOf(
  _Group group,
  String why, {
  required _Scope scope,
}) => [
  for (final mover in group.movers)
    if (scope.names(mover))
      _fault(
        mover.taken,
        scope == _Scope.code ? mover.values.codeKey! : mover.key,
        why,
      ),
];

/// Sorts the values of the movers of [group] into the lines the record
/// [indexed] lacks, and the faults of the values that differ from its entries.
_Gathered _gather(_Group group, MergedDocType recordType, IndexedDoc indexed) {
  final entries = {
    for (final entry in recordEntriesOf(indexed, recordType)) entry.item: entry,
  };
  final coversHeld = {
    for (final line in indexed.valuesOf(
      recordCoversFieldOf(recordType)?.id ?? '',
    ))
      CodeLinkEntry(line).pointer,
  };
  final gathered = _Gathered([]);
  for (final mover in group.movers) {
    final item = mover.item;
    if (item == null) {
      for (final line in mover.values.covers) {
        if (coversHeld.add(CodeLinkEntry(line).pointer)) {
          gathered.covers.add(line);
        }
      }
      continue;
    }
    final entry = entries[item];
    final conflict = _conflictOf(mover.values, entry);
    if (conflict != null) {
      gathered.unplaced.add(
        _fault(
          mover.taken,
          conflict,
          '$conflict differs from what the record of ${group.feature.name} '
          'holds for $item',
        ),
      );
      continue;
    }
    final status = mover.values.status;
    if (status != null && entry?.status == null) {
      gathered.statuses.add('$item:${status.wire}');
    }
    if (mover.values.code.isNotEmpty && (entry?.codePaths.isEmpty ?? true)) {
      gathered.code.addAll([
        for (final path in mover.values.code) '$item:$path',
      ]);
    }
  }
  return gathered;
}

/// The reason a record type has no field for some gathered lines, and the
/// movers it names.
final class _Lacking {
  const new(this.why, this.scope);

  final String why;
  final _Scope scope;
}

/// Returns each reason [recordType] has no field for some [gathered] lines,
/// so one run lists every mover that lacks a field.
List<_Lacking> _lackingFields(MergedDocType recordType, _Gathered gathered) => [
  if (gathered.code.isNotEmpty && recordCodeFieldOf(recordType) == null)
    _Lacking('${recordType.id} has no field for code paths', _Scope.code),
  if (gathered.covers.isNotEmpty && recordCoversFieldOf(recordType) == null)
    _Lacking('${recordType.id} has no field for covered code', _Scope.covers),
];

_Landed _addTo(
  PlacementDoc held,
  MergedDocType recordType,
  _Group group,
  _Gathered gathered,
) {
  final String? added;
  try {
    added = addRecordLines(held.lf, recordType, gathered.lines);
  } on RecordFieldUnreadable catch (error) {
    return _refused(
      group,
      gathered.unplaced,
      'the ${error.field} block of the record of ${group.feature.name} is '
      'not valid YAML',
      scope: _scopeOfField(error.field, recordType),
    );
  }
  return _Landed(
    unplaced: gathered.unplaced,
    record: _LandedRecord(
      docPath: held.plannedPath,
      text: added ?? held.lf,
      isNew: false,
    ),
  );
}

_Landed _create(
  _Tree tree,
  MergedDocType recordType,
  _Group group,
  _Gathered gathered,
  bool Function(String docPath) isTaken,
) {
  final feature = group.feature;
  final created = tree.newRecordOf(
    feature,
    gathered.lines,
    target: group.target,
  );
  if (created == null) {
    return _refused(
      group,
      gathered.unplaced,
      'no path places the record of ${feature.name}',
    );
  }
  if (isTaken(created.docPath)) {
    return _refused(
      group,
      gathered.unplaced,
      'the record of ${feature.name} goes to ${created.docPath}, which holds '
      'a file the run cannot read as a record',
    );
  }
  return _Landed(
    unplaced: gathered.unplaced,
    record: _LandedRecord(
      docPath: created.docPath,
      text: created.text,
      isNew: true,
    ),
  );
}

/// Returns the key of the first value of [values] that differs from what
/// [entry], the record's entry for the item, already holds; null when none
/// does.
String? _conflictOf(_Values values, RecordEntry? entry) {
  if (entry == null) return null;
  final status = values.status;
  if (status != null && entry.status != null && entry.status != status) {
    return _statusKey;
  }
  final held = entry.codePaths;
  if (values.code.isNotEmpty &&
      held.isNotEmpty &&
      !_sameList(values.code, held)) {
    return values.codeKey;
  }
  return null;
}

bool _sameList(List<String> a, List<String> b) =>
    a.length == b.length && a.indexed.every((entry) => entry.$2 == b[entry.$1]);

bool _hasValidFrontmatter(String lf) {
  final blocks = Doc.parse(lf).frontmatter;
  return blocks == null ||
      FrontmatterYaml.parse(blocks.map((b) => b.text).join()).errorLine == null;
}

MigrateFault _fault(_Taken taken, String key, String why) => MigrateFault(
  MigrateFaultCode.valueUnplaced,
  '$why; $_fixThenMigrate',
  file: taken.docPath,
  key: key,
);

// MARK: - Reading the values

/// What one doc gave up: its path before the moves and after, its doc type,
/// the fields of the step it held, and its text before the fields left.
final class _Taken {
  const new(this.docPath, this.plannedPath, this.type, this.fields, this.lf);

  final String docPath;
  final String plannedPath;
  final MergedDocType type;
  final List<String> fields;
  final String lf;
}

/// One doc's values on their way to the entry of [item], or, with no item, to
/// the `covers` list of the record.
final class _Mover {
  const new(this.taken, this.item, this.values);

  final _Taken taken;

  /// The item's name relative to its feature; null for a doc that is no story
  /// or FR, whose list field has no item.
  final String? item;
  final _Values values;

  bool get isList => item == null;

  /// The key a refusal names: the first field the doc held.
  String get key => taken.fields.first;
}

/// The movers that land in one record: a feature's record in one code target.
final class _Group {
  new(this.feature, this.target);

  final IndexedDoc feature;
  final String? target;
  final movers = <_Mover>[];
}

sealed class _Read {
  const new();
}

/// The status and code paths a doc held, each a value a record entry takes, or
/// the paths its list field held.
final class _Values extends _Read {
  const new(this.status, this.code, this.codeKey, {this.covers = const []});

  final RecordStatus? status;
  final List<String> code;

  /// The key of the first field that held a code path.
  final String? codeKey;

  /// The paths of the list field of a doc that is no story or FR.
  final List<String> covers;
}

/// A value no record entry takes, under [key].
final class _Bad extends _Read {
  const new(this.key, this.why);

  final String key;
  final String why;
}

_Read _read(_Taken taken, {required bool isList}) {
  final values = frontmatterValuesOf(Doc.parse(taken.lf));
  final first = taken.fields.first;
  if (values.isEmpty) {
    return _Bad(
      first,
      'the frontmatter is not valid YAML, so $first cannot move to a record',
    );
  }
  if (isList) return _readList(taken, values);
  RecordStatus? status;
  final code = <String>[];
  String? codeKey;
  for (final field in taken.fields) {
    final value = values[field];
    if (value == null) continue;
    if (field == _statusKey) {
      status = value is String ? RecordStatus.byWire(value) : null;
      if (status == null || status == RecordStatus.skipped) {
        return _Bad(
          field,
          'status $value is no status a record entry takes, planned, '
          'implemented, or deprecated',
        );
      }
      continue;
    }
    final paths = _codePathsOf(value);
    if (paths == null) return _Bad(field, '$field is no list of code paths');
    if (paths.isNotEmpty) codeKey ??= field;
    code.addAll(paths);
  }
  return _Values(status, code, codeKey);
}

/// Returns the paths every field of [taken] lists, from [values], its
/// frontmatter, in field order.
_Read _readList(_Taken taken, Map<String, Object?> values) {
  final covers = <String>[];
  for (final field in taken.fields) {
    final value = values[field];
    if (value == null) continue;
    final paths = _codePathsOf(value);
    if (paths == null) return _Bad(field, '$field is no list of code paths');
    covers.addAll(paths);
  }
  return _Values(null, const [], null, covers: covers);
}

/// Returns the code paths [value] lists, a lone path as a list of one, or
/// null when it is no list of non-empty single-line text.
List<String>? _codePathsOf(Object value) {
  final paths = switch (value) {
    final String path => [path],
    final List<Object?> list => [for (final path in list) path],
    _ => null,
  };
  if (paths == null) return null;
  final isValid = paths.every(
    (path) => path is String && path.trim().isNotEmpty && !path.contains('\n'),
  );
  return isValid ? paths.cast<String>() : null;
}

// MARK: - The tree

/// The feature a taken doc lands under, the item it lands as (null for a list
/// field), and the code target of the record it lands in.
final class _Landing {
  const new(this.feature, this.item, this.target);

  final IndexedDoc feature;
  final String? item;
  final String? target;

  /// Names the record: the feature's in [target].
  String get key => '${target ?? ''}\n${feature.docPath}';
}

/// The typed docs of the run as the index reads them, to find the feature and
/// the record of a story or an FR.
final class _Tree {
  new(this._set, this._recordType, this._firstTarget, List<PlacementDoc> docs) {
    for (final doc in docs) {
      final type = doc.type;
      if (type == null) continue;
      final indexed = IndexedDoc(
        docPath: doc.plannedPath,
        docTypeId: type.id,
        name: docNameOf(doc.plannedPath, type, target: doc.target),
        frontmatter: const {},
        tokens: 0,
      );
      _byPath[doc.plannedPath] = indexed;
      _targets[doc.plannedPath] = doc.target;
      if (type.id == _recordType.id) {
        (_records[doc.target] ??= {})[indexed.name] = doc;
      }
    }
    _parents = resolveParents(_byPath.values, _set).parents;
  }

  final MergedSet _set;
  final MergedDocType _recordType;
  final String? _firstTarget;
  final _byPath = <String, IndexedDoc>{};
  final _targets = <String, String?>{};

  /// The records of the run by code target, then by feature name.
  final _records = <String?, Map<String, PlacementDoc>>{};
  late final Map<String, String> _parents;

  /// Returns where [taken] lands: the feature it sits under, and for a story
  /// or an FR its name relative to that feature and the first target, else no
  /// item and the doc's own target; null for an orphan.
  _Landing? landingOf(_Taken taken) {
    final doc = _byPath[taken.plannedPath];
    if (doc == null) return null;
    if (_isItemType(doc.docTypeId!)) {
      final landing = featureRelativeOf(doc, _byPath, _parents);
      return landing == null
          ? null
          : _Landing(landing.feature, landing.relative, _firstTarget);
    }
    final feature = featureOf(doc, _byPath, _parents);
    return feature == null
        ? null
        : _Landing(feature, null, _targets[taken.plannedPath] ?? _firstTarget);
  }

  /// Returns the record of [feature] in [target] the run already holds, or
  /// null.
  PlacementDoc? recordOf(IndexedDoc feature, String? target) =>
      _records[target]?[feature.name];

  /// Returns [held], as the index reads it, or an empty record of [feature].
  IndexedDoc indexedRecordOf(PlacementDoc? held, IndexedDoc feature) =>
      IndexedDoc(
        docPath: held?.plannedPath ?? '',
        docTypeId: _recordType.id,
        name: feature.name,
        frontmatter: held == null
            ? const {}
            : frontmatterValuesOf(Doc.parse(held.lf)),
        tokens: 0,
      );

  /// Returns the new record of [feature] in [target] holding [lines]; null
  /// when the record doc type has no path in the feature's spec folder.
  NewRecord? newRecordOf(
    IndexedDoc feature,
    RecordLines lines, {
    required String? target,
  }) {
    final featureType = _set.lookup(feature.docTypeId!);
    if (featureType == null) return null;
    return rewrite_records.newRecordOf(
      _set,
      _recordType,
      featureType: featureType,
      featureDocPath: feature.docPath,
      featureName: feature.name,
      lines: lines,
      target: target,
    );
  }
}
