import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/doc_lines.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/record_entries.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// The item a leading `:` names: the record's feature itself.
const _featureItem = '';

/// Returns the findings of a record doc's `statuses` and `implements` lines
/// (`consistency_check/find_prd_spec_disagreements/check_record_entries`).
///
/// Every line gives at most one finding, the first its behavior order reaches,
/// so no other rule reports a line this one does. A doc that is no record,
/// whose frontmatter is invalid, or whose feature is missing has none.
Iterable<Finding> checkRecordEntries(
  CheckContext context,
  IndexedDoc record,
) sync* {
  final type = context.set.recordDocType;
  if (type == null || record.docTypeId != type.id) return;
  final feature = context.index.parentOf(record);
  if (feature == null || feature.docTypeId != featureType) return;
  final lines = context.linesOf(record);
  if (lines.frontmatterErrorLine != null) return;
  yield* _RecordWalk(context, record, feature, type, lines).findings();
}

/// One record read line by line against its feature tree.
final class _RecordWalk {
  new(this._context, this._record, this._feature, this._type, this._lines)
    : _statusFieldId = _fieldIdOf(
        _type,
        (f) => f.type == FieldType.recordStatus,
      ),
      _codeFieldId = _fieldIdOf(
        _type,
        (f) =>
            f.type == FieldType.outputRef && f.pointer == PointerKind.itemExact,
      ),
      _entries = {
        for (final entry in recordEntriesOf(_record, _type)) entry.item: entry,
      },
      _items = _itemsOf(_context, _feature);

  final CheckContext _context;
  final MergedDocType _type;
  final IndexedDoc _record;
  final IndexedDoc _feature;
  final DocLines _lines;
  final String? _statusFieldId;
  final String? _codeFieldId;
  final Map<String, RecordEntry> _entries;

  /// The items the record may name: the feature itself, its stories, and
  /// their FRs, each relative to the feature.
  final Set<String> _items;

  Iterable<Finding> findings() sync* {
    yield* _statusFindings();
    yield* _codeFindings();
  }

  Iterable<Finding> _statusFindings() sync* {
    final fieldId = _statusFieldId;
    if (fieldId == null) return;
    final seen = <String>{};
    for (final (:value, :line, text: _) in _lines.entriesOf(fieldId)) {
      if (value is! String) continue;
      final parsed = recordStatusLineOf(value);
      final item = parsed?.item ?? value;
      if (parsed == null || !_items.contains(item)) {
        yield _unresolved(item, line);
      } else if (!seen.add(item)) {
        yield _finding(
          FindingKind.recordEntryDuplicate,
          line,
          '${_nameOf(item)} has a second statuses line',
          {'entry': _nameOf(item)},
        );
      } else if (parsed.status == RecordStatus.skipped) {
        if ((parsed.reason ?? '').trim().isEmpty) {
          yield _finding(
            FindingKind.skipReasonMissing,
            line,
            '${_nameOf(item)} is skipped and gives no reason',
            {'entry': _nameOf(item)},
          );
        }
      } else {
        yield* _asNonSkipped(item, line, itemHoldsStatus: true);
      }
    }
  }

  Iterable<Finding> _codeFindings() sync* {
    final fieldId = _codeFieldId;
    if (fieldId == null) return;
    for (final (:value, :line, text: _) in _lines.entriesOf(fieldId)) {
      if (value is! String) continue;
      final parsed = recordCodeLineOf(value);
      final item = parsed?.item ?? value;
      if (parsed == null || !_items.contains(item)) {
        yield _unresolved(item, line);
      } else if (_entries[item]?.status == RecordStatus.skipped) {
        yield _finding(
          FindingKind.skipWithCode,
          line,
          '${_nameOf(item)} is skipped but names a code path',
          {'entry': _nameOf(item)},
        );
      } else {
        yield* _asNonSkipped(item, line, itemHoldsStatus: false);
      }
    }
  }

  /// A line of an item that is not skipped: the feature's own entry is
  /// written only to skip it, and any other item sits under no skip.
  Iterable<Finding> _asNonSkipped(
    String item,
    int line, {
    required bool itemHoldsStatus,
  }) sync* {
    if (item == _featureItem) {
      yield _finding(
        FindingKind.featureStatusWritten,
        line,
        itemHoldsStatus
            ? 'a feature takes its status from its stories; its entry takes '
                  'skipped only'
            : 'the feature entry is written only to skip it; it takes no '
                  'code path',
      );
      return;
    }
    final skip = _skipAbove(item);
    if (skip == null) return;
    yield _finding(
      FindingKind.entryUnderSkip,
      line,
      '${_nameOf(item)} sits under the skip of $skip',
      {'entry': _nameOf(item), 'skip': skip},
    );
  }

  /// Returns the name of the entry whose skip covers [item], the narrowest
  /// first, or null when none does.
  ///
  /// The record's own skips come first, then a skipped feature entry in the
  /// record of each feature above, in the same code target.
  String? _skipAbove(String item) {
    final own = [
      for (final entry in _entries.values)
        if (entry.status == RecordStatus.skipped &&
            entry.item != item &&
            _covers(entry.item, item))
          entry.item,
    ]..sort((a, b) => b.length.compareTo(a.length));
    if (own.isNotEmpty) return _nameOf(own.first);
    return _ancestorSkip();
  }

  String? _ancestorSkip() {
    final index = _context.index;
    for (final feature in index.chainOf(_feature).skip(1)) {
      if (feature.docTypeId != featureType) continue;
      for (final record in index.ofTypeNamed(_type.id, feature.name)) {
        if (record.target != _record.target) continue;
        if (_skipsFeature(record)) return feature.name;
      }
    }
    return null;
  }

  bool _skipsFeature(IndexedDoc record) {
    return recordEntriesOf(record, _type).any(
      (entry) =>
          entry.item == _featureItem && entry.status == RecordStatus.skipped,
    );
  }

  Finding _unresolved(String entry, int line) => _finding(
    FindingKind.recordEntryUnresolved,
    line,
    '$entry names neither ${_feature.name} nor a story or FR of it',
    {'entry': entry},
  );

  Finding _finding(
    FindingKind kind,
    int line,
    String message, [
    Map<String, Object> keys = const {},
  ]) =>
      _context.finding(_record, kind, line: line, message: message, keys: keys);

  /// The name an entry carries: its item, or the feature's name for the
  /// feature itself.
  String _nameOf(String item) => item == _featureItem ? _feature.name : item;
}

String? _fieldIdOf(MergedDocType type, bool Function(MergedField) test) =>
    type.fields.where(test).firstOrNull?.id;

/// Returns the items a record of [feature] names: the feature itself, each
/// story under it, and each FR of those stories, relative to the feature.
Set<String> _itemsOf(CheckContext context, IndexedDoc feature) {
  final index = context.index;
  final prefix = '${feature.name}/';
  String relative(IndexedDoc doc) => doc.name.startsWith(prefix)
      ? doc.name.substring(prefix.length)
      : doc.name;
  return {
    _featureItem,
    for (final story in index.childrenOf(feature))
      if (story.docTypeId == storyType) ...[
        relative(story),
        for (final fr in index.childrenOf(story))
          if (fr.docTypeId == frType) relative(fr),
      ],
  };
}

/// Whether the skipped entry [skipped] covers [item]: the feature itself, or a
/// story above an FR.
bool _covers(String skipped, String item) =>
    skipped == _featureItem || item.startsWith('$skipped/');
