import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/doc_items.dart';
import 'package:specstone_core/src/doc_model/models/id_read.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/doc_model/task_ref.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart'
    show FieldType, RecordStatus;

/// One well-formed entry of a `task_ref` field, the field's id, and the file
/// line the entry is on.
typedef _TaskRefEntry = ({String field, TaskRef ref, int line});

/// Returns each well-formed entry of every `task_ref` field of [doc], in field
/// then entry order.
///
/// A field is found by its type alone. An entry that breaks the entry form is
/// left out; the frontmatter value rule reports it.
Iterable<_TaskRefEntry> _taskRefEntriesOf(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  final type = context.typeOf(doc);
  if (type == null) return;
  final lines = context.linesOf(doc);
  for (final field in type.fields) {
    if (field.type != FieldType.taskRef) continue;
    for (final (:value, :line, text: _) in lines.entriesOf(field.id)) {
      final ref = value is String ? TaskRef.parse(value) : null;
      if (ref != null) yield (field: field.id, ref: ref, line: line);
    }
  }
}

/// Returns a `task_item_missing` finding per task ref of [doc] whose item the
/// doc does not hold.
///
/// An item is an item ID of the lead or a section, or the text of a `###`
/// heading less one code span that encloses the whole text, matched exact and
/// case-sensitive. A whole-doc ref always resolves.
Iterable<Finding> checkTaskRefs(CheckContext context, IndexedDoc doc) sync* {
  Set<String>? held;
  for (final (field: _, :ref, :line) in _taskRefEntriesOf(context, doc)) {
    final item = ref.item;
    if (item == null) continue;
    held ??= _itemNamesOf(context, doc);
    if (held.contains(item)) continue;
    yield context.finding(
      doc,
      FindingKind.taskItemMissing,
      line: line,
      message: 'task ${ref.task} names item $item, which the doc does not hold',
      keys: {'task': ref.task, 'item': item},
    );
  }
}

/// Returns a `task_ref_leftover` finding per task ref of [doc] once its
/// feature is done.
///
/// A feature is done when it is not skipped, each story and FR under it has a
/// record entry, none is `planned`, and one is `implemented`. A doc shared
/// across targets needs each target that does not skip the feature done.
Iterable<Finding> checkLeftoverTaskRefs(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  final feature = _featureOf(context, doc);
  if (feature == null) return;
  final entries = _taskRefEntriesOf(context, doc).toList();
  if (entries.isEmpty || !_isDone(context.index, doc, feature)) return;
  final target = doc.target == null ? '' : ' --target ${doc.target}';
  for (final (:field, :ref, :line) in entries) {
    yield context.finding(
      doc,
      FindingKind.taskRefLeftover,
      line: line,
      message:
          'task ${ref.task} is left on the done feature ${feature.name}; '
          'drop the entry with specstone set ${doc.docTypeId}:${doc.name} '
          '--field $field$target --base <bases.fields.$field of get '
          '--json$target>, '
          'the list less the entry on stdin',
      keys: {'task': ref.task, 'item': ref.item ?? '', 'feature': feature.name},
    );
  }
}

/// Returns the feature [doc] nests under when its doc type has the `feature`
/// type as parent, else null.
IndexedDoc? _featureOf(CheckContext context, IndexedDoc doc) {
  if (context.typeOf(doc)?.parent != featureType) return null;
  final parent = context.index.parentOf(doc);
  return parent?.docTypeId == featureType ? parent : null;
}

bool _isDone(DocIndex index, IndexedDoc doc, IndexedDoc feature) {
  final targets = switch ((doc.target, index.targetNames)) {
    (final String target, _) => [target],
    (_, []) => <String?>[null],
    (_, final names) => names,
  };
  final live = [
    for (final target in targets)
      if (index.statusOf(feature, codeTarget: target) !=
          RecordStatus.skipped.wire)
        target,
  ];
  return live.isNotEmpty &&
      live.every((target) => _isFeatureDoneIn(index, feature, target));
}

/// Whether every story and FR under [feature] is recorded in [target], none
/// `planned`, and at least one `implemented`.
bool _isFeatureDoneIn(DocIndex index, IndexedDoc feature, String? target) {
  final statuses = {
    for (final member in index.subtreeOf(feature))
      if (member.docTypeId == storyType || member.docTypeId == frType)
        index.itemStatus(member, codeTarget: target),
  };
  return statuses.contains(RecordStatus.implemented) &&
      !statuses.contains(RecordStatus.planned);
}

Set<String> _itemNamesOf(CheckContext context, IndexedDoc doc) {
  final content = context.contentOf(doc);
  final lead = context.leadItemsOf(doc);
  return {
    for (final items in content.itemFacts.sectionItems)
      for (final item in items) ?item.id,
    ..._leadIdsOf(context, doc, lead),
    for (final items in [
      lead,
      for (var i = 0; i < content.sections.length; i++) context.itemsIn(doc, i),
    ])
      for (final item in items)
        if (item.kind == SectionItemKind.heading) _headingNameOf(item.head),
  };
}

/// Returns the heading [text] less one code span that encloses all of it.
String _headingNameOf(String text) {
  final name = text.trim();
  final spans = codeSpansOf(name);
  if (spans.length != 1) return name;
  final (:start, :end, :ticks) = spans.single;
  if (start != 0 || end != name.length) return name;
  return name.substring(ticks, name.length - ticks);
}

/// Returns the item IDs the [lead] items open with, read by each ID prefix a
/// section of the doc's type holds.
Iterable<String> _leadIdsOf(
  CheckContext context,
  IndexedDoc doc,
  Iterable<SectionItem> lead,
) sync* {
  final prefixes = {
    for (final section in context.typeOf(doc)!.sections) ?section.prefixId,
  };
  if (prefixes.isEmpty) return;
  for (final item in lead) {
    for (final prefix in prefixes) {
      if (readItemId(item.head, prefix) case final ItemId id) yield id.written;
    }
  }
}
