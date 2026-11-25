import 'package:specstone_core/src/index_query/models/link_cite.dart';
import 'package:specstone_core/src/index_query/models/link_text.dart';

/// A link a reader classified as an item link.
final class ItemLink {
  const new({required this.link, required this.cite});

  final LinkText link;
  final ItemCite cite;
}
