import 'dart:convert';

import 'package:specstone_core/src/doc_model/doc_path_shape.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/new_doc.dart'
    show skeletonOf;
import 'package:specstone_core/src/document_writing/rewrite_refs.dart'
    show TextEdit;
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/record_entries.dart';
import 'package:specstone_core/src/rendering/formatter.dart' show layOutDoc;
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// What a rename or a move does to the record entries of every code target:
/// the edit of each record that renames or loses entries or gains some, by
/// its DocPath before the moves, and the record it creates, as a draft, for
/// entries that land where no record is.
typedef RecordPlan = ({Map<String, TextEdit> edits, List<CreateStep> creates});

/// Where a story or FR entry goes: the feature whose record takes it, and its
/// name relative to that feature.
typedef _Landing = ({IndexedDoc feature, String name});

/// The entries bound for one feature's record in one target.
final class _Arrival {
  new(this.feature, this.target);

  final IndexedDoc feature;
  final String? target;
  final statuses = <String>[];
  final code = <String>[];

  void take(RecordLines lines) {
    statuses.addAll(lines.statuses);
    code.addAll(lines.code);
  }
}

/// Returns the record edits and the new records that follow [renamed], the
/// names that change, mapped from `(doc type id, old name)` to the new name.
///
/// An entry names its item relative to its record's feature, so it changes
/// only when the item's name changes inside that feature: the entry is
/// renamed in place. An item that left the feature moves its lines, as
/// written but for the item, to the record of the feature it landed in, in
/// the same target, and the line leaves the old record; a target whose old
/// record holds no line of it changes nothing, and a landing feature with no
/// record in that target gets one, as a draft, holding the lines. The feature
/// itself keeps its own entry.
RecordPlan planRecordRewrites(
  WriteSession session,
  Map<(String, String), String> renamed,
) {
  final recordType = session.index.set.recordDocType;
  if (recordType == null || renamed.isEmpty) {
    return (edits: const {}, creates: const []);
  }
  return _Planner(session, recordType, renamed).plan();
}

/// Plans the entries of every record of one rename or move.
final class _Planner {
  new(this.session, this.recordType, this.renamed);

  final WriteSession session;
  final MergedDocType recordType;
  final Map<(String, String), String> renamed;
  final _edits = <String, TextEdit>{};
  final _arrivals = <(String, String?), _Arrival>{};

  DocIndex get _index => session.index;

  RecordPlan plan() {
    for (final record in _index.docs) {
      if (record.docTypeId != recordType.id) continue;
      final feature = _index.parentOf(record);
      if (feature != null) _planSource(record, feature);
    }
    final creates = <CreateStep>[];
    for (final arrival in _arrivals.values) {
      if (_land(arrival) case final step?) creates.add(step);
    }
    return (edits: _edits, creates: creates);
  }

  /// Plans the in-place renames and the departures of [record], the record of
  /// [feature], and notes the lines that arrive elsewhere.
  void _planSource(IndexedDoc record, IndexedDoc feature) {
    final (:inPlace, :leaving) = _itemMovesOf(_index, feature, renamed);
    if (inPlace.isEmpty && leaving.isEmpty) return;
    _edits[record.docPath] = (text) => rewriteRecordItems(
      text,
      recordType,
      (item) => leaving.containsKey(item) ? null : inPlace[item] ?? item,
    );
    final bytes = leaving.isEmpty ? null : session.readDocBytes(record.docPath);
    if (bytes == null) return;
    final lfText = toLf(utf8.decode(bytes));
    final landings = {
      for (final move in leaving.values) move.feature.docPath: move.feature,
    };
    for (final MapEntry(key: path, value: landing) in landings.entries) {
      final lines = recordLinesCarried(lfText, recordType, (item) {
        final move = leaving[item];
        return move != null && move.feature.docPath == path ? move.name : null;
      });
      if (lines.statuses.isEmpty && lines.code.isEmpty) continue;
      final key = (path, record.target);
      _arrivals
          .putIfAbsent(key, () => _Arrival(landing, record.target))
          .take(lines);
    }
  }

  /// Adds the lines of [arrival] to the record that holds them, or returns the
  /// step that creates it.
  CreateStep? _land(_Arrival arrival) {
    final lines = (statuses: arrival.statuses, code: arrival.code);
    final held = _index
        .ofTypeNamed(recordType.id, arrival.feature.name)
        .where((record) => record.target == arrival.target)
        .firstOrNull;
    if (held == null) {
      return _createdRecord(session, recordType, arrival, lines);
    }
    _edits[held.docPath] = (text) => addRecordLines(text, recordType, lines);
    return null;
  }
}

/// Returns, for the items of [feature]'s record, the new relative name of each
/// that stays in [feature] under another name, and the landing of each that
/// leaves it; keyed by the item's name now.
({Map<String, String> inPlace, Map<String, _Landing> leaving}) _itemMovesOf(
  DocIndex index,
  IndexedDoc feature,
  Map<(String, String), String> renamed,
) {
  final inPlace = <String, String>{};
  final leaving = <String, _Landing>{};
  final featurePrefix = '${_nameAfter(feature, renamed)}/';
  for (final MapEntry(key: item, value: doc) in recordItemsOf(
    feature,
    index.childrenOf,
  ).entries) {
    final name = _nameAfter(doc, renamed);
    if (name.startsWith(featurePrefix)) {
      final relative = name.substring(featurePrefix.length);
      if (relative != item) inPlace[item] = relative;
    } else if (_landingOf(index, doc, renamed) case final landing?) {
      leaving[item] = landing;
    }
  }
  return (inPlace: inPlace, leaving: leaving);
}

String _nameAfter(IndexedDoc doc, Map<(String, String), String> renamed) =>
    renamed[(doc.docTypeId, doc.name)] ?? doc.name;

/// Returns where [item], a story or an FR, lands: the feature its story sits
/// in after the moves and its name relative to that feature; null when that
/// feature is not indexed.
_Landing? _landingOf(
  DocIndex index,
  IndexedDoc item,
  Map<(String, String), String> renamed,
) {
  final story = item.docTypeId == storyType ? item : index.parentOf(item);
  if (story == null) return null;
  final storyName = _nameAfter(story, renamed);
  final cut = storyName.lastIndexOf('/');
  if (cut < 0) return null;
  final featureName = storyName.substring(0, cut);
  final name = _nameAfter(item, renamed);
  final feature = index.ofTypeNamed(featureType, featureName).firstOrNull;
  if (feature == null || !name.startsWith('$featureName/')) return null;
  return (feature: feature, name: name.substring(featureName.length + 1));
}

/// Returns the step that creates the record [arrival] needs, as a draft with
/// [lines] in it.
///
/// A path the project reads in a target's folder only with two or more
/// targets, as the doc type matcher reads it. Throws [IndexFault]
/// `argument_invalid` when the record doc type has no path of its own for the
/// feature, as `new` does, so the lines never leave the old record unplaced.
CreateStep _createdRecord(
  WriteSession session,
  MergedDocType recordType,
  _Arrival arrival,
  RecordLines lines,
) {
  final set = session.index.set;
  final featureType = session.index.typeOf(arrival.feature);
  final featureShape = featureType == null
      ? null
      : DocPathShape.ofDoc(featureType, set, arrival.feature.docPath);
  final values = featureShape?.valuesOf(arrival.feature.docPath);
  final twins = session.index.targetNames.length > 1;
  final shape = featureShape == null
      ? null
      : DocPathShape.of(
          recordType,
          set,
          depth: featureShape.depth,
          target: twins ? arrival.target : null,
        );
  if (values == null || shape == null || !isSpecDocShape(shape)) {
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      '${recordType.id} has no path to create a record at for '
      '${arrival.feature.name}',
    );
  }
  final docPath = shape.build(values);
  session.requireWritable(docPath);
  final skeleton = skeletonOf(recordType, arrival.feature.name.split('/').last);
  final text = addRecordLines(skeleton, recordType, lines) ?? skeleton;
  return CreateStep(
    session.projectPathOf(docPath),
    layOutDoc(text, recordType),
  );
}
