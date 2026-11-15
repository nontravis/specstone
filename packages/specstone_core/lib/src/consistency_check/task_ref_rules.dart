import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/doc_items.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/doc_model/task_ref.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart'
    show FieldType;

/// One well-formed entry of a `task_ref` field and the file line it is on.
typedef _TaskRefEntry = ({TaskRef ref, int line});

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
      if (ref != null) yield (ref: ref, line: line);
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
  for (final (:ref, :line) in _taskRefEntriesOf(context, doc)) {
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

Set<String> _itemNamesOf(CheckContext context, IndexedDoc doc) {
  final content = context.contentOf(doc);
  return {
    for (final items in content.itemFacts.sectionItems)
      for (final item in items) ?item.id,
    ..._leadIdsOf(context, doc),
    for (final items in [
      context.leadItemsOf(doc),
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

/// Returns the item IDs the lead's items open with, read by each ID prefix a
/// section of the doc's type holds.
Iterable<String> _leadIdsOf(CheckContext context, IndexedDoc doc) sync* {
  final prefixes = {
    for (final section in context.typeOf(doc)!.sections) ?section.prefixId,
  };
  if (prefixes.isEmpty) return;
  for (final item in context.leadItemsOf(doc)) {
    for (final prefix in prefixes) {
      if (readItemId(item.head, prefix) case final ItemId id) yield id.written;
    }
  }
}
