import 'package:specstone_core/src/index_query/models/readability_facts.dart';

/// One item of a doc: the key `check` holds it by when it reads one, its
/// first line, its visible code points, and its readability facts.
///
/// `line`, `visibleChars`, and `readability` are those of the text the doc's
/// counts cover; `visibleChars` leaves out what a link or a link reference
/// definition hides, as `HiddenText` reads it.
final class ItemFact {
  const new({
    required this.id,
    required this.line,
    required this.visibleChars,
    required this.readability,
  });

  final String? id;
  final int line;
  final int visibleChars;
  final ReadabilityFacts readability;
}
