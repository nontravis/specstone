import 'package:specstone_core/src/doc_model/models/id_read.dart';

/// An item ID written in prose, and the offset where it starts.
final class ItemIdAt {
  const new({required this.at, required this.id});

  final int at;
  final ItemId id;
}
