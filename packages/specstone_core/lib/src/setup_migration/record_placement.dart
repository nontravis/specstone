import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart' show withKeyBlock;
import 'package:specstone_core/src/document_writing/rewrite_records.dart'
    as rewrite_records;
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/line_facts.dart'
    show parseFrontmatterYaml;
import 'package:specstone_core/src/index_query/parents.dart'
    show resolveParents;
import 'package:specstone_core/src/index_query/record_entries.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/run_plan.dart'
    show PlannedCreate, draftNote;
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart'
    show FieldType, PointerKind, RecordStatus;
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pack_migration.dart';

// MARK: - Constants

const _docsFolder = 'docs/';
const _statusKey = 'status';
const _fixThenMigrate = 'fix it, then run specstone migrate again';

// MARK: - Types

/// A typed doc of the run as the placement reads it: its DocPath after the
/// moves, its doc type, the code target whose pattern set matched it (null for
/// a shared doc), and its LF text after the steps so far.
typedef PlacementDoc = ({
  String plannedPath,
  MergedDocType? type,
  String? target,
  String lf,
});

/// A record the pass creates, as a draft: its DocPath and its laid-out text.
typedef NewRecord = ({String docPath, String text});

/// Where the values a `move_to_record` step took land: the `value_unplaced`
/// faults when any value has no place, else the new text of each existing
/// record by its planned DocPath and each record to create.
typedef RecordPlacement = ({
  List<MigrateFault> unplaced,
  Map<String, String> edits,
  List<NewRecord> creates,
});

// MARK: - Before the steps

/// Returns [type] as it stood before the [steps] moved its code fields into a
/// record: each field of a `move_to_record` step that [type] no longer
/// declares and that is no `status` comes back as an `output_ref` list, which
/// the approval hash leaves out, so a doc approved before the run still
/// compares as approved (apply_steps_and_pins E38).
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

// MARK: - RecordMoves

/// The values the `move_to_record` steps of a run take from their docs, kept
/// until [place] gives each its entry in its feature's record.
final class RecordMoves {
  final _taken = <_Taken>[];

  /// Returns [lf], a doc of [type] at [docPath], without the fields of [step]
  /// it holds, and notes their values for [place]; [lf] itself when it holds
  /// none.
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
    final held = [
      for (final field in step.fields)
        if (names.contains(field)) field,
    ];
    if (held.isEmpty) return lf;
    _taken.add(_Taken(docPath, plannedPath, type, held, lf));
    return held.fold(lf, (text, field) => withKeyBlock(text, field, null));
  }

  /// Plans where every value taken lands, in the records of [recordType] of
  /// [set], over [docs], the typed docs of the run.
  ///
  /// With no [recordType] no value has a place; with no value taken there is
  /// nothing to place.
  ///
  /// A value lands in its feature's record: added to the record the feature
  /// has, or in a new draft record at the record doc type's path. With two or
  /// more code targets that record is the one of [firstTarget], the target the
  /// spec tree moves to. A value the record already holds for its item is kept
  /// as it is; a different one, or any value no record entry takes, is
  /// `value_unplaced`, listed for every such doc at once
  /// (apply_steps_and_pins E33 to E35).
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
      return (unplaced: const [], edits: const {}, creates: const []);
    }
    if (recordType == null) {
      return (
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
    final byFeature = <String, ({IndexedDoc feature, List<_Mover> movers})>{};
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
          switch (_read(taken)) {
            case _Bad(:final key, :final why):
              unplaced.add(_fault(taken, key, why));
            case final _Values values:
              (byFeature[landing.feature.docPath] ??= (
                feature: landing.feature,
                movers: [],
              )).movers.add(_Mover(taken, landing.item, values));
          }
      }
    }
    final edits = <String, String>{};
    final creates = <NewRecord>[];
    for (final (:feature, :movers) in byFeature.values) {
      final landed = _land(tree, recordType, feature, movers, isTaken);
      unplaced.addAll(landed.unplaced);
      switch (landed.record) {
        case (:final docPath, :final text, isNew: true):
          creates.add((docPath: docPath, text: text));
        case (:final docPath, :final text, isNew: false):
          edits[docPath] = text;
        case null:
          break;
      }
    }
    unplaced.sort((a, b) => compareCodePoints(a.file!, b.file!));
    return (unplaced: unplaced, edits: edits, creates: creates);
  }
}

// MARK: - Plan output

/// Throws the first of [faults] on each doc, the first as the fault and the
/// rest chained through `more`; nothing when [faults] is empty.
///
/// A doc can collide once per rival and once per step, or hold several values
/// no record takes; it is listed once (INV-16).
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
      path: '$_docsFolder${record.docPath}',
      text: record.text,
      note: draftNote,
    ),
]..sort((a, b) => compareCodePoints(a.path, b.path));

// MARK: - Landing

/// The record of one feature after its movers land: its DocPath and text, and
/// whether it is new; null when nothing lands.
typedef _Landed = ({
  List<MigrateFault> unplaced,
  ({String docPath, String text, bool isNew})? record,
});

_Landed _land(
  _Tree tree,
  MergedDocType recordType,
  IndexedDoc feature,
  List<_Mover> movers,
  bool Function(String docPath) isTaken,
) {
  List<MigrateFault> refuseAll(String why, {bool codeOnly = false}) => [
    for (final mover in movers)
      if (!codeOnly || mover.values.code.isNotEmpty)
        _fault(
          mover.taken,
          codeOnly ? mover.values.codeKey! : mover.taken.fields.first,
          why,
        ),
  ];
  final held = tree.recordOf(feature);
  if (held != null && !_hasValidFrontmatter(held.lf)) {
    return (
      unplaced: refuseAll(
        'the record of ${feature.name} has frontmatter that is not valid YAML',
      ),
      record: null,
    );
  }
  final entries = {
    for (final entry in recordEntriesOf(
      tree.indexedRecordOf(held, feature),
      recordType,
    ))
      entry.item: entry,
  };
  final unplaced = <MigrateFault>[];
  final statuses = <String>[];
  final code = <String>[];
  for (final mover in movers) {
    final conflict = _conflictOf(mover.values, entries[mover.item]);
    if (conflict != null) {
      unplaced.add(
        _fault(
          mover.taken,
          conflict,
          '$conflict differs from what the record of ${feature.name} holds '
          'for ${mover.item}',
        ),
      );
      continue;
    }
    final entry = entries[mover.item];
    final status = mover.values.status;
    if (status != null && entry?.status == null) {
      statuses.add('${mover.item}:${status.wire}');
    }
    if (mover.values.code.isNotEmpty && (entry?.codePaths.isEmpty ?? true)) {
      code.addAll([
        for (final path in mover.values.code) '${mover.item}:$path',
      ]);
    }
  }
  if (statuses.isEmpty && code.isEmpty) {
    return (unplaced: unplaced, record: null);
  }
  _Landed refused(String why, {bool codeOnly = false}) => (
    unplaced: [
      ...unplaced,
      ...refuseAll(why, codeOnly: codeOnly),
    ],
    record: null,
  );
  if (code.isNotEmpty && recordCodeFieldOf(recordType) == null) {
    return refused(
      '${recordType.id} has no field for code paths',
      codeOnly: true,
    );
  }
  final lines = (statuses: statuses, code: code);
  if (held != null) {
    final String? added;
    try {
      added = addRecordLines(held.lf, recordType, lines);
    } on RecordFieldUnreadable catch (error) {
      return refused(
        'the ${error.field} block of the record of ${feature.name} is not '
        'valid YAML',
        codeOnly: error.field == recordCodeFieldOf(recordType)?.id,
      );
    }
    return (
      unplaced: unplaced,
      record: (docPath: held.plannedPath, text: added ?? held.lf, isNew: false),
    );
  }
  final created = tree.newRecordOf(feature, lines);
  if (created == null) {
    return refused('no path places the record of ${feature.name}');
  }
  if (isTaken(created.docPath)) {
    return refused(
      'the record of ${feature.name} goes to ${created.docPath}, which holds '
      'a file the run cannot read as a record',
    );
  }
  return (
    unplaced: unplaced,
    record: (docPath: created.docPath, text: created.text, isNew: true),
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
      parseFrontmatterYaml(blocks.map((b) => b.text).join()).errorLine == null;
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

/// One doc's values on their way to the entry of [item].
final class _Mover {
  const new(this.taken, this.item, this.values);

  final _Taken taken;

  /// The item's name relative to its feature.
  final String item;
  final _Values values;
}

sealed class _Read {
  const new();
}

/// The status and code paths a doc held, each a value a record entry takes.
final class _Values extends _Read {
  const new(this.status, this.code, this.codeKey);

  final RecordStatus? status;
  final List<String> code;

  /// The key of the first field that held a code path.
  final String? codeKey;
}

/// A value no record entry takes, under [key].
final class _Bad extends _Read {
  const new(this.key, this.why);

  final String key;
  final String why;
}

_Read _read(_Taken taken) {
  final values = frontmatterValuesOf(Doc.parse(taken.lf));
  final first = taken.fields.first;
  if (values.isEmpty) {
    return _Bad(
      first,
      'the frontmatter is not valid YAML, so $first cannot move to a record',
    );
  }
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
      if (type.id == _recordType.id && doc.target == _firstTarget) {
        _records[indexed.name] = doc;
      }
    }
    _parents = resolveParents(_byPath.values, _set).parents;
  }

  final MergedSet _set;
  final MergedDocType _recordType;
  final String? _firstTarget;
  final _byPath = <String, IndexedDoc>{};
  final _records = <String, PlacementDoc>{};
  late final Map<String, String> _parents;

  /// Returns the feature a story or an FR of [taken] sits under and its name
  /// relative to that feature; null for any other doc and for an orphan.
  ({IndexedDoc feature, String item})? landingOf(_Taken taken) {
    final doc = _byPath[taken.plannedPath];
    if (doc == null ||
        (doc.docTypeId != storyType && doc.docTypeId != frType)) {
      return null;
    }
    var at = doc;
    while (at.docTypeId != featureType) {
      final parent = _byPath[_parents[at.docPath]];
      if (parent == null) return null;
      at = parent;
    }
    return (feature: at, item: doc.name.substring(at.name.length + 1));
  }

  /// Returns the record of [feature] the run already holds, or null.
  PlacementDoc? recordOf(IndexedDoc feature) => _records[feature.name];

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

  /// Returns the new record of [feature] holding [lines]; null when the
  /// record doc type has no path in the feature's spec folder.
  ({String docPath, String text})? newRecordOf(
    IndexedDoc feature,
    RecordLines lines,
  ) {
    final featureType = _set.lookup(feature.docTypeId!);
    if (featureType == null) return null;
    return rewrite_records.newRecordOf(
      _set,
      _recordType,
      featureType: featureType,
      featureDocPath: feature.docPath,
      featureName: feature.name,
      lines: lines,
      target: _firstTarget,
    );
  }
}
