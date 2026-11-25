import 'package:specstone_core/src/document_writing/models/text_edit.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';

/// What a rename or a move does to the record entries of every code target:
/// the edit of each record that renames or loses entries or gains some, by
/// its DocPath before the moves, and the record it creates, as a draft, for
/// entries that land where no record is.
final class RecordPlan {
  const new({required this.edits, required this.creates});

  final Map<String, TextEdit> edits;
  final List<CreateStep> creates;
}
