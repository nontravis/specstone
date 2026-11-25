import 'package:specstone_core/src/index_query/models/matrix_line.dart';

final _lineBreak = RegExp(r'\s*\n\s*');

/// What the index keeps about one doc, apart from its text.
final class IndexedDoc {
  const new({
    required this.docPath,
    this.docTypeId,
    required this.name,
    this.target,
    this.parentPath,
    this.title,
    required this.frontmatter,
    required this.tokens,
    this.formatted,
    this.approvalHash,
    this.order = 0,
    this.warnings = const [],
    this.matrixLines = const [],
  });

  /// The path of the doc relative to the docs root.
  final String docPath;

  /// The id of the doc type that matches [docPath]; null when untyped.
  final String? docTypeId;

  /// The name the doc answers to in a query.
  final String name;

  /// The code target a per-target doc belongs to: the one whose pattern set
  /// matched with two or more targets, else the single target when named.
  ///
  /// Null for a shared doc, a doc of a doc type that is not per-target, and
  /// an untyped doc.
  final String? target;

  /// The docPath of the doc this one nests under; null for a root doc.
  final String? parentPath;

  /// The text after `# ` in the doc head; null without a title line.
  final String? title;

  /// The frontmatter as plain Dart values; empty without valid frontmatter.
  final Map<String, Object?> frontmatter;

  /// The size of the whole file in tokens.
  final int tokens;

  /// Whether the LF text equals the text the format command lays out.
  ///
  /// Null for an untyped doc, a doc whose bytes are not UTF-8, and a doc the
  /// format command refuses: the docs whose counts cover their text as
  /// decoded.
  final bool? formatted;

  /// The `comparedApprovalHash` of the doc; null for an untyped doc or one
  /// whose frontmatter is not valid YAML.
  final String? approvalHash;

  /// The position of the doc in tree order.
  final int order;

  /// What went wrong while reading the doc, one sentence each.
  final List<String> warnings;

  /// The lines of the doc's Verification matrix section, in file order; empty
  /// for a doc that is no record, or whose record holds no such section.
  final List<MatrixLine> matrixLines;

  /// Whether the doc shows under [codeTarget]: always with none, else only
  /// when the doc is shared or belongs to that target.
  bool inTarget(String? codeTarget) =>
      codeTarget == null || target == null || target == codeTarget;

  /// Whether exactly one doc type matches [docPath].
  bool get isTyped => docTypeId != null;

  /// Whether the doc has a `# ` title line that holds text.
  ///
  /// The test `check` runs for its missing-title finding.
  bool get hasTitle => title?.trim().isNotEmpty ?? false;

  /// The `status` the doc writes, or null when it writes none.
  ///
  /// A story or FR takes its status from its record entry instead
  /// (`DocIndex.statusOf`); this is the raw written value.
  String? get writtenStatus => switch (frontmatter['status']) {
    final String status => status,
    _ => null,
  };

  /// Whether the `draft` key holds the YAML boolean `true`.
  bool get isDraft => frontmatter['draft'] == true;

  /// Returns the value of [key] when the frontmatter holds it as a YAML
  /// string, else null.
  ///
  /// [valuesOf] reads a number as text; this read does not.
  String? stringValueOf(String key) => switch (frontmatter[key]) {
    final String value => value,
    _ => null,
  };

  /// Returns the `summary` string on one line, or null when it holds no text.
  ///
  /// A non-string reads as null as in [stringValueOf]; each line break, with
  /// the space around it, becomes one space, so a block scalar reads whole.
  String? get oneLineSummary {
    final line = stringValueOf('summary')?.trim().replaceAll(_lineBreak, ' ');
    return line == null || line.isEmpty ? null : line;
  }

  /// Returns the values of [key]: a scalar as one string, each scalar item of
  /// a list, else none.
  List<String> valuesOf(String key) => switch (frontmatter[key]) {
    final List<Object?> items => [
      for (final item in items)
        if (_isScalar(item)) '$item',
    ],
    final Object? value when _isScalar(value) => ['$value'],
    _ => const [],
  };
}

bool _isScalar(Object? value) =>
    value is String || value is num || value is bool;
