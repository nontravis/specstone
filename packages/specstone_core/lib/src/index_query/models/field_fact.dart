import 'package:specstone_core/src/index_query/models/readability_facts.dart';

/// The readability facts of one prose field value, read as one item.
final class FieldFact {
  const new({required this.readability});

  /// The sentences of the value, as one item holds them.
  final ReadabilityFacts readability;
}
