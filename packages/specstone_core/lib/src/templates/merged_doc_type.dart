import 'package:specstone_core/src/templates/doc_type_layer.dart';
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

  /// The section's own banned words; null when no layer sets them.
  final List<String>? bannedWords;

  /// The section's own allowed words; null when no layer sets them.
  final List<String>? allowedWords;

  /// The prefix each body line starts with; null when no layer sets it.
  final String? linePrefix;

  /// Whether the section is a query section; null when no layer sets it.
  final bool? query;

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
      ).toJson(),
      'linePrefix': ?linePrefix,
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
    };
  }
}

/// The doc-level lint settings of a merged doc type.
///
/// A null limit or word list means no layer defines it.
final class MergedLint {
  const new({
    this.maxChars,
    this.maxLines,
    this.bannedWords,
    this.allowedWords,
  });

  /// The doc-level character limit.
  final int? maxChars;

  /// The doc-level line ceiling.
  final int? maxLines;

  /// The banned words.
  final List<String>? bannedWords;

  /// The allowed words.
  final List<String>? allowedWords;

  /// Returns a copy with each non-null argument replacing its property.
  MergedLint copyWith({
    int? maxChars,
    int? maxLines,
    List<String>? bannedWords,
    List<String>? allowedWords,
  }) => MergedLint(
    maxChars: maxChars ?? this.maxChars,
    maxLines: maxLines ?? this.maxLines,
    bannedWords: bannedWords ?? this.bannedWords,
    allowedWords: allowedWords ?? this.allowedWords,
  );

  /// Returns the JSON object of this lint with only the keys set.
  ///
  /// The object is empty when no layer defines a limit or a word list.
  Map<String, Object> toJson() => {
    'maxChars': ?maxChars,
    'maxLines': ?maxLines,
    'bannedWords': ?bannedWords,
    'allowedWords': ?allowedWords,
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
    this.bundle,
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

  /// The bundle modes the doc type takes part in; null when no layer sets it.
  final List<String>? bundle;

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
    List<String>? bundle,
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
    bundle: bundle ?? this.bundle,
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
      'bundle': ?bundle,
      'fields': [for (final field in fields) field.toJson()],
      'sections': [for (final section in sections) section.toJson()],
      if (lintJson.isNotEmpty) 'lint': lintJson,
      if (reference != null)
        'reference': [for (final entry in reference!) entry.toJson()],
    };
  }

  /// Returns the writing guide: the description, then each section's header
  /// and description, each block set off by a blank line.
  ///
  /// A description with only whitespace adds no block.
  String renderGuide() {
    final blocks = <String>[
      ?_trimmedOrNull(description),
      for (final section in sections) ...[
        '## ${section.header}',
        ?_trimmedOrNull(section.description),
      ],
    ];
    return blocks.isEmpty ? '' : '${blocks.join('\n\n')}\n';
  }

  /// Returns [text] without trailing whitespace, or null when nothing is left.
  static String? _trimmedOrNull(String? text) {
    final trimmed = text?.trimRight();
    return trimmed == null || trimmed.trim().isEmpty ? null : trimmed;
  }
}
