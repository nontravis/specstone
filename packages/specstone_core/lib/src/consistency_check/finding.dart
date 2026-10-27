/// A rule violation kind of the consistency check.
///
/// Values follow the `s02_api_check.md` Finding kinds table. [wire] is the
/// snake_case name printed in text and JSON; none equals a Specstone error
/// code (INV-2).
enum FindingKind {
  frontmatterInvalid('frontmatter_invalid'),
  requiredFieldMissing('required_field_missing'),
  fieldValueMismatch('field_value_mismatch'),
  fieldUndeclared('field_undeclared'),
  featureStatusWritten('feature_status_written'),
  titleMissing('title_missing'),
  requiredSectionMissing('required_section_missing'),
  sectionUndeclared('section_undeclared'),
  linesOverLimit('lines_over_limit'),
  charsOverLimit('chars_over_limit'),
  visionQuoteMissing('vision_quote_missing'),
  bannedWord('banned_word'),
  untypedDoc('untyped_doc'),
  docTypeAmbiguous('doc_type_ambiguous'),
  orderNumberDuplicate('order_number_duplicate'),
  parentAmbiguous('parent_ambiguous'),
  parentMissing('parent_missing'),
  fileNotUtf8('file_not_utf8'),
  fileUnreadable('file_unreadable'),
  implementsPathUnresolved('implements_path_unresolved'),
  implementsSymbolUnresolved('implements_symbol_unresolved'),
  coversPathMissing('covers_path_missing'),
  codeRootMissing('code_root_missing'),
  codeUncovered('code_uncovered'),
  docRefUnresolved('doc_ref_unresolved'),
  linkUnresolved('link_unresolved'),
  referenceDocUnresolved('reference_doc_unresolved'),
  listedFileMissing('listed_file_missing'),
  concernsTargetUnresolved('concerns_target_unresolved'),
  scenarioTraceUnresolved('scenario_trace_unresolved'),
  overrideKindMismatch('override_kind_mismatch'),
  overrideUnresolved('override_unresolved'),
  roleUnresolved('role_unresolved'),
  visionGoalWidened('vision_goal_widened'),
  visionGoalUnresolved('vision_goal_unresolved'),
  frTraceUnresolved('fr_trace_unresolved'),
  architectureMissing('architecture_missing'),
  implementsMissing('implements_missing'),
  suspect('suspect'),
  unconfirmed('unconfirmed'),
  confirmedEntryMalformed('confirmed_entry_malformed'),
  confirmedEntryStale('confirmed_entry_stale');

  new(this.wire);

  /// The snake_case name printed in text and JSON.
  final String wire;

  /// Whether the kind is reported against the project, not one doc (INV-12).
  bool get isProjectLevel =>
      this == codeUncovered || this == referenceDocUnresolved;
}

/// One rule violation at a line of a file.
final class Finding {
  const new({
    required this.kind,
    required this.path,
    required this.line,
    required this.message,
    this.name,
    this.keys = const {},
  });

  /// The violated rule.
  final FindingKind kind;

  /// A DocPath, or a project template file's path from the project root.
  final String path;

  /// The doc's name; null for an untyped doc and for a template file.
  final String? name;

  /// The 1-based line in the file.
  final int line;

  /// The violation in plain text.
  final String message;

  /// Extra JSON members after `message`.
  final Map<String, Object> keys;

  /// The `path:line: kind: message` text line.
  String get textLine => '$path:$line: ${kind.wire}: $message';

  /// The JSON object: `kind`, `docPath`, `name` when set, `line`, `message`,
  /// then [keys].
  Map<String, Object> toJson() => {
    'kind': kind.wire,
    'docPath': path,
    'name': ?name,
    'line': line,
    'message': message,
    ...keys,
  };
}
