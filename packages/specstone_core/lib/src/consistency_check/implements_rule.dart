import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/implements_entry.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/record_entries.dart';
import 'package:specstone_core/src/templates/code_target.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';

const _segmentMark = '.';
const _edge = r'[\p{L}\p{N}_]';

/// Returns the code path findings of a record [doc]; any other doc has none.
///
/// A path `path[:Symbol]` is resolved from the code root of the record's own
/// target when its item is neither `planned` nor `skipped`. A line naming no
/// item is `check_record_entries`'s, never reported here. A code file is read
/// only to resolve a Symbol (INV-11).
Iterable<Finding> checkImplements(CheckContext context, IndexedDoc doc) sync* {
  final type = context.set.recordDocType;
  if (type == null || doc.docTypeId != type.id) return;
  final feature = context.index.parentOf(doc);
  if (feature == null || feature.docTypeId != featureType) return;
  final lines = context.linesOf(doc);
  if (lines.frontmatterErrorLine != null) return;
  final fieldId = recordCodeFieldOf(type)?.id;
  final target = context.targets
      .where((target) => target.name == doc.target)
      .firstOrNull;
  if (fieldId == null || target == null) return;
  final items = recordItemsOf(feature, context.index.childrenOf);
  for (final (:value, :line, text: _) in lines.entriesOf(fieldId)) {
    if (value is! String) continue;
    final parsed = recordCodeLineOf(value);
    final item = items[parsed?.item];
    if (parsed == null || item == null) continue;
    if (!_isResolved(context, item, doc.target)) continue;
    yield* _resolve(context, doc, target, parsed.code, line);
  }
}

Iterable<Finding> _resolve(
  CheckContext context,
  IndexedDoc doc,
  CodeTarget target,
  String code,
  int line,
) sync* {
  final entry = ImplementsEntry(code);
  final path = entry.path;
  if (!entry.namesFileFrom(context.codeRootOf(target))) {
    yield context.finding(
      doc,
      FindingKind.implementsPathUnresolved,
      line: line,
      message: path.isEmpty ? 'the code path is empty' : '$path is no file',
      keys: {'entry': code},
    );
    return;
  }
  final symbol = entry.symbol;
  if (symbol.isEmpty) return;
  final text = context.codeTextOf(target, path);
  if (text == null) return;
  for (final segment in symbol.split(_segmentMark)) {
    if (_wordPattern(segment).hasMatch(text)) continue;
    yield context.finding(
      doc,
      FindingKind.implementsSymbolUnresolved,
      line: line,
      message: '$segment occurs nowhere in $path',
      keys: {'entry': code, 'symbol': segment},
    );
    return;
  }
}

/// Whether [item]'s paths are resolved: its status in [codeTarget] is
/// `implemented` or `deprecated`.
bool _isResolved(CheckContext context, IndexedDoc item, String? codeTarget) =>
    switch (context.index.itemStatus(item, codeTarget: codeTarget)) {
      RecordStatus.implemented || RecordStatus.deprecated => true,
      RecordStatus.planned || RecordStatus.skipped => false,
    };

RegExp _wordPattern(String word) =>
    RegExp('(?<!$_edge)${RegExp.escape(word)}(?!$_edge)', unicode: true);
