import 'package:specstone_core/src/templates/models/line_prefix_count.dart';

/// The bounds on the number of items in a section.
final class ItemCountLint {
  const new({
    this.min,
    this.max,
    this.perSubsection = false,
    this.prefixes = const [],
    this.waitsForOwner = false,
  });

  /// The fewest items, when bounded.
  final int? min;

  /// The most items, when bounded.
  final int? max;

  /// Whether each subsection is counted alone.
  final bool perSubsection;

  /// The item counts required per line prefix.
  final List<LinePrefixCount> prefixes;

  /// Whether an out-of-range count waits for the Owner, not the agent.
  final bool waitsForOwner;

  /// Returns the JSON object of these bounds, `min` and `max` only when set.
  Map<String, Object> toJson() => {
    'min': ?min,
    'max': ?max,
    'perSubsection': perSubsection,
    'prefixes': [
      for (final LinePrefixCount(:linePrefix, :count) in prefixes)
        {'linePrefix': linePrefix, 'count': count},
    ],
  };
}
