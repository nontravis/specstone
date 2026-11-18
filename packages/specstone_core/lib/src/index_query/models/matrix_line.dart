/// One non-blank line of a record's Verification matrix section: a row, or a
/// line that is no row.
sealed class MatrixLine {
  const new({required this.line});

  /// Reads the line [toJson] wrote.
  ///
  /// Throws a [FormatException] for a `kind` that names no line.
  factory fromJson(Map<String, Object?> json) {
    final line = json['line']! as int;
    return switch (json['kind']) {
      'test' => TestRow(
        item: json['item']! as String,
        edgeCase: json['edgeCase']! as String,
        literal: json['literal']! as String,
        fingerprint: json['fingerprint'] as String?,
        line: line,
        written: json['written']! as String,
      ),
      'skip' => SkipRow(
        item: json['item']! as String,
        edgeCase: json['edgeCase']! as String,
        reason: json['reason']! as String,
        fingerprint: json['fingerprint'] as String?,
        line: line,
        written: json['written']! as String,
      ),
      'malformed' => MalformedRow(line: line, text: json['text']! as String),
      final kind => throw FormatException('no matrix line of kind $kind'),
    };
  }

  /// The 1-based file line.
  final int line;

  /// The line as the index stores it.
  Map<String, Object?> toJson();
}

/// A section line that is neither a test row nor a skip row.
final class MalformedRow extends MatrixLine {
  const new({required super.line, required this.text});

  /// The line as written.
  final String text;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is MalformedRow && other.line == line && other.text == text;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(line, text);

  @override
  Map<String, Object?> toJson() => {
    'kind': 'malformed',
    'line': line,
    'text': text,
  };

  @override
  String toString() => 'MalformedRow(line: $line, text: $text)';
}

/// A row of the Verification matrix: the FR edge case it names, a test or a
/// skip.
sealed class MatrixRow extends MatrixLine {
  const new({
    required this.item,
    required this.edgeCase,
    required super.line,
    required this.written,
    this.fingerprint,
  });

  /// The FR the row names, relative to the record's feature.
  final String item;

  /// The edge case ID the row names, as the FR writes it.
  final String edgeCase;

  /// The 12 lowercase hex characters that end the row; null with none.
  final String? fingerprint;

  /// The row as the file writes it: its text less the leading `- `, and less
  /// its fingerprint with the spaces before it. A row built with no value takes
  /// the form with one space and one backtick around [TestRow.literal].
  final String written;

  /// The row's link label: the item, `#`, and the edge case.
  String get label => '$item#$edgeCase';
}

/// A row that names one string literal of a test's name.
final class TestRow extends MatrixRow {
  const new({
    required super.item,
    required super.edgeCase,
    required this.literal,
    required super.line,
    super.fingerprint,
    String? written,
  }) : super(written: written ?? '$item $edgeCase: `$literal`');

  /// The content of the row's code span, as the test file writes the name.
  final String literal;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is TestRow &&
      other.item == item &&
      other.edgeCase == edgeCase &&
      other.literal == literal &&
      other.fingerprint == fingerprint &&
      other.written == written &&
      other.line == line;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode =>
      Object.hash(item, edgeCase, literal, fingerprint, written, line);

  @override
  Map<String, Object?> toJson() => {
    'kind': 'test',
    'item': item,
    'edgeCase': edgeCase,
    'literal': literal,
    'fingerprint': fingerprint,
    'written': written,
    'line': line,
  };

  @override
  String toString() =>
      'TestRow(item: $item, edgeCase: $edgeCase, literal: $literal, '
      'fingerprint: $fingerprint, written: $written, line: $line)';
}

/// A row that gives the reason no test proves its edge case.
final class SkipRow extends MatrixRow {
  const new({
    required super.item,
    required super.edgeCase,
    required this.reason,
    required super.line,
    super.fingerprint,
    String? written,
  }) : super(written: written ?? '$item $edgeCase skipped: $reason');

  /// The text after `skipped: `, its fingerprint left off.
  final String reason;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is SkipRow &&
      other.item == item &&
      other.edgeCase == edgeCase &&
      other.reason == reason &&
      other.fingerprint == fingerprint &&
      other.written == written &&
      other.line == line;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode =>
      Object.hash(item, edgeCase, reason, fingerprint, written, line);

  @override
  Map<String, Object?> toJson() => {
    'kind': 'skip',
    'item': item,
    'edgeCase': edgeCase,
    'reason': reason,
    'fingerprint': fingerprint,
    'written': written,
    'line': line,
  };

  @override
  String toString() =>
      'SkipRow(item: $item, edgeCase: $edgeCase, reason: $reason, '
      'fingerprint: $fingerprint, written: $written, line: $line)';
}
