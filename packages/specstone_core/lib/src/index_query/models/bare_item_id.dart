/// A bare item ID of a typed doc's prose: the ID at its file line and column,
/// with the citation whose item-ID run holds it, or none.
///
/// `column` is the 0-based offset of the ID in its line. The citation is as
/// written: nothing is resolved here.
final class BareItemId {
  const new({
    required this.line,
    required this.column,
    required this.id,
    required this.citation,
  });

  final int line;
  final int column;
  final String id;
  final BareIdCitation? citation;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is BareItemId &&
      other.line == line &&
      other.column == column &&
      other.id == id &&
      other.citation == citation;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(line, column, id, citation);
}

/// The citation an item-ID run follows.
sealed class BareIdCitation {
  const new();
}

/// A link: its destination as written, a `#anchor` kept, a bare `#anchor`
/// included.
final class LinkCitation extends BareIdCitation {
  const new({required this.destination});

  final String destination;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is LinkCitation && other.destination == destination;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => destination.hashCode;
}

/// A cite candidate: the doc name or path as written, less its
/// `#<section key>`.
final class CiteCitation extends BareIdCitation {
  const new({required this.written});

  final String written;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is CiteCitation && other.written == written;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => written.hashCode;
}
