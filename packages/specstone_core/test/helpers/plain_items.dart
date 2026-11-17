import 'package:specstone_core/src/index_query/item_facts.dart';

/// The first line facts of an item, without its readability facts.
typedef PlainItem = ({String? id, int line, int chars});

/// Returns [items] as [PlainItem]s.
List<PlainItem> plainItems(List<ItemFact> items) => [
  for (final item in items) (id: item.id, line: item.line, chars: item.chars),
];

/// Returns the section items of [facts] as [PlainItem]s, one list per section.
List<List<PlainItem>> plainSections(ItemFacts facts) => [
  for (final items in facts.sectionItems) plainItems(items),
];
