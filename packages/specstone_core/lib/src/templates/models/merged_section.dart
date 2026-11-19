import 'package:specstone_core/src/templates/models/catalog_lint.dart';
import 'package:specstone_core/src/templates/models/diagram_lint.dart';
import 'package:specstone_core/src/templates/models/item_count_lint.dart';
import 'package:specstone_core/src/templates/models/item_field_lint.dart';
import 'package:specstone_core/src/templates/models/merged_lint.dart';
import 'package:specstone_core/src/templates/models/pattern_entry.dart';
import 'package:specstone_core/src/templates/models/required_when_lint.dart';
import 'package:specstone_core/src/templates/models/sentence_limit.dart';
import 'package:specstone_core/src/templates/models/summary_rows.dart';
import 'package:specstone_core/src/templates/models/when_field.dart';

/// One enabled guide section of a merged doc type.
final class MergedSection {
  const new({
    required this.id,
    required this.header,
    this.prefixId,
    this.required = false,
    this.description,
    this.template,
    this.maxChars,
    this.maxLines,
    this.bannedWords,
    this.allowedWords,
    this.linePrefix,
    this.query,
    this.summary,
    this.summaryRows,
    this.skeleton,
    this.bannedPatterns,
    this.requiredPatterns,
    this.minLines,
    this.catalog,
    this.namesCodes,
    this.itemFields,
    this.requiredWhen,
    this.diagram,
    this.maxSentences,
    this.itemCount,
    this.maxSubsections,
    this.maxItemLines,
    this.whenField,
    this.isOutputRef = false,
  });

  /// The section id.
  final String id;

  /// The section's heading.
  final String header;

  /// The section's numbering prefix.
  final String? prefixId;

  /// Whether a doc must carry the section.
  final bool required;

  /// What the section holds.
  final String? description;

  /// The section's body template.
  final String? template;

  /// The section's own character limit, replacing the doc-level value.
  final int? maxChars;

  /// The section's own line ceiling, replacing the doc-level value.
  final int? maxLines;

  /// The section's own banned words, merged for this section; the doc-level
  /// list applies on top of it.
  ///
  /// Null when no layer sets them.
  final List<String>? bannedWords;

  /// The section's own allowed words, merged for this section; the doc-level
  /// list applies on top of it.
  ///
  /// Null when no layer sets them.
  final List<String>? allowedWords;

  /// Limits the section's own banned words to its lines that start with it.
  ///
  /// Null when no layer sets it.
  final String? linePrefix;

  /// Whether the section is a query section; null when no layer sets it.
  final bool? query;

  /// Whether the section prints in a summary doc of a design bundle; null when
  /// no layer sets it.
  final bool? summary;

  /// The rows a summary doc prints of the section's table, or off; null when
  /// no layer sets it.
  final SummaryRows? summaryRows;

  /// Whether an optional section's header joins the skeleton `new` writes;
  /// null when no layer sets it.
  final bool? skeleton;

  /// The body rows a summary doc prints; null when unset or off.
  int? get summaryRowCount => summaryRows?.count;

  /// The section's own banned patterns, merged by `id`; null when no layer
  /// sets them.
  final List<PatternEntry>? bannedPatterns;

  /// The section's own required patterns, merged by `id`; null when no layer
  /// sets them.
  final List<PatternEntry>? requiredPatterns;

  /// The fewest non-blank lines the section holds; null when no layer sets it.
  final int? minLines;

  /// The code catalog the section's table is; null when no layer sets it.
  final CatalogLint? catalog;

  /// Whether a code span in the section can name a catalog code; null when no
  /// layer sets it.
  final bool? namesCodes;

  /// The nested items each top-level item holds, merged by `field`; null when
  /// no layer sets them.
  final List<ItemFieldLint>? itemFields;

  /// The rule that makes the section required; null when no layer sets it.
  final RequiredWhenLint? requiredWhen;

  /// The checks on the section's flowcharts; null when no layer sets them.
  final DiagramLint? diagram;

  /// The sentence limits; null when no layer sets them.
  final List<SentenceLimit>? maxSentences;

  /// The bounds on the section's item count; null when no layer sets them.
  final ItemCountLint? itemCount;

  /// The most `###` subsections the section holds; null when no layer sets it.
  final int? maxSubsections;

  /// The most non-blank lines one item holds; null when no layer sets it.
  final int? maxItemLines;

  /// The doc field and values that bind [required]; null when no layer sets
  /// it.
  final WhenField? whenField;

  /// Whether the section's lines are pointers the CLI checks, outside the
  /// approval hash and the draft mark.
  final bool isOutputRef;

  /// Returns a copy with each non-null argument replacing its property.
  MergedSection copyWith({
    String? header,
    String? prefixId,
    bool? required,
    String? description,
    String? template,
    int? maxChars,
    int? maxLines,
    List<String>? bannedWords,
    List<String>? allowedWords,
    String? linePrefix,
    bool? query,
    bool? summary,
    SummaryRows? summaryRows,
    bool? skeleton,
    List<PatternEntry>? bannedPatterns,
    List<PatternEntry>? requiredPatterns,
    int? minLines,
    CatalogLint? catalog,
    bool? namesCodes,
    List<ItemFieldLint>? itemFields,
    RequiredWhenLint? requiredWhen,
    DiagramLint? diagram,
    List<SentenceLimit>? maxSentences,
    ItemCountLint? itemCount,
    int? maxSubsections,
    int? maxItemLines,
    WhenField? whenField,
    bool? isOutputRef,
  }) => MergedSection(
    id: id,
    header: header ?? this.header,
    prefixId: prefixId ?? this.prefixId,
    required: required ?? this.required,
    description: description ?? this.description,
    template: template ?? this.template,
    maxChars: maxChars ?? this.maxChars,
    maxLines: maxLines ?? this.maxLines,
    bannedWords: bannedWords ?? this.bannedWords,
    allowedWords: allowedWords ?? this.allowedWords,
    linePrefix: linePrefix ?? this.linePrefix,
    query: query ?? this.query,
    summary: summary ?? this.summary,
    summaryRows: summaryRows ?? this.summaryRows,
    skeleton: skeleton ?? this.skeleton,
    bannedPatterns: bannedPatterns ?? this.bannedPatterns,
    requiredPatterns: requiredPatterns ?? this.requiredPatterns,
    minLines: minLines ?? this.minLines,
    catalog: catalog ?? this.catalog,
    namesCodes: namesCodes ?? this.namesCodes,
    itemFields: itemFields ?? this.itemFields,
    requiredWhen: requiredWhen ?? this.requiredWhen,
    diagram: diagram ?? this.diagram,
    maxSentences: maxSentences ?? this.maxSentences,
    itemCount: itemCount ?? this.itemCount,
    maxSubsections: maxSubsections ?? this.maxSubsections,
    maxItemLines: maxItemLines ?? this.maxItemLines,
    whenField: whenField ?? this.whenField,
    isOutputRef: isOutputRef ?? this.isOutputRef,
  );

  /// Returns the JSON object of this section with only the keys set.
  ///
  /// `required` and `outputRef` print only when true; `lint` is absent when no
  /// lint key is set, and holds each guide-rule key a layer sets.
  Map<String, Object> toJson() {
    final lint = {
      ...MergedLint(
        maxChars: maxChars,
        maxLines: maxLines,
        bannedWords: bannedWords,
        allowedWords: allowedWords,
        bannedPatterns: bannedPatterns,
      ).toJson(),
      'linePrefix': ?linePrefix,
      'requiredPatterns': ?requiredPatterns?.map((p) => p.toJson()).toList(),
      'minLines': ?minLines,
      'catalog': ?catalog?.toJson(),
      'namesCodes': ?namesCodes,
      'itemFields': ?itemFields?.map((f) => f.toJson()).toList(),
      'requiredWhen': ?requiredWhen?.toJson(),
      'diagram': ?diagram?.toJson(),
      'maxSentences': ?maxSentences?.map((l) => l.toJson()).toList(),
      'itemCount': ?itemCount?.toJson(),
      'maxSubsections': ?maxSubsections,
      'maxItemLines': ?maxItemLines,
    };
    return {
      'id': id,
      'prefixId': ?prefixId,
      if (required) 'required': true,
      'header': header,
      'description': ?description,
      'template': ?template,
      if (lint.isNotEmpty) 'lint': lint,
      'query': ?query,
      'summary': ?summary,
      'summaryRows': ?summaryRows?.toJson(),
      if (isOutputRef) 'outputRef': true,
      if (whenField case WhenField(:final field, :final values))
        'whenField': {'field': field, 'values': values},
    };
  }
}
