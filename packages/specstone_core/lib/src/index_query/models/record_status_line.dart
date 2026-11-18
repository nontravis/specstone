import 'package:specstone_core/src/templates/models/record_status.dart';

/// The item, status, and `skipped` reason of an `item:status[:reason]` line.
final class RecordStatusLine {
  const new({required this.item, required this.status, required this.reason});

  final String item;
  final RecordStatus? status;
  final String? reason;
}
