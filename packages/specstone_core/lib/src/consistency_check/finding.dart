/// Who clears a finding (`print_findings`): the Owner by an act of theirs, or
/// the Agent by editing.
///
/// It is no level: an `owner` finding counts toward the count line and the exit
/// status as any other.
enum WaitsFor {
  owner('owner'),
  agent('agent');

  new(this.wire);

  /// The name printed in JSON.
  final String wire;
}

/// The tag the text line of an `owner` finding ends with.
const _ownerTag = ' (waits for the Owner)';

/// What every line under a finding line starts with.
const _blockIndent = '    ';

/// A rule violation kind of the consistency check.
///
/// Values follow the `s02_api_check.md` Finding kinds table. [wire] is the
/// snake_case name printed in text and JSON; none equals a Specstone error
/// code (INV-2).
enum FindingKind {
  frontmatterInvalid('frontmatter_invalid'),
  requiredFieldMissing('required_field_missing'),
  fieldGroupMissing('field_group_missing'),
  fieldValueMismatch('field_value_mismatch'),
  fieldUndeclared('field_undeclared'),
  featureStatusWritten('feature_status_written'),
  requirementStatusWritten('requirement_status_written'),
  titleMissing('title_missing'),
  requiredSectionMissing('required_section_missing'),
  sectionUndeclared('section_undeclared'),
  linesOverLimit('lines_over_limit'),
  charsOverLimit('chars_over_limit'),
  itemOverLimit('item_over_limit'),
  visionQuoteMissing('vision_quote_missing'),
  titleNumbered('title_numbered'),
  sentencesOverLimit('sentences_over_limit'),
  itemCountOutOfRange('item_count_out_of_range'),
  prefixCountMismatch('prefix_count_mismatch'),
  linesUnderLimit('lines_under_limit'),
  itemFieldMissing('item_field_missing'),
  sectionUnneeded('section_unneeded'),
  systemUnresolved('system_unresolved'),
  operationUnmatched('operation_unmatched'),
  scopeOperationUnresolved('scope_operation_unresolved'),
  scopePathUncovered('scope_path_uncovered'),
  bannedWord('banned_word'),
  untypedDoc('untyped_doc'),
  docTypeAmbiguous('doc_type_ambiguous'),
  orderNumberDuplicate('order_number_duplicate'),
  parentAmbiguous('parent_ambiguous'),
  parentMissing('parent_missing'),
  featureMixedChildren('feature_mixed_children'),
  subFeatureTooSmall('sub_feature_too_small'),
  nestingOverLimit('nesting_over_limit'),
  pathOverLimit('path_over_limit'),
  fileNotUtf8('file_not_utf8'),
  fileUnreadable('file_unreadable'),
  patternBanned('pattern_banned'),
  patternMissing('pattern_missing'),
  itemIdMissing('item_id_missing'),
  itemIdDuplicate('item_id_duplicate'),
  itemIdLettered('item_id_lettered'),
  implementsPathUnresolved('implements_path_unresolved'),
  implementsSymbolUnresolved('implements_symbol_unresolved'),
  docCitedInCode('doc_cited_in_code'),
  coversPathMissing('covers_path_missing'),
  codeRootMissing('code_root_missing'),
  codeUncovered('code_uncovered'),
  docRefUnresolved('doc_ref_unresolved'),
  docRefDuplicate('doc_ref_duplicate'),
  docRefSelf('doc_ref_self'),
  linkUnresolved('link_unresolved'),
  linkAnchorMissing('link_anchor_missing'),
  linkSelf('link_self'),
  referenceMalformed('reference_malformed'),
  linkTargetMissing('link_target_missing'),
  markdownUnparsed('markdown_unparsed'),
  docNameUnresolved('doc_name_unresolved'),
  perTargetReference('per_target_reference'),
  sharedDocCodePath('shared_doc_code_path'),
  numberLabel('number_label'),
  referenceDocUnresolved('reference_doc_unresolved'),
  listedFileMissing('listed_file_missing'),
  concernsTargetUnresolved('concerns_target_unresolved'),
  journeyStepUnresolved('journey_step_unresolved'),
  journeyAfterUnresolved('journey_after_unresolved'),
  journeyStepDuplicate('journey_step_duplicate'),
  scenarioTraceUnresolved('scenario_trace_unresolved'),
  overrideKindMismatch('override_kind_mismatch'),
  overrideUnresolved('override_unresolved'),
  roleUnresolved('role_unresolved'),
  visionGoalWidened('vision_goal_widened'),
  visionGoalUnresolved('vision_goal_unresolved'),
  goalServesMissing('goal_serves_missing'),
  frTraceUnresolved('fr_trace_unresolved'),
  architectureMissing('architecture_missing'),
  implementsMissing('implements_missing'),
  testsUnresolved('tests_unresolved'),
  testsMissing('tests_missing'),
  recordEntryUnresolved('record_entry_unresolved'),
  recordEntryDuplicate('record_entry_duplicate'),
  skipReasonMissing('skip_reason_missing'),
  skipWithCode('skip_with_code'),
  entryUnderSkip('entry_under_skip'),
  errorCodeDuplicate('error_code_duplicate'),
  errorCodeUnraised('error_code_unraised'),
  errorCodeUncataloged('error_code_uncataloged'),
  diagramTitleMissing('diagram_title_missing'),
  diagramEdgeUnlabeled('diagram_edge_unlabeled'),
  diagramLabelUnquoted('diagram_label_unquoted'),
  suspect('suspect'),
  unconfirmed('unconfirmed'),
  confirmedEntryMalformed('confirmed_entry_malformed'),
  confirmedEntryStale('confirmed_entry_stale'),
  formatDrift('format_drift'),
  agentBlockStale('agent_block_stale'),
  tbrOpen('tbr_open'),
  approvalStale('approval_stale');

  new(this.wire);

  /// The snake_case name printed in text and JSON.
  final String wire;

  /// Who clears a finding of this kind, unless its rule says otherwise.
  WaitsFor get waitsFor => switch (this) {
    approvalStale ||
    charsOverLimit ||
    itemOverLimit ||
    linesOverLimit ||
    tbrOpen => WaitsFor.owner,
    _ => WaitsFor.agent,
  };

  /// Whether the kind is reported against the project, not one doc (INV-12).
  bool get isProjectLevel =>
      this == codeUncovered ||
      this == docCitedInCode ||
      this == referenceDocUnresolved ||
      this == agentBlockStale;
}

/// One rule violation at a line of a file.
final class Finding {
  const new({
    required this.kind,
    required this.path,
    required this.line,
    required this.message,
    this.name,
    WaitsFor? waitsFor,
    this.keys = const {},
  }) : _waitsFor = waitsFor;

  /// The violated rule.
  final FindingKind kind;

  /// A DocPath, or a project template or agent file's path from the project
  /// root.
  final String path;

  /// The doc's name; null for an untyped doc and for a template file.
  final String? name;

  /// The 1-based line in the file.
  final int line;

  /// The violation in plain text.
  final String message;

  final WaitsFor? _waitsFor;

  /// Who clears the finding: the rule's choice, else the kind's.
  WaitsFor get waitsFor => _waitsFor ?? kind.waitsFor;

  /// Extra JSON members after `waitsFor`.
  final Map<String, Object> keys;

  /// The `path:line: kind: message` text line, with no tag.
  String get textLine => '$path:$line: ${kind.wire}: $message';

  /// The lines the text output prints: [textLine], ended with the tag when
  /// [waitsFor] is `owner`.
  ///
  /// A `suspect` or `unconfirmed` finding with a `text` key goes on with each
  /// line of the upstream block and then `fingerprint <hash>`, each indented
  /// 4 spaces, so a reader cut short of the block's end never reaches the
  /// fingerprint.
  List<String> get textLines => [
    if (waitsFor == WaitsFor.owner) '$textLine$_ownerTag' else textLine,
    ..._upstreamBlockLines,
  ];

  // `reference_malformed` and `item_id_*` findings hold an unrelated `text`.
  Iterable<String> get _upstreamBlockLines sync* {
    final text = keys['text'];
    if ((kind != FindingKind.suspect && kind != FindingKind.unconfirmed) ||
        text is! String) {
      return;
    }
    if (text.isNotEmpty) {
      for (final line in text.split('\n')) {
        yield '$_blockIndent$line';
      }
    }
    yield '${_blockIndent}fingerprint ${keys['fingerprint']}';
  }

  /// The JSON object: `kind`, `docPath`, `name` when set, `line`, `message`
  /// with no tag, `waitsFor`, then [keys].
  Map<String, Object> toJson() => {
    'kind': kind.wire,
    'docPath': path,
    'name': ?name,
    'line': line,
    'message': message,
    'waitsFor': waitsFor.wire,
    ...keys,
  };
}
