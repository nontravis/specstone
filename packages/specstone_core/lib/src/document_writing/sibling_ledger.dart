import 'dart:math';

/// The numbers and names one call gives the docs it lands in each folder, so
/// a created doc and a moved doc never take one number or one name there.
///
/// A folder is keyed by its container path and the doc type it holds.
final class SiblingLedger {
  final _last = <String, int>{};
  final _names = <String, Set<String>>{};

  /// Returns the next number in [container] for [docTypeId], past
  /// [highestOnDisk] and every number this ledger gave there.
  int nextNumber(String container, String docTypeId, int highestOnDisk) {
    final key = '$container $docTypeId';
    final number = max(_last[key] ?? 0, highestOnDisk) + 1;
    _last[key] = number;
    return number;
  }

  /// Whether [name] is free in [container] for [docTypeId]; takes it when so.
  bool claim(String container, String docTypeId, String name) =>
      (_names['$container $docTypeId'] ??= {}).add(name);
}
