import 'package:specstone_core/src/doc_model/models/text_range.dart';
import 'package:specstone_core/src/index_query/models/written_destination.dart';

/// The inline text of a body and the definitions its links resolve against.
///
/// `text` is the body with every code unit markdown never reads as inline text
/// blanked to a space, line ends and length kept; `leaves` are the inline text
/// ranges in source order; `definitions` maps `linkLabel(label)` to the
/// destination as written, the first definition of a label winning;
/// `footnoteLabels` holds each footnote definition's label, lowercased;
/// `definitionSpans` holds the body range of each definition read, from its
/// label's `[` to the end of its last line, the line feed after it included
/// when one follows, cut around the container markers and indents of its
/// continuation lines, so a definition may hold several ranges.
final class LeafText {
  const new({
    required this.text,
    required this.leaves,
    required this.definitions,
    required this.footnoteLabels,
    required this.definitionLabels,
    required this.definitionDestinations,
    required this.definitionSpans,
  });

  final String text;
  final List<TextRange> leaves;
  final Map<String, WrittenDestination> definitions;
  final Set<String> footnoteLabels;
  final List<TextRange> definitionLabels;
  final List<TextRange> definitionDestinations;
  final List<TextRange> definitionSpans;
}
