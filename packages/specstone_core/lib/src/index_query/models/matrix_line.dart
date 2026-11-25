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
        edgeCase: json['edgeCase'] as String?,
        literals: List<String>.from(json['literals']! as List<Object?>),
        fingerprint: json['fingerprint'] as String?,
        line: line,
        written: json['written']! as String,
      ),
      'skip' => SkipRow(
        item: json['item']! as String,
        edgeCase: json['edgeCase'] as String?,
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

/// Which of the two shapes a row of the Verification matrix has.
enum RowForm {
  /// A row that names an FR: `<item>`.
  perFr,

  /// A row that names an FR edge case: `<item> <edge case>`.
  perEdgeCase,
}

/// A row of the Verification matrix: the FR, or the FR edge case, it names, a
/// test or a skip.
sealed class MatrixRow extends MatrixLine {
  const new({
    required this.item,
    required super.line,
    this.edgeCase,
    this.fingerprint,
    String? written,
  }) : _written = written;

  /// The FR the row names, relative to the record's feature.
  final String item;

  /// The edge case ID the row names, as the FR writes it; null on a per-FR row.
  final String? edgeCase;

  /// The 12 lowercase hex characters that end the row; null with none.
  final String? fingerprint;

  final String? _written;

  /// The row as the file writes it: its text less the leading `- `, and less
  /// its fingerprint with the spaces before it. A row built with no value takes
  /// the form with one space and one backtick around each literal.
  String get written => _written ?? _defaultWritten;

  /// The shape the row has.
  RowForm get form => edgeCase == null ? RowForm.perFr : RowForm.perEdgeCase;

  /// The row's link label: the item, then `#` and the edge case on a
  /// per-edge-case row.
  String get label => switch (edgeCase) {
    final edgeCase? => '$item#$edgeCase',
    null => item,
  };

  /// The item, then the edge case when the row names one.
  String get _head => switch (edgeCase) {
    final edgeCase? => '$item $edgeCase',
    null => item,
  };

  String get _defaultWritten;
}

/// A row that names the string literals of a test's names.
final class TestRow extends MatrixRow {
  const new({
    required super.item,
    required this.literals,
    required super.line,
    super.edgeCase,
    super.fingerprint,
    super.written,
  });

  /// The content of each code span of the row, as the test file writes the
  /// name, in file order; one on a per-edge-case row.
  final List<String> literals;

  /// The first of [literals].
  String get firstLiteral => literals.first;

  @override
  String get _defaultWritten =>
      '$_head: ${[for (final literal in literals) '`$literal`'].join(', ')}';

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is TestRow &&
      other.item == item &&
      other.edgeCase == edgeCase &&
      _sameStrings(other.literals, literals) &&
      other.fingerprint == fingerprint &&
      other.written == written &&
      other.line == line;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(
    item,
    edgeCase,
    Object.hashAll(literals),
    fingerprint,
    written,
    line,
  );

  @override
  Map<String, Object?> toJson() => {
    'kind': 'test',
    'item': item,
    'edgeCase': edgeCase,
    'literals': literals,
    'fingerprint': fingerprint,
    'written': written,
    'line': line,
  };

  @override
  String toString() =>
      'TestRow(item: $item, edgeCase: $edgeCase, literals: $literals, '
      'fingerprint: $fingerprint, written: $written, line: $line)';
}

bool _sameStrings(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A row that gives the reason no test proves its FR or edge case.
final class SkipRow extends MatrixRow {
  const new({
    required super.item,
    required this.reason,
    required super.line,
    super.edgeCase,
    super.fingerprint,
    super.written,
  });

  @override
  String get _defaultWritten => '$_head skipped: $reason';

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
