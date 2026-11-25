import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/matrix_form.dart';
import 'package:specstone_core/src/consistency_check/models/doc_lines.dart';
import 'package:specstone_core/src/consistency_check/models/yaml_entry.dart';
import 'package:specstone_core/src/consistency_check/record_doc.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/models/matrix_line.dart';
import 'package:specstone_core/src/index_query/record_entries.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/models/record_status.dart';

/// The item a leading `:` names: the record's feature itself.
const _featureItem = '';

/// Returns the findings of a record doc's `statuses`, `implements`, and
/// `tests` lines and its Verification matrix rows.
///
/// Every line and row gives at most one finding, the first its behavior order
/// reaches, so no other rule reports a line this one does. A row is read as a
/// `tests` line of its item, except a row naming a story, which the matrix
/// rule reports, and a refused-form row, which gets the form finding alone. A
/// doc that is no record, whose frontmatter is invalid, or whose feature is
/// missing has none.
Iterable<Finding> checkRecordEntries(
  CheckContext context,
  IndexedDoc record,
) sync* {
  final read = recordDocOf(context, record);
  if (read == null) return;
  yield* _RecordWalk(
    context,
    record,
    read.feature,
    read.type,
    read.lines,
  ).findings();
}

/// One record read line by line against its feature tree.
final class _RecordWalk {
  new(
    this._context,
    this._record,
    this._feature,
    MergedDocType type,
    this._lines,
  ) : _statusFieldId = recordStatusFieldOf(type)?.id,
      _codeFields = [
        _CodeField(id: recordCodeFieldOf(type)?.id, noun: 'code path'),
        _CodeField(id: recordTestFieldOf(type)?.id, noun: 'test'),
      ],
      _entries = {
        for (final entry in recordEntriesOf(_record, type)) entry.item: entry,
      },
      _docs = {
        _featureItem: null,
        ...recordItemsOf(_feature, _context.index.childrenOf),
      };

  final CheckContext _context;
  final IndexedDoc _record;
  final IndexedDoc _feature;
  final DocLines _lines;
  final String? _statusFieldId;
  final List<_CodeField> _codeFields;
  final Map<String, RecordEntry> _entries;

  /// The items the record may name, each relative to the feature: the
  /// feature itself (no doc), its stories, and their FRs.
  final Map<String, IndexedDoc?> _docs;

  Iterable<Finding> findings() sync* {
    yield* _statusFindings();
    yield* _codeFindings();
    yield* _missingFindings();
  }

  /// One finding per story or FR with no `statuses` line and no skip over it,
  /// at the `statuses` key line, or line 1 when the record has no such key.
  Iterable<Finding> _missingFindings() sync* {
    final fieldId = _statusFieldId;
    if (fieldId == null) return;
    final named = {
      for (final line in statusLinesOf(_lines, fieldId)) line.item,
    };
    final keyLine = _lines.keyLine(fieldId) ?? 1;
    final target = _record.target;
    final where = target == null ? '' : ' in $target';
    for (final MapEntry(key: item, value: doc) in _docs.entries) {
      if (doc == null || named.contains(item) || _skipAbove(item) != null) {
        continue;
      }
      yield _finding(
        FindingKind.recordEntryMissing,
        keyLine,
        '$item has no statuses line$where; write its status',
        {'entry': item, 'target': ?target},
      );
    }
  }

  Iterable<Finding> _statusFindings() sync* {
    final fieldId = _statusFieldId;
    if (fieldId == null) return;
    final seen = <String>{};
    for (final entry in statusLinesOf(_lines, fieldId)) {
      final line = entry.line;
      final item = entry.item ?? entry.text;
      if (entry.item == null || !_docs.containsKey(item)) {
        yield _unresolved(item, line);
      } else if (!seen.add(item)) {
        yield _finding(
          FindingKind.recordEntryDuplicate,
          line,
          '${_nameOf(item)} has a second statuses line',
          {'entry': _nameOf(item)},
        );
      } else if (entry.status == RecordStatus.skipped) {
        if ((entry.reason ?? '').trim().isEmpty) {
          yield _finding(
            FindingKind.skipReasonMissing,
            line,
            '${_nameOf(item)} is skipped and gives no reason',
            {'entry': _nameOf(item)},
          );
        }
      } else {
        yield* _asNonSkipped(item, line);
      }
    }
  }

  Iterable<Finding> _codeFindings() sync* {
    for (final _CodeField(:id, :noun) in _codeFields) {
      if (id != null) yield* _lineFindings(id, noun);
    }
    for (final row in _record.matrixLines.whereType<MatrixRow>()) {
      // A refused-form row and a row naming a story are the matrix rule's
      // alone.
      if (isRefusedFormRow(_context, _record, row)) continue;
      final doc = _docs[row.item];
      if (doc != null && doc.docTypeId != frType) continue;
      yield* _itemFindings(row.item, row.line, 'matrix row');
    }
  }

  Iterable<Finding> _lineFindings(String fieldId, String noun) sync* {
    for (final YamlEntry(:value, :line) in _lines.entriesOf(fieldId)) {
      if (value is! String) continue;
      final parsed = recordCodeLineOf(value);
      if (parsed == null) {
        yield _unresolved(value, line);
      } else {
        yield* _itemFindings(parsed.item, line, noun);
      }
    }
  }

  /// The finding of a code, test, or matrix line of [item]; [noun] names what
  /// the line holds.
  Iterable<Finding> _itemFindings(String item, int line, String noun) sync* {
    if (!_docs.containsKey(item)) {
      yield _unresolved(item, line);
    } else if (_entries[item]?.status == RecordStatus.skipped) {
      yield _finding(
        FindingKind.skipWithCode,
        line,
        '${_nameOf(item)} is skipped but names a $noun',
        {'entry': _nameOf(item)},
      );
    } else {
      yield* _asNonSkipped(item, line, noun: noun);
    }
  }

  /// A line of an item that is not skipped: the feature's own entry is
  /// written only to skip it, and any other item sits under no skip.
  ///
  /// [noun] names what a code line holds; null for a `statuses` line.
  Iterable<Finding> _asNonSkipped(String item, int line, {String? noun}) sync* {
    if (item == _featureItem) {
      yield _finding(
        FindingKind.featureStatusWritten,
        line,
        noun == null
            ? 'a feature takes its status from its stories; its entry takes '
                  'skipped only'
            : 'the feature entry is written only to skip it; it takes no '
                  '$noun',
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

  String? _skipAbove(String item) =>
      _context.index.coveringSkipOf(_docs[item]!, codeTarget: _record.target);

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

/// A record's code-path field, null when its type has none, and the noun a
/// finding names its lines by.
final class _CodeField {
  const new({required this.id, required this.noun});

  final String? id;
  final String noun;
}
