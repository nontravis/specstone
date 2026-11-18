/// An item ID or a scenario number where its item opens.
sealed class IdRead {
  const new({required this.prefix, required this.digits});

  final String prefix;
  final String digits;

  /// Prefix plus digits, plus any letter.
  String get written;
}

/// Prefix and digits that end at a character that is no letter and no digit.
final class ItemId extends IdRead {
  const new({required super.prefix, required super.digits});

  BigInt get number => BigInt.parse(digits);

  @override
  String get written => '$prefix$digits';
}

/// Digits a letter follows (`RULE-7a`, `Scenario 6a`): no ID, its own or the
/// digits'.
final class LetteredId extends IdRead {
  const new({
    required super.prefix,
    required super.digits,
    required this.letters,
  });

  final String letters;

  @override
  String get written => '$prefix$digits$letters';
}

/// Digits, a letter run, then a digit (`RULE-7a1`, `Scenario 6a2`): a form
/// the grammar cannot read, neither an ID nor a lettered one.
final class UnreadableId extends IdRead {
  const new({required super.prefix, required super.digits, required this.rest});

  /// The letter and digit run after [digits], as written.
  final String rest;

  @override
  String get written => '$prefix$digits$rest';
}
