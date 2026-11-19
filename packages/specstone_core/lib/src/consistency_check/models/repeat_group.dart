import 'package:specstone_core/src/consistency_check/models/repeat_item.dart';

/// One maximal run of normalized words and the items of two or more typed
/// docs that hold it.
final class RepeatGroup {
  const new({required this.run, required this.items});

  final String run;
  final List<RepeatItem> items;
}
