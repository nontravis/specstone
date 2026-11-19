/// One `banned_patterns` match on a line of a held section or on a prose field
/// value.
///
/// Exactly one of [section] and [field] is set.
final class BannedMatch {
  const new({
    this.section,
    this.field,
    required this.line,
    required this.entry,
    required this.match,
  }) : assert(
         (section == null) != (field == null),
         'a match names a section or a field, never both',
       );

  /// The position of the held section; null for a field match.
  final int? section;

  /// The id of the prose field; null for a section match.
  final String? field;

  /// The 1-based file line; a field match sits on its key's line.
  final int line;

  /// The position of the entry in `bannedEntriesOf` for the section; for a
  /// field match, in the doc-level entries.
  final int entry;

  /// The matched text; never empty and never excepted.
  final String match;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is BannedMatch &&
      other.section == section &&
      other.field == field &&
      other.line == line &&
      other.entry == entry &&
      other.match == match;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(section, field, line, entry, match);
}
