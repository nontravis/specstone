import 'package:specstone_core/src/doc_model/models/trace_note.dart';

/// Every trace note of an item in file order, and its text with the closing
/// notes removed.
final class ItemTraceNotes {
  const new({required this.notes, required this.counted});

  final List<TraceNote> notes;
  final String counted;
}
