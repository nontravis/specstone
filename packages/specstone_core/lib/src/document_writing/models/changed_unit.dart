/// The part of a doc a [ChangedUnit] names.
enum UnitKind {
  /// The frontmatter lines no key owns.
  frontmatter,

  /// One frontmatter key, by name.
  field,

  /// The title line.
  title,

  /// The head without its title line.
  lead,

  /// One `##` section, by header text.
  section,
}

/// Which of the two texts hold a [ChangedUnit].
enum UnitSide {
  /// Both texts hold the unit, each with other content.
  both,

  /// Only the new text holds the unit.
  added,

  /// Only the old text holds the unit.
  removed,
}

/// A unit that differs between two texts.
final class ChangedUnit {
  const new({required this.kind, required this.name, required this.side});

  final UnitKind kind;

  /// The key of a [UnitKind.field] or the header text of a [UnitKind.section],
  /// as written, and empty for the other kinds.
  final String name;

  final UnitSide side;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is ChangedUnit &&
      other.kind == kind &&
      other.name == name &&
      other.side == side;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(kind, name, side);
}
