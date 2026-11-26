import 'package:specstone_core/src/doc_model/models/label_part.dart';

/// A chain of capital-prefix label parts joined by single spaces, with the
/// 0-based line of the text it starts on.
///
/// The chain holds at least one part with a prefix outside `F-`, `US-`, and
/// `FR-`. The config says which prefixes count, so `check` cuts the chain into
/// labels.
final class PrefixedLabelLine {
  const new({required this.line, required this.parts});

  final int line;
  final List<LabelPart> parts;
}
