import 'package:specstone_core/src/index_query/models/item_fact.dart';
import 'package:specstone_core/src/index_query/models/item_facts.dart';

/// The first line facts of an item, without its readability facts; `chars` is
/// its visible count.
typedef PlainItem = ({String? id, int line, int chars});

/// Returns [items] as [PlainItem]s.
List<PlainItem> plainItems(List<ItemFact> items) => [
  for (final item in items)
    (id: item.id, line: item.line, chars: item.visibleChars),
];

/// Returns the section items of [facts] as [PlainItem]s, one list per section.
List<List<PlainItem>> plainSections(ItemFacts facts) => [
  for (final items in facts.sectionItems) plainItems(items),
];
