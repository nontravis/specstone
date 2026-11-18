import 'package:specstone_core/src/doc_model/models/trace_note.dart';
import 'package:specstone_core/src/index_query/models/sentence_fact.dart';

/// What `check` reads of an item's readability.
///
/// `cells` holds the sentences of the item, one list for an item that is no
/// table row and one per cell for a table row; `notes` holds its trace notes.
/// A doc with no doc type holds none of either.
final class ReadabilityFacts {
  const new({required this.cells, required this.notes});

  final List<List<SentenceFact>> cells;
  final List<TraceNote> notes;
}
