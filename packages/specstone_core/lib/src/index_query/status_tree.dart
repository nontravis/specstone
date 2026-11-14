import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/record_entries.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_set.dart';

/// The entry item that names the record's own feature (a skip).
const _featureItem = '';

/// The record doc of one feature in one target: the feature's name, the one
/// the record's entry items are relative to, and its parsed entries.
typedef _RecordDoc = ({String feature, List<RecordEntry> entries});

/// The docs of one snapshot as a parent tree, with each story's, FR's, and
/// feature's status in each code target, read from no store.
///
/// The index serves it, and the migrate stamp builds one over the texts of a
/// run, so both read one status rule.
final class StatusTree {
  /// Reads [docs], each nested under its `parentPath`, or under the one
  /// [parents] gives it when [parents] is not null.
  ///
  /// - [targetNames]: the config's target names in config order; empty with
  ///   one unnamed target.
  new(
    this.set,
    this.docs, {
    List<String> targetNames = const [],
    Map<String, String>? parents,
  }) : targetNames = List.unmodifiable(targetNames),
       _byPath = {for (final doc in docs) doc.docPath: doc},
       _parents =
           parents ?? {for (final doc in docs) doc.docPath: ?doc.parentPath},
       _byTypeAndName = _groupBy(docs, (doc) => '${doc.docTypeId}:${doc.name}');

  /// The merged doc types of the project.
  final MergedSet set;

  /// Every doc in tree order.
  final List<IndexedDoc> docs;

  /// The config's target names, in config order; empty with one unnamed
  /// target.
  final List<String> targetNames;

  final Map<String, IndexedDoc> _byPath;
  final Map<String, String> _parents;
  final Map<String, List<IndexedDoc>> _byTypeAndName;
  late final Map<String, List<IndexedDoc>> _children = () {
    final children = <String, List<IndexedDoc>>{};
    for (final doc in docs) {
      if (_parents[doc.docPath] case final parent?) {
        (children[parent] ??= []).add(doc);
      }
    }
    return {
      for (final MapEntry(:key, :value) in children.entries)
        key: List<IndexedDoc>.unmodifiable(value),
    };
  }();

  /// The record entries of each record doc, keyed by its docPath; built on
  /// first read.
  late final Map<String, List<RecordEntry>> _recordEntries = {
    if (set.recordDocType case final type?)
      for (final record in docs)
        if (record.docTypeId == type.id)
          record.docPath: recordEntriesOf(record, type),
  };

  /// Returns the doc at [docPath], or null when none is indexed there.
  IndexedDoc? at(String docPath) => _byPath[docPath];

  /// Returns the docs of the doc type [typeId] named [name], in tree order.
  List<IndexedDoc> ofTypeNamed(String typeId, String name) =>
      _byTypeAndName['$typeId:$name'] ?? const [];

  /// Returns the doc [doc] nests under, or null for a root doc.
  IndexedDoc? parentOf(IndexedDoc doc) {
    final parentPath = _parents[doc.docPath];
    return parentPath == null ? null : _byPath[parentPath];
  }

  /// Returns the docs that nest directly under [doc].
  List<IndexedDoc> childrenOf(IndexedDoc doc) =>
      _children[doc.docPath] ?? const [];

  /// Returns [doc] followed by every doc nested under it, parents first.
  List<IndexedDoc> subtreeOf(IndexedDoc doc) => [
    doc,
    for (final child in childrenOf(doc)) ...subtreeOf(child),
  ];

  /// Returns the status of [doc] in [codeTarget], or in its one target when
  /// null: the one `targets:` names when it names one, else the unnamed
  /// target.
  ///
  /// A feature computes it from its subtree's stories (INV-17); a story or FR
  /// takes its record entry's status, or `planned` without one, outside every
  /// skip that covers it (INV-29); any other doc returns the status it writes,
  /// or null. With no record doc type every story and FR reads its `status:`
  /// with no target, and a feature computes from those (INV-29).
  String? statusOf(IndexedDoc doc, {String? codeTarget}) {
    final typeId = doc.docTypeId;
    if (typeId == featureType) return _featureStatusOf(doc, codeTarget).wire;
    if (typeId != storyType && typeId != frType) return doc.writtenStatus;
    if (set.recordDocType == null) return doc.writtenStatus;
    return itemStatus(doc, codeTarget: codeTarget).wire;
  }

  /// Returns the status of the story or FR [item] in [codeTarget] (INV-29):
  /// `skipped` under a skip of its feature, of a feature above, or, for an FR,
  /// of its story; else its record entry's `statuses` status, `planned`
  /// without an entry or a status.
  RecordStatus itemStatus(IndexedDoc item, {String? codeTarget}) {
    final target = _namedOrGiven(codeTarget);
    if (_coveringSkip(item, target, includingOwn: true) != null) {
      return RecordStatus.skipped;
    }
    return _entryOf(item, target)?.status ?? RecordStatus.planned;
  }

  /// Returns the name of the skip that covers the story or FR [item] in
  /// [codeTarget] apart from its own entry (INV-29), or null when none does.
  ///
  /// The narrowest skip wins, and the record nearest [item] first; a skipped
  /// feature entry is named by its feature.
  String? coveringSkipOf(IndexedDoc item, {String? codeTarget}) =>
      _coveringSkip(item, _namedOrGiven(codeTarget), includingOwn: false);

  String? _coveringSkip(
    IndexedDoc item,
    String? codeTarget, {
    required bool includingOwn,
  }) {
    for (final record in _recordsOf(item, codeTarget)) {
      final relative = _relativeItemOf(item, record);
      final covering = [
        for (final entry in record.entries)
          if (entry.status == RecordStatus.skipped &&
              (includingOwn || entry.item != relative) &&
              _skipCovers(entry.item, relative))
            entry.item,
      ]..sort((a, b) => b.length.compareTo(a.length));
      if (covering.isEmpty) continue;
      return covering.first.isEmpty ? record.feature : covering.first;
    }
    return null;
  }

  /// Returns the record entry of the story or FR [item] in [codeTarget], or
  /// in its one target when null (as [statusOf] reads it); null with no
  /// entry, and with no record doc type.
  RecordEntry? recordEntryOf(IndexedDoc item, {String? codeTarget}) =>
      _entryOf(item, _namedOrGiven(codeTarget));

  /// Returns the entry of [item] in its own feature's record in [codeTarget],
  /// the one record `check` resolves it in; a record above names none of it.
  RecordEntry? _entryOf(IndexedDoc item, String? codeTarget) {
    final feature = _featureOf(item)?.name;
    for (final record in _recordsOf(item, codeTarget)) {
      if (record.feature != feature) continue;
      final relative = _relativeItemOf(item, record);
      for (final entry in record.entries) {
        if (entry.item == relative) return entry;
      }
    }
    return null;
  }

  /// Returns the nearest feature at or above [doc], or null for none.
  IndexedDoc? _featureOf(IndexedDoc doc) {
    for (IndexedDoc? member = doc; member != null; member = parentOf(member)) {
      if (member.docTypeId == featureType) return member;
    }
    return null;
  }

  /// Returns the feature [doc]'s status in [codeTarget] from the stories of
  /// its whole subtree (INV-17): `skipped` under its own skip or one above;
  /// `planned` with no story; `skipped` when every story is; `deprecated`
  /// when every story not skipped is; `implemented` when every story neither
  /// skipped nor deprecated is; `planned` otherwise.
  RecordStatus _featureStatusOf(IndexedDoc doc, String? codeTarget) {
    final records = _recordsOf(doc, _namedOrGiven(codeTarget));
    final skippedAbove = records.any(
      (record) => record.entries.any(
        (entry) =>
            entry.item == _featureItem && entry.status == RecordStatus.skipped,
      ),
    );
    if (skippedAbove) return RecordStatus.skipped;
    RecordStatus storyStatusOf(IndexedDoc story) => set.recordDocType == null
        ? RecordStatus.byWire(story.writtenStatus ?? '') ?? RecordStatus.planned
        : itemStatus(story, codeTarget: _namedOrGiven(codeTarget));
    final stories = [
      for (final member in subtreeOf(doc).skip(1))
        if (member.docTypeId == storyType) storyStatusOf(member),
    ];
    if (stories.isEmpty) return RecordStatus.planned;
    if (stories.every((s) => s == RecordStatus.skipped)) {
      return RecordStatus.skipped;
    }
    final left = stories.where((s) => s != RecordStatus.skipped);
    if (left.every((s) => s == RecordStatus.deprecated)) {
      return RecordStatus.deprecated;
    }
    final live = left.where((s) => s != RecordStatus.deprecated);
    return live.every((s) => s == RecordStatus.implemented)
        ? RecordStatus.implemented
        : RecordStatus.planned;
  }

  /// Returns [codeTarget], or the one name `targets:` holds when the project
  /// names exactly one code target and none was given.
  String? _namedOrGiven(String? codeTarget) =>
      codeTarget ?? (targetNames.length == 1 ? targetNames.single : null);

  /// The records of [doc]'s feature and of each feature above it in
  /// [codeTarget], nearest feature first.
  List<_RecordDoc> _recordsOf(IndexedDoc doc, String? codeTarget) {
    final type = set.recordDocType;
    if (type == null) return const [];
    final records = <_RecordDoc>[];
    for (IndexedDoc? member = doc; member != null; member = parentOf(member)) {
      if (member.docTypeId != featureType) continue;
      for (final record in ofTypeNamed(type.id, member.name)) {
        if (record.target != codeTarget) continue;
        records.add((
          feature: member.name,
          entries: _recordEntries[record.docPath] ?? const [],
        ));
      }
    }
    return records;
  }

  /// Returns [item]'s name relative to [record]'s feature: its own name with
  /// the feature's prefix dropped.
  String _relativeItemOf(IndexedDoc item, _RecordDoc record) {
    final prefix = '${record.feature}/';
    return item.name.startsWith(prefix)
        ? item.name.substring(prefix.length)
        : item.name;
  }

  /// Whether the skipped [entryItem] covers [relative]: the record's own
  /// feature, the item itself, or a story or feature above it.
  bool _skipCovers(String entryItem, String relative) =>
      entryItem.isEmpty ||
      entryItem == relative ||
      relative.startsWith('$entryItem/');
}

Map<String, List<IndexedDoc>> _groupBy(
  List<IndexedDoc> docs,
  String Function(IndexedDoc doc) key,
) {
  final groups = <String, List<IndexedDoc>>{};
  for (final doc in docs) {
    (groups[key(doc)] ??= []).add(doc);
  }
  return {
    for (final MapEntry(:key, :value) in groups.entries)
      key: List.unmodifiable(value),
  };
}
