import 'dart:convert';

import 'package:specstone_core/src/doc_model/doc_path_shape.dart';
import 'package:specstone_core/src/document_writing/models/new_record.dart';
import 'package:specstone_core/src/document_writing/models/record_plan.dart';
import 'package:specstone_core/src/document_writing/models/renamed_names.dart';
import 'package:specstone_core/src/document_writing/models/text_edit.dart';
import 'package:specstone_core/src/document_writing/move_item.dart'
    show ItemLanding;
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/new_doc.dart'
    show skeletonOf;
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/matrix_rows.dart';
import 'package:specstone_core/src/index_query/record_entries.dart';
import 'package:specstone_core/src/rendering/formatter.dart' show layOutDoc;
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';

const _edgeCasesKey = 'edge_cases';

/// Where a story or FR entry goes: the feature whose record takes it, and its
/// name relative to that feature.
final class _Landing {
  const new({required this.feature, required this.name});

  final IndexedDoc feature;
  final String name;
}

/// The items of a record that stay under a new name, and those that leave.
final class _RecordItemMoves {
  const new({required this.inPlace, required this.leaving});

  final Map<String, String> inPlace;
  final Map<String, _Landing> leaving;
}

/// The feature a record's arrivals land in, by DocPath, and their code target.
final class _ArrivalKey {
  const new({required this.featurePath, required this.target});

  final String featurePath;
  final String? target;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is _ArrivalKey &&
      other.featurePath == featurePath &&
      other.target == target;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(featurePath, target);
}

/// The entries bound for one feature's record in one target.
final class _Arrival {
  new(this.feature, this.target);

  final IndexedDoc feature;
  final String? target;
  final statuses = <String>[];
  final code = <String>[];
  final tests = <String>[];
  final rows = <String>[];

  void take(RecordLines lines) {
    statuses.addAll(lines.statuses);
    code.addAll(lines.code);
    tests.addAll(lines.tests);
    rows.addAll(lines.rows);
  }
}

/// Returns the record edits and the new records that follow [renamed], the
/// names that change, mapped from `(doc type id, old name)` to the new name.
///
/// An entry names its item relative to its record's feature, so it changes
/// only when the item's name changes inside that feature: the entry is
/// renamed in place. An item that left the feature moves its lines and matrix
/// rows, as written but for the item, to the record of the feature it landed
/// in, in the same target, and they leave the old record; a target whose old
/// record holds no line of it changes nothing, and a landing feature with no
/// record in that target gets one, as a draft, holding them. The feature
/// itself keeps its own entry.
///
/// Throws [RenderFault] `output_not_writable` before the journal for a record
/// whose field block is not valid YAML, and for a file at a record path the
/// index lacks that is no UTF-8 record, so no line is dropped.
RecordPlan planRecordRewrites(WriteSession session, RenamedNames renamed) {
  final recordType = session.index.set.recordDocType;
  if (recordType == null || renamed.isEmpty) {
    return const RecordPlan(edits: {}, creates: []);
  }
  return _Planner(session, recordType, renamed).plan();
}

/// Where a matrix row's edge case lands: the requirement's feature and name
/// relative to it, and the edge case's ID there.
final class _RowMove {
  const new({required this.target, required this.edgeCase});

  final _Landing target;
  final String edgeCase;
}

/// What the moved edge cases do to the rows of one record's matrix: the new
/// text of each row that stays in it, by file line index, and the rows that
/// leave it for the record of another feature.
final class _RowChanges {
  const new({required this.rewritten, required this.leaving});

  final Map<int, String> rewritten;
  final Map<int, _RowLeaving> leaving;

  bool get isEmpty => rewritten.isEmpty && leaving.isEmpty;
}

/// A matrix row that leaves its record: the feature it lands in, and the row.
final class _RowLeaving {
  const new({required this.feature, required this.row});

  final IndexedDoc feature;
  final String row;
}

/// Returns the record edits and the new records that follow the edge cases
/// [landings] move, each row of a matrix that names one set to name it at its
/// target requirement and new number.
///
/// A row keeps its literal, reason, and fingerprint. A row whose edge case
/// lands in a requirement of another feature leaves its record for that
/// feature's, in the same target, as [planRecordRewrites] carries an item's
/// rows; a landing feature with no record in that target gets one, as a draft.
/// A row that names an edge case which stays keeps its text. Throws
/// [RenderFault] `output_not_writable` as [planRecordRewrites] does.
RecordPlan planEdgeCaseRowMoves(
  WriteSession session,
  List<ItemLanding> landings,
) {
  final recordType = session.index.set.recordDocType;
  final moves = _rowMovesOf(session.index, landings);
  if (recordType == null || moves.isEmpty) {
    return const RecordPlan(edits: {}, creates: []);
  }
  return _Planner(
    session,
    recordType,
    const RenamedNames({}),
    rowMoves: moves,
  ).plan();
}

/// Returns the row move of each edge case [landings] move, by the DocPath of
/// the feature of its source requirement, then by the `<item> <edge case>` a
/// row that names it opens with.
Map<String, Map<String, _RowMove>> _rowMovesOf(
  DocIndex index,
  List<ItemLanding> landings,
) {
  final moves = <String, Map<String, _RowMove>>{};
  for (final landing in landings) {
    if (landing.sectionKey != _edgeCasesKey ||
        landing.from.doc.docTypeId != frType) {
      continue;
    }
    final source = _landingOf(index, landing.from.doc, const RenamedNames({}));
    final target = _landingOf(index, landing.to, const RenamedNames({}));
    if (source == null || target == null) continue;
    (moves[source.feature.docPath] ??=
        {})['${source.name} ${landing.from.id}'] = _RowMove(
      target: target,
      edgeCase: landing.newId,
    );
  }
  return moves;
}

/// Returns what [moves] do to the rows of [lfText], a record of [feature].
_RowChanges _rowChangesOf(
  String lfText,
  MergedDocType recordType,
  Map<String, _RowMove> moves,
  IndexedDoc feature,
) {
  final lines = lfText.split('\n');
  final rewritten = <int, String>{};
  final leaving = <int, _RowLeaving>{};
  for (final row in matrixLinesIn(lfText, recordType).whereType<MatrixRow>()) {
    final move = moves['${row.item} ${row.edgeCase}'];
    if (move == null) continue;
    final at = row.line - 1;
    final rest = lines[at].substring(
      2 + row.item.length + 1 + row.edgeCase.length,
    );
    final moved = '- ${move.target.name} ${move.edgeCase}$rest';
    if (move.target.feature.docPath == feature.docPath) {
      rewritten[at] = moved;
    } else {
      leaving[at] = _RowLeaving(feature: move.target.feature, row: moved);
    }
  }
  return _RowChanges(rewritten: rewritten, leaving: leaving);
}

/// Returns [lfText] with the rows [changes] rewrite set and the rows it
/// leaves dropped; every other line stays as written.
String _withRowChanges(String lfText, _RowChanges changes) => [
  for (final (at, line) in lfText.split('\n').indexed)
    if (!changes.leaving.containsKey(at)) changes.rewritten[at] ?? line,
].join('\n');

/// Plans the entries of every record of one rename or move.
final class _Planner {
  new(this.session, this.recordType, this.renamed, {this.rowMoves = const {}});

  final WriteSession session;
  final MergedDocType recordType;
  final RenamedNames renamed;

  /// The moved edge cases, by the DocPath of the feature whose records name
  /// their requirement, then by the `<item> <edge case>` a row opens with.
  final Map<String, Map<String, _RowMove>> rowMoves;
  final _edits = <String, TextEdit>{};
  final _arrivals = <_ArrivalKey, _Arrival>{};

  DocIndex get _index => session.index;

  RecordPlan plan() {
    for (final record in _index.docs) {
      if (record.docTypeId != recordType.id) continue;
      final feature = _index.parentOf(record);
      if (feature == null) continue;
      _planSource(record, feature);
      _planRows(record, feature);
    }
    final creates = <CreateStep>[];
    for (final arrival in _arrivals.values) {
      if (_land(arrival) case final step?) creates.add(step);
    }
    return RecordPlan(edits: _edits, creates: creates);
  }

  /// Plans the in-place renames and the departures of [record], the record of
  /// [feature], and notes the lines that arrive elsewhere.
  void _planSource(IndexedDoc record, IndexedDoc feature) {
    final _RecordItemMoves(:inPlace, :leaving) = _itemMovesOf(
      _index,
      feature,
      renamed,
    );
    if (inPlace.isEmpty && leaving.isEmpty) return;
    _edits[record.docPath] = (text) => readRecord(
      record.docPath,
      () => rewriteRecordItems(
        text,
        recordType,
        (item) => leaving.containsKey(item) ? null : inPlace[item] ?? item,
      ),
    );
    final bytes = leaving.isEmpty ? null : session.readDocBytes(record.docPath);
    if (bytes == null) return;
    final lfText = toLf(utf8.decode(bytes));
    final landings = {
      for (final move in leaving.values) move.feature.docPath: move.feature,
    };
    for (final MapEntry(key: path, value: landing) in landings.entries) {
      final lines = readRecord(
        record.docPath,
        () => recordLinesCarried(lfText, recordType, (item) {
          final move = leaving[item];
          return move != null && move.feature.docPath == path
              ? move.name
              : null;
        }),
      );
      if (lines.isEmpty) continue;
      final key = _ArrivalKey(featurePath: path, target: record.target);
      _arrivals
          .putIfAbsent(key, () => _Arrival(landing, record.target))
          .take(lines);
    }
  }

  /// Plans the matrix rows of [record], the record of [feature], that name a
  /// moved edge case, and notes the rows that arrive in another feature's
  /// record.
  void _planRows(IndexedDoc record, IndexedDoc feature) {
    final moves = rowMoves[feature.docPath];
    final bytes = moves == null ? null : session.readDocBytes(record.docPath);
    if (moves == null || bytes == null) return;
    final changes = _rowChangesOf(
      toLf(utf8.decode(bytes)),
      recordType,
      moves,
      feature,
    );
    if (changes.isEmpty) return;
    final prior = _edits[record.docPath];
    _edits[record.docPath] = (text) {
      final earlier = prior?.call(text);
      final current = earlier ?? text;
      final rewritten = _withRowChanges(
        current,
        _rowChangesOf(current, recordType, moves, feature),
      );
      return rewritten == current ? earlier : rewritten;
    };
    for (final leaving in changes.leaving.values) {
      final key = _ArrivalKey(
        featurePath: leaving.feature.docPath,
        target: record.target,
      );
      _arrivals
          .putIfAbsent(key, () => _Arrival(leaving.feature, record.target))
          .take(RecordLines(rows: [leaving.row]));
    }
  }

  /// Adds the lines of [arrival] to the record that holds them, or returns the
  /// step that creates it.
  ///
  /// The session's index is a snapshot, so a record path it lacks is read on
  /// disk: a record there takes the lines as an indexed one does.
  CreateStep? _land(_Arrival arrival) {
    final lines = RecordLines(
      statuses: arrival.statuses,
      code: arrival.code,
      tests: arrival.tests,
      rows: arrival.rows,
    );
    final held = _index
        .ofTypeNamed(recordType.id, arrival.feature.name)
        .where((record) => record.target == arrival.target)
        .firstOrNull;
    if (held != null) {
      _addTo(held.docPath, lines);
      return null;
    }
    final record = _newRecordFor(session, recordType, arrival, lines);
    if (session.readDocBytes(record.docPath) == null) {
      session.requireWritable(record.docPath);
      return CreateStep(session.projectPathOf(record.docPath), record.text);
    }
    _requireRecordAt(record.docPath);
    _addTo(record.docPath, lines);
    return null;
  }

  /// Plans the arrival of [lines] after the edit already planned for the record
  /// at [docPath], so a record that renames and gains entries does both.
  void _addTo(String docPath, RecordLines lines) {
    final prior = _edits[docPath];
    _edits[docPath] = (text) {
      final renamed = prior?.call(text);
      final added = readRecord(
        docPath,
        () => addRecordLines(renamed ?? text, recordType, lines),
      );
      return added ?? renamed;
    };
  }

  /// Throws [RenderFault] `output_not_writable` unless the matcher reads the
  /// file at [docPath], which the snapshot did not index, as a record.
  void _requireRecordAt(String docPath) {
    if (session.docTypeAt(docPath)?.id == recordType.id) return;
    throw RenderFault(
      RenderFaultCode.outputNotWritable,
      'cannot write $docPath: it is no ${recordType.id} doc',
    );
  }
}

/// Returns what [read] returns from the record at [docPath].
///
/// Throws [RenderFault] `output_not_writable` naming the record when a field
/// block [read] needs is not valid YAML, so the write refuses before the
/// journal rather than drop a line it cannot place.
T readRecord<T>(String docPath, T Function() read) {
  try {
    return read();
  } on RecordFieldUnreadable catch (error) {
    throw RenderFault(
      RenderFaultCode.outputNotWritable,
      'cannot write $docPath: its ${error.field} block is not valid YAML',
    );
  }
}

/// Returns, for the items of [feature]'s record, the new relative name of each
/// that stays in [feature] under another name, and the landing of each that
/// leaves it; keyed by the item's name now.
///
/// An item stays when its new name puts it in [feature] itself, so one that
/// moves into a sub-feature of [feature] leaves.
_RecordItemMoves _itemMovesOf(
  DocIndex index,
  IndexedDoc feature,
  RenamedNames renamed,
) {
  final inPlace = <String, String>{};
  final leaving = <String, _Landing>{};
  final featureName = _nameAfter(feature, renamed);
  for (final MapEntry(key: item, value: doc) in recordItemsOf(
    feature,
    index.childrenOf,
  ).entries) {
    final name = _nameAfter(doc, renamed);
    if (_featureNameOf(doc, renamed) == featureName) {
      final relative = name.substring(featureName.length + 1);
      if (relative != item) inPlace[item] = relative;
    } else if (_landingOf(index, doc, renamed) case final landing?) {
      leaving[item] = landing;
    }
  }
  return _RecordItemMoves(inPlace: inPlace, leaving: leaving);
}

String _nameAfter(IndexedDoc doc, RenamedNames renamed) =>
    renamed.newNameOf(doc.docTypeId, doc.name) ?? doc.name;

/// Returns where [item], a story or an FR, lands: the feature its new name
/// puts it in and its name relative to that feature; null when that feature
/// is not indexed.
///
/// An FR's story is its new name less the last segment, so an FR moved to
/// another story lands where that story is.
_Landing? _landingOf(DocIndex index, IndexedDoc item, RenamedNames renamed) {
  final featureName = _featureNameOf(item, renamed);
  if (featureName == null) return null;
  final feature = index.ofTypeNamed(featureType, featureName).firstOrNull;
  if (feature == null) return null;
  final name = _nameAfter(item, renamed);
  return _Landing(
    feature: feature,
    name: name.substring(featureName.length + 1),
  );
}

/// Returns the name of the feature [item]'s new name puts it in; null when the
/// name has no feature segment.
String? _featureNameOf(IndexedDoc item, RenamedNames renamed) {
  final name = _nameAfter(item, renamed);
  final storyName = item.docTypeId == storyType ? name : _parentName(name);
  return storyName == null ? null : _parentName(storyName);
}

String? _parentName(String name) {
  final cut = name.lastIndexOf('/');
  return cut < 0 ? null : name.substring(0, cut);
}

/// Returns the DocPath and text of the record [arrival] needs, as a draft with
/// [lines] in it.
///
/// A path the project reads in a target's folder only with two or more
/// targets, as the doc type matcher reads it. Throws [IndexFault]
/// `argument_invalid` when the record doc type has no path of its own for the
/// feature, as `new` does, so the lines never leave the old record unplaced.
NewRecord _newRecordFor(
  WriteSession session,
  MergedDocType recordType,
  _Arrival arrival,
  RecordLines lines,
) {
  final set = session.index.set;
  final featureType = session.index.typeOf(arrival.feature);
  final record = featureType == null
      ? null
      : newRecordOf(
          set,
          recordType,
          featureType: featureType,
          featureDocPath: arrival.feature.docPath,
          featureName: arrival.feature.name,
          lines: lines,
          target: session.index.hasTwins ? arrival.target : null,
        );
  if (record == null) {
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      '${recordType.id} has no path to create a record at for '
      '${arrival.feature.name}',
    );
  }
  return record;
}

/// Returns the DocPath and laid-out text of the draft record of the feature at
/// [featureDocPath] holding [lines]; null when [recordType] has no path of its
/// own for the feature.
///
/// The one builder of a new record, for a move or rename and for a migration.
/// [target] reads the path in that code target's folder.
NewRecord? newRecordOf(
  MergedSet set,
  MergedDocType recordType, {
  required MergedDocType featureType,
  required String featureDocPath,
  required String featureName,
  required RecordLines lines,
  String? target,
}) {
  final featureShape = DocPathShape.ofDoc(featureType, set, featureDocPath);
  final values = featureShape?.valuesOf(featureDocPath);
  final shape = featureShape == null
      ? null
      : DocPathShape.of(
          recordType,
          set,
          depth: featureShape.depth,
          target: target,
        );
  if (values == null || shape == null || !isSpecDocShape(shape)) return null;
  final skeleton = skeletonOf(recordType, featureName.split('/').last);
  final text = addRecordLines(skeleton, recordType, lines) ?? skeleton;
  return NewRecord(
    docPath: shape.build(values),
    text: layOutDoc(text, recordType),
  );
}
