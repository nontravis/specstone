import 'dart:math';

import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/pattern_entry.dart';
import 'package:specstone_core/src/templates/reference_entry.dart';

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
    this.bannedPatterns,
    this.requiredPatterns,
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

  /// The section's own banned patterns, merged by `id`; null when no layer
  /// sets them.
  final List<PatternEntry>? bannedPatterns;

  /// The section's own required patterns, merged by `id`; null when no layer
  /// sets them.
  final List<PatternEntry>? requiredPatterns;

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
    List<PatternEntry>? bannedPatterns,
    List<PatternEntry>? requiredPatterns,
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
    bannedPatterns: bannedPatterns ?? this.bannedPatterns,
    requiredPatterns: requiredPatterns ?? this.requiredPatterns,
  );

  /// Returns the JSON object of this section with only the keys set.
  ///
  /// `required` prints only when true; `lint` is absent when no lint key is
  /// set.
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
    };
  }
}

/// The most characters one item may hold when no layer sets `max_item_chars`.
const defaultMaxItemChars = 600;

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

  /// Returns a copy with each non-null argument replacing its property.
  MergedLint copyWith({
    int? maxChars,
    int? maxLines,
    int? maxItemChars,
    List<String>? bannedWords,
    List<String>? allowedWords,
    List<PatternEntry>? bannedPatterns,
    List<List<String>>? requiredFieldGroups,
  }) => MergedLint(
    maxChars: maxChars ?? this.maxChars,
    maxLines: maxLines ?? this.maxLines,
    maxItemChars: maxItemChars ?? this.maxItemChars,
    bannedWords: bannedWords ?? this.bannedWords,
    allowedWords: allowedWords ?? this.allowedWords,
    bannedPatterns: bannedPatterns ?? this.bannedPatterns,
    requiredFieldGroups: requiredFieldGroups ?? this.requiredFieldGroups,
  );

  /// Returns the JSON object of this lint with only the keys set.
  ///
  /// The object is empty when no layer defines a limit or a word list.
  Map<String, Object> toJson() => {
    'maxChars': ?maxChars,
    'maxLines': ?maxLines,
    'maxItemChars': ?maxItemChars,
    'bannedWords': ?bannedWords,
    'allowedWords': ?allowedWords,
    'bannedPatterns': ?bannedPatterns?.map((p) => p.toJson()).toList(),
    'requiredFieldGroups': ?requiredFieldGroups,
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
    this.path,
    this.maxDepth,
    this.isPerTarget = false,
    this.nestedPaths,
    this.bundle,
    this.generators,
    this.reference,
    this.pack,
  });

  /// The doc type id.
  final String id;

  /// What the doc type is for.
  final String? description;

  /// The id of the doc type this one nests under.
  final String? parent;

  /// The id of the doc type this one builds on.
  final String? extendsId;

  /// The doc path pattern.
  final String? path;

  /// How many more times the doc type's own folder segment may repeat; null
  /// when no layer sets it.
  final int? maxDepth;

  /// Whether the doc type reads its patterns once per target (INV-30).
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

  /// The generated-block kinds the doc type lists; null when no layer sets it.
  ///
  /// Null differs from empty: a plain list merges only over null (PD17).
  final List<String>? generators;

  /// The generated-block kinds the doc type lists, empty when none is set.
  List<String> get listedGenerators => generators ?? const [];

  /// The enabled fields, built-ins first.
  final List<MergedField> fields;

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
    String? path,
    int? maxDepth,
    bool? isPerTarget,
    List<String>? nestedPaths,
    List<String>? bundle,
    List<String>? generators,
    List<MergedField>? fields,
    List<MergedSection>? sections,
    MergedLint? lint,
    List<ReferenceEntry>? reference,
    String? pack,
    List<String>? files,
  }) => MergedDocType(
    id: id,
    description: description ?? this.description,
    parent: parent ?? this.parent,
    extendsId: extendsId ?? this.extendsId,
    path: path ?? this.path,
    maxDepth: maxDepth ?? this.maxDepth,
    isPerTarget: isPerTarget ?? this.isPerTarget,
    nestedPaths: nestedPaths,
    bundle: bundle ?? this.bundle,
    generators: generators ?? this.generators,
    fields: fields ?? this.fields,
    sections: sections ?? this.sections,
    lint: lint ?? this.lint,
    reference: reference ?? this.reference,
    pack: pack ?? this.pack,
    files: files ?? this.files,
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
        ['Guide sources:', ...sources.map(_sourceLine)].join('\n'),
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

  /// Returns the guide line of [entry]: `- <title>[, <locator>][: <target>]`,
  /// where the target is its url, file, or doc.
  static String _sourceLine(ReferenceEntry entry) {
    final locator = entry.locator;
    final target = entry.url ?? entry.file ?? entry.doc;
    return '- ${entry.title}'
        '${locator == null ? '' : ', $locator'}'
        '${target == null ? '' : ': $target'}';
  }

  /// Returns [text] without trailing whitespace, or null when nothing is left.
  static String? _trimmedOrNull(String? text) {
    final trimmed = text?.trimRight();
    return trimmed == null || trimmed.trim().isEmpty ? null : trimmed;
  }
}
