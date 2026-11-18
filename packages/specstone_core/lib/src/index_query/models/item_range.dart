import 'package:specstone_core/src/index_query/models/item_link.dart';

/// Two item links of one section joined by ` to `.
final class ItemRange {
  const new({required this.first, required this.last});

  final ItemLink first;
  final ItemLink last;
}
