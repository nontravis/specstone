import 'package:specstone_core/src/doc_model/models/label_part.dart';

/// A chain of capital-prefix label parts joined by single spaces at its file
/// line.
///
/// The index holds every chain with a part outside `F-`, `US-`, and `FR-`,
/// whatever the config lists; `check` cuts it into the labels the config's
/// prefixes make.
final class PrefixedLabelPlace {
  const new({required this.line, required this.parts});

  final int line;
  final List<LabelPart> parts;
}
