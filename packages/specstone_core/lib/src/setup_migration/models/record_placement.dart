import 'package:specstone_core/src/document_writing/models/new_record.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';

/// Where the values a `move_to_record` step took land: the `value_unplaced`
/// faults when any value has no place, else the new text of each existing
/// record by its planned DocPath and each record to create.
final class RecordPlacement {
  const new({
    required this.unplaced,
    required this.edits,
    required this.creates,
  });

  final List<MigrateFault> unplaced;
  final Map<String, String> edits;
  final List<NewRecord> creates;
}
