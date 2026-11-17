import 'dart:math';

import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/pattern_entry.dart';
import 'package:specstone_core/src/templates/reference_entry.dart';
import 'package:specstone_core/src/templates/summary_rows.dart';

/// One enabled frontmatter field of a merged doc type.
final class MergedField {
  const new({
    required this.id,
    required this.type,
    this.list = false,
    this.required = false,
    this.enumValues,
    this.docTypes,
    PointerKind? pointer,
    this.description,
  }) : pointer = type == FieldType.outputRef ? pointer : null;

  /// The field id.
  final String id;

  /// The field type.
  final FieldType type;

  /// Whether the field is a list of [type].
  final bool list;

  /// Whether a doc must carry the field.
  final bool required;

  /// The allowed values of an `enum` field.
  final List<String>? enumValues;

  /// The target doc type ids of a `doc_ref` field.
  final List<String>? docTypes;

  /// How an `output_ref` field's value matches a path; null for any other type.
  final PointerKind? pointer;

  /// What the field holds.
  final String? description;

  /// Returns a copy with each non-null argument replacing its property.
  ///
  /// A list the new type does not use is dropped unless the call writes it:
  /// [enumValues] belongs to `enum` only, [docTypes] to `doc_ref` only, and
  /// [pointer] to `output_ref` only.
  MergedField copyWith({
    FieldType? type,
    bool? list,
    bool? required,
    List<String>? enumValues,
    List<String>? docTypes,
    PointerKind? pointer,
    String? description,
  }) {
    final newType = type ?? this.type;
    return MergedField(
      id: id,
      type: newType,
      list: list ?? this.list,
      required: required ?? this.required,
      enumValues:
          enumValues ??
          (newType == FieldType.enumType ? this.enumValues : null),
      docTypes:
          docTypes ?? (newType == FieldType.docRef ? this.docTypes : null),
      pointer: pointer ?? this.pointer,
      description: description ?? this.description,
    );
  }

  /// Returns the JSON object of this field with only the keys set.
  ///
  /// `list` and `required` print only when true.
  Map<String, Object> toJson() => {
    'id': id,
    'type': type.wire,
    if (list) 'list': true,
    if (required) 'required': true,
    'enum': ?enumValues,
    'docTypes': ?docTypes,
    'pointer': ?pointer?.wire,
    'description': ?description,
  };
}

/// A section table that is a code catalog.
final class CatalogLint {
  const new({required this.column});

  /// The header of the column whose code spans are the catalog's codes.
  final String column;

  /// Returns the JSON object of this catalog.
  Map<String, Object> toJson() => {'column': column};
}

/// A nested `- **<field>:** <text>` item every top-level item must hold.
final class ItemFieldLint {
  const new({required this.field, this.values, this.when});

  /// The nested item's label; the merge key.
  final String field;

  /// The texts the nested item may hold; any text when null.
  final List<String>? values;

  /// The condition under which the item must hold this field; always when null.
  final ItemFieldWhen? when;

  /// Returns whether an item with these nested [fields] must hold this field.
  bool appliesTo(Map<String, String> fields) => when?.isMetBy(fields) ?? true;

  /// Returns the JSON object of this item field, `values` and `when` only when
  /// set.
  Map<String, Object> toJson() => {
    'field': field,
    'values': ?values,
    'when': ?when?.toJson(),
  };
}

/// A condition on one nested field of an item: the field holds exactly a value.
final class ItemFieldWhen {
  const new({required this.field, required this.value});

  /// The label of the nested item that is read.
  final String field;

  /// The text that nested item must hold, compared exactly.
  final String value;

  /// Returns whether [fields] holds [field] with exactly [value].
  bool isMetBy(Map<String, String> fields) => fields[field] == value;

  /// Returns the JSON object of this condition.
  Map<String, Object> toJson() => {'field': field, 'value': value};
}

/// A section that is required while an item of another section holds a value.
final class RequiredWhenLint {
  const new({required this.section, required this.field, required this.value});

  /// The id of the section whose items are read.
  final String section;

  /// The nested item label read in that section.
  final String field;

  /// The field value that makes this section required.
  final String value;

  /// Returns the JSON object of this rule.
  Map<String, Object> toJson() => {
    'section': section,
    'field': field,
    'value': value,
  };
}

/// The checks on each `mermaid` flowchart in a section.
final class DiagramLint {
  const new({
    this.title = false,
    this.edgeLabels = false,
    this.bannedLabels = const [],
  });

  /// Whether a diagram must carry a title.
  final bool title;

  /// Whether every edge must carry a label.
  final bool edgeLabels;

  /// The labels a diagram may not hold.
  final List<String> bannedLabels;

  /// Returns the JSON object of this diagram lint.
  Map<String, Object> toJson() => {
    'title': title,
    'edgeLabels': edgeLabels,
    'bannedLabels': bannedLabels,
  };
}

/// The most sentences a line, or a table cell, may hold.
final class SentenceLimit {
  const new({required this.count, this.linePrefix, this.column});

  /// The most sentences allowed.
  final int count;

  /// Limits the check to lines that start with it.
  final String? linePrefix;

  /// Limits the check to cells under this table header.
  final String? column;

  /// Returns the JSON object of this limit, each optional key only when set.
  Map<String, Object> toJson() => {
    'count': count,
    'linePrefix': ?linePrefix,
    'column': ?column,
  };
}

/// The bounds on the number of items in a section.
final class ItemCountLint {
  const new({
    this.min,
    this.max,
    this.perSubsection = false,
    this.prefixes = const [],
  });

  /// The fewest items, when bounded.
  final int? min;

  /// The most items, when bounded.
  final int? max;

  /// Whether each subsection is counted alone.
  final bool perSubsection;

  /// The item counts required per line prefix.
  final List<({String linePrefix, int count})> prefixes;

  /// Returns the JSON object of these bounds, `min` and `max` only when set.
  Map<String, Object> toJson() => {
    'min': ?min,
    'max': ?max,
    'perSubsection': perSubsection,
    'prefixes': [
      for (final (:linePrefix, :count) in prefixes)
        {'linePrefix': linePrefix, 'count': count},
    ],
  };
}

/// The doc field and values that bind a section's `required`.
typedef WhenField = ({String field, List<String> values});

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
    whenField: whenField ?? this.whenField,
    isOutputRef: isOutputRef ?? this.isOutputRef,
  );

  /// Returns the JSON object of this section with only the keys set.
  ///
  /// `required` prints only when true; `lint` is absent when no lint key is
  /// set, and holds each guide-rule key a layer sets.
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
      if (whenField case (:final field, :final values))
        'whenField': {'field': field, 'values': values},
    };
  }
}

/// The id of the record doc type's matrix section, the one section whose
/// lines are pointers.
const verificationMatrixKey = 'verification_matrix';

/// The enabled matrix section of [recordType], or null.
///
/// Null when [recordType] holds no `record_status` field, so only the record
/// doc type has a matrix. Finds the section by [verificationMatrixKey], never
/// by [MergedSection.isOutputRef].
MergedSection? verificationMatrixOf(MergedDocType recordType) {
  if (!recordType.isRecordType) return null;
  for (final section in recordType.sections) {
    if (section.id == verificationMatrixKey) return section;
  }
  return null;
}

/// The most characters one item may hold when no layer sets `max_item_chars`.
const defaultMaxItemChars = 600;

/// A language key mapped to a sentence cap, a whole number of 1 or more.
///
/// Every map holds `default`, which a language with no entry of its own takes.
final class SentenceCaps {
  const new(this.entries);

  /// The cap of each language key.
  final Map<String, int> entries;

  /// Returns the cap of [language], else the `default` cap.
  int capFor(String language) =>
      entries[language] ??
      entries[_defaultLanguage] ??
      (throw StateError('a sentence cap map holds no $_defaultLanguage'));

  /// Returns these caps with each entry of [upper] replacing the same entry.
  SentenceCaps mergedWith(Map<String, int>? upper) =>
      upper == null ? this : SentenceCaps({...entries, ...upper});

  /// Returns the JSON object of every language key and its cap.
  Map<String, Object> toJson() => {...entries};

  static const _defaultLanguage = 'default';
}

/// The most words of one sentence when no layer sets `max_sentence_words`.
const builtInSentenceWords = SentenceCaps({'default': 25, 'ko': 17});

/// The most characters of one sentence in a script with no spaces when no
/// layer sets `max_sentence_chars`.
const builtInSentenceChars = SentenceCaps({
  'default': 100,
  'th': 100,
  'ja': 60,
  'zh': 45,
});

/// The language keys `max_sentence_words` takes.
const sentenceWordLanguages = {'default', 'ko', 'ar', 'he', 'hi', 'el'};

/// The language keys `max_sentence_chars` takes.
const sentenceCharLanguages = {'default', 'th', 'lo', 'km', 'my', 'zh', 'ja'};

/// The doc-level lint settings of a merged doc type.
///
/// A null limit or word list means no layer defines it.
final class MergedLint {
  const new({
    this.maxChars,
    this.maxLines,
    this.maxItemChars,
    this.bannedWords,
    this.allowedWords,
    this.bannedPatterns,
    this.requiredFieldGroups,
    this.maxSentenceWords,
    this.maxSentenceChars,
    this.traceNoteLast,
    this.titleNoNumber,
  });

  /// The doc-level character limit.
  final int? maxChars;

  /// The doc-level line ceiling.
  final int? maxLines;

  /// The most characters one item may hold, when a layer sets it.
  final int? maxItemChars;

  /// The most characters one item may hold: [maxItemChars], else the default.
  int get itemCharLimit => maxItemChars ?? defaultMaxItemChars;

  /// The banned words.
  final List<String>? bannedWords;

  /// The allowed words.
  final List<String>? allowedWords;

  /// The banned patterns, merged by `id`.
  final List<PatternEntry>? bannedPatterns;

  /// The groups of fields a doc must carry at least one of each.
  final List<List<String>>? requiredFieldGroups;

  /// The word caps after the merge, built-in entries included; null when no
  /// layer writes `max_sentence_words`.
  final SentenceCaps? maxSentenceWords;

  /// The word caps `check` applies: [maxSentenceWords], else the built-in ones.
  SentenceCaps get sentenceWordCaps => maxSentenceWords ?? builtInSentenceWords;

  /// The character caps after the merge, built-in entries included; null when
  /// no layer writes `max_sentence_chars`.
  final SentenceCaps? maxSentenceChars;

  /// The character caps `check` applies: [maxSentenceChars], else the built-in
  /// ones.
  SentenceCaps get sentenceCharCaps => maxSentenceChars ?? builtInSentenceChars;

  /// Whether a trace note must close its item; null when no layer sets it.
  final bool? traceNoteLast;

  /// Whether a trace note must close its item: [traceNoteLast], else `true`.
  bool get isTraceNoteLast => traceNoteLast ?? true;

  /// Whether a digit in the `# ` title line is a finding; null when no layer
  /// sets it.
  final bool? titleNoNumber;

  /// Returns a copy with each non-null argument replacing its property.
  MergedLint copyWith({
    int? maxChars,
    int? maxLines,
    int? maxItemChars,
    List<String>? bannedWords,
    List<String>? allowedWords,
    List<PatternEntry>? bannedPatterns,
    List<List<String>>? requiredFieldGroups,
    SentenceCaps? maxSentenceWords,
    SentenceCaps? maxSentenceChars,
    bool? traceNoteLast,
    bool? titleNoNumber,
  }) => MergedLint(
    maxChars: maxChars ?? this.maxChars,
    maxLines: maxLines ?? this.maxLines,
    maxItemChars: maxItemChars ?? this.maxItemChars,
    bannedWords: bannedWords ?? this.bannedWords,
    allowedWords: allowedWords ?? this.allowedWords,
    bannedPatterns: bannedPatterns ?? this.bannedPatterns,
    requiredFieldGroups: requiredFieldGroups ?? this.requiredFieldGroups,
    maxSentenceWords: maxSentenceWords ?? this.maxSentenceWords,
    maxSentenceChars: maxSentenceChars ?? this.maxSentenceChars,
    traceNoteLast: traceNoteLast ?? this.traceNoteLast,
    titleNoNumber: titleNoNumber ?? this.titleNoNumber,
  );

  /// Returns the JSON object of this lint with only the keys set.
  ///
  /// The object is empty when no layer writes a lint key.
  Map<String, Object> toJson() => {
    'maxChars': ?maxChars,
    'maxLines': ?maxLines,
    'maxItemChars': ?maxItemChars,
    'bannedWords': ?bannedWords,
    'allowedWords': ?allowedWords,
    'bannedPatterns': ?bannedPatterns?.map((p) => p.toJson()).toList(),
    'requiredFieldGroups': ?requiredFieldGroups,
    'maxSentenceWords': ?maxSentenceWords?.toJson(),
    'maxSentenceChars': ?maxSentenceChars?.toJson(),
    'traceNoteLast': ?traceNoteLast,
    'titleNoNumber': ?titleNoNumber,
  };
}

/// A doc type with its layers folded into one, disabled entries dropped.
final class MergedDocType {
  const new({
    required this.id,
    required this.fields,
    required this.sections,
    required this.lint,
    required this.files,
    this.description,
    this.parent,
    this.extendsId,
    this.extendsChain = const [],
    this.path,
    this.maxDepth,
    this.isPerTarget = false,
    this.nestedPaths,
    this.bundle,
    this.bundleRefs,
    this.summaryFor,
    this.generators,
    this.reference,
    this.pack,
    this.disabledFieldIds = const {},
    this.disabledSectionIds = const {},
  });

  /// The doc type id.
  final String id;

  /// The ids of fields a lower layer defined and a layer then disabled.
  ///
  /// A later `disabled: true` on one of them leaves the doc type as it is.
  final Set<String> disabledFieldIds;

  /// The ids of sections a lower layer defined and a layer then disabled.
  ///
  /// A later `disabled: true` on one of them leaves the doc type as it is.
  final Set<String> disabledSectionIds;

  /// What the doc type is for.
  final String? description;

  /// The id of the doc type this one nests under.
  final String? parent;

  /// The id of the doc type this one builds on.
  final String? extendsId;

  /// The ids this doc type builds on, nearest target first; empty without
  /// `extends`.
  final List<String> extendsChain;

  /// Whether this doc type is [docTypeId] or builds on it.
  bool buildsOn(String docTypeId) =>
      id == docTypeId || extendsChain.contains(docTypeId);

  /// The doc path pattern.
  final String? path;

  /// How many more times the doc type's own folder segment may repeat; null
  /// when no layer sets it.
  final int? maxDepth;

  /// Whether the doc type reads its patterns once per target.
  final bool isPerTarget;

  /// Whether the doc type's own folder segment may repeat.
  bool get nests => (maxDepth ?? 0) > 0;

  /// One path pattern per depth, from 0 to the nesting type's `max_depth`;
  /// null when the doc type's path holds no nesting segment.
  ///
  /// A `MergedSet` derives it, so [copyWith] never carries it over.
  final List<String>? nestedPaths;

  /// The path patterns a doc of this type matches: [nestedPaths], else [path],
  /// else none.
  List<String> get paths => nestedPaths ?? [?path];

  /// The bundle modes the doc type takes part in; null when no layer sets it.
  final List<String>? bundle;

  /// Whether the bundle join of this doc type goes to the refs file of an
  /// `implement` or `design` bundle `--out` writes; null when no layer sets it.
  final bool? bundleRefs;

  /// The doc type ids of the bundle targets whose bundles print this doc type
  /// in summary; null when no layer sets it.
  final List<String>? summaryFor;

  /// Whether a bundle whose target has the doc type [targetTypeId] prints a
  /// cited doc of this type in summary, not as its naming line alone.
  ///
  /// A null [targetTypeId] stands for a target with no doc type.
  bool printsSummaryFor(String? targetTypeId) =>
      summaryFor == null ||
      (targetTypeId != null && summaryFor!.contains(targetTypeId));

  /// The generated-block kinds the doc type lists; null when no layer sets it.
  ///
  /// Null differs from empty: a plain list merges only over null.
  final List<String>? generators;

  /// The generated-block kinds the doc type lists, empty when none is set.
  List<String> get listedGenerators => generators ?? const [];

  /// The enabled fields, built-ins first.
  final List<MergedField> fields;

  /// Whether this is the record doc type, the one holding a `record_status`
  /// field; every rule on records finds it by that field alone.
  bool get isRecordType => fields.any((f) => f.type == FieldType.recordStatus);

  /// The enabled sections in merged order.
  final List<MergedSection> sections;

  /// The doc-level lint settings.
  final MergedLint lint;

  /// The cited sources; null when no layer defines the list.
  final List<ReferenceEntry>? reference;

  /// The pack that supplied the doc type.
  final String? pack;

  /// The layer files that wrote this doc type, lowest layer first.
  final List<String> files;

  /// Returns a copy with each non-null argument replacing its property.
  MergedDocType copyWith({
    String? description,
    String? parent,
    String? extendsId,
    List<String>? extendsChain,
    String? path,
    int? maxDepth,
    bool? isPerTarget,
    List<String>? nestedPaths,
    List<String>? bundle,
    bool? bundleRefs,
    List<String>? summaryFor,
    List<String>? generators,
    List<MergedField>? fields,
    List<MergedSection>? sections,
    MergedLint? lint,
    List<ReferenceEntry>? reference,
    String? pack,
    List<String>? files,
    Set<String>? disabledFieldIds,
    Set<String>? disabledSectionIds,
  }) => MergedDocType(
    id: id,
    description: description ?? this.description,
    parent: parent ?? this.parent,
    extendsId: extendsId ?? this.extendsId,
    extendsChain: extendsChain ?? this.extendsChain,
    path: path ?? this.path,
    maxDepth: maxDepth ?? this.maxDepth,
    isPerTarget: isPerTarget ?? this.isPerTarget,
    nestedPaths: nestedPaths,
    bundle: bundle ?? this.bundle,
    bundleRefs: bundleRefs ?? this.bundleRefs,
    summaryFor: summaryFor ?? this.summaryFor,
    generators: generators ?? this.generators,
    fields: fields ?? this.fields,
    sections: sections ?? this.sections,
    lint: lint ?? this.lint,
    reference: reference ?? this.reference,
    pack: pack ?? this.pack,
    files: files ?? this.files,
    disabledFieldIds: disabledFieldIds ?? this.disabledFieldIds,
    disabledSectionIds: disabledSectionIds ?? this.disabledSectionIds,
  );

  /// Returns the JSON object of the merged schema with only the keys set.
  ///
  /// Keys follow the s02 `specstone guide <type> --json` order; `lint` is
  /// absent when no layer sets a limit or a word list.
  Map<String, Object> toJson() {
    final lintJson = lint.toJson();
    return {
      'id': id,
      'description': ?description,
      'parent': ?parent,
      'extends': ?extendsId,
      'path': ?path,
      'maxDepth': ?maxDepth,
      if (isPerTarget) 'perTarget': true,
      'bundle': ?bundle,
      'bundleRefs': ?bundleRefs,
      'summaryFor': ?summaryFor,
      'fields': [for (final field in fields) field.toJson()],
      'sections': [for (final section in sections) section.toJson()],
      if (lintJson.isNotEmpty) 'lint': lintJson,
      if (reference != null)
        'reference': [for (final entry in reference!) entry.toJson()],
    };
  }

  /// Returns the writing guide, each block set off by a blank line.
  ///
  /// The description and the doc-level banned words come first, then each
  /// section's header, description, own banned words, and template, then the
  /// `Guide sources:` block of [reference]. A banned word list drops the
  /// allowed words that apply there, as `check` does; a description, word
  /// list, template, or [reference] list left empty adds no block.
  String renderGuide() {
    final docAllowed = lint.allowedWords ?? const <String>[];
    final sources = reference ?? const <ReferenceEntry>[];
    final blocks = <String>[
      ?_trimmedOrNull(description),
      ?_bannedWordsLine(lint.bannedWords, allowed: docAllowed),
      for (final section in sections) ...[
        '## ${section.header}',
        ?_trimmedOrNull(section.description),
        ?_bannedWordsLine(
          section.bannedWords,
          allowed: [...docAllowed, ...?section.allowedWords],
          linePrefix: section.linePrefix,
        ),
        ?_templateBlock(section.template),
      ],
      if (sources.isNotEmpty)
        ['Guide sources:', ...sources.map(referenceSourceLine)].join('\n'),
    ];
    return blocks.isEmpty ? '' : '${blocks.join('\n\n')}\n';
  }

  static final _backtickRun = RegExp('`+');

  /// The shortest fence a markdown code block takes.
  static const _minFence = 3;

  /// Returns the `Banned words:` line of [words] not in [allowed], or null
  /// when none is left.
  ///
  /// A [linePrefix] names the lines the words apply on.
  static String? _bannedWordsLine(
    List<String>? words, {
    required List<String> allowed,
    String? linePrefix,
  }) {
    final shown = [
      for (final word in {...?words})
        if (!allowed.contains(word)) '`$word`',
    ];
    if (shown.isEmpty) return null;
    final where = linePrefix == null ? '' : ' on `$linePrefix` lines';
    return 'Banned words$where: ${shown.join(', ')}';
  }

  /// Returns [template] as a `Template:` line and a markdown code block, or
  /// null when it is empty.
  ///
  /// The fence is one backtick longer than the longest backtick run inside,
  /// so a fence the template holds never closes the block.
  static String? _templateBlock(String? template) {
    final body = _trimmedOrNull(template);
    if (body == null) return null;
    final longestRun = _backtickRun
        .allMatches(body)
        .fold(0, (longest, run) => max(longest, run.end - run.start));
    final fence = '`' * max(_minFence, longestRun + 1);
    return 'Template:\n${fence}markdown\n$body\n$fence';
  }

  /// Returns [text] without trailing whitespace, or null when nothing is left.
  static String? _trimmedOrNull(String? text) {
    final trimmed = text?.trimRight();
    return trimmed == null || trimmed.trim().isEmpty ? null : trimmed;
  }
}
