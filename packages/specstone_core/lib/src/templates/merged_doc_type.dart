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
    this.description,
  });

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

  /// What the field holds.
  final String? description;

  /// Returns a copy with each non-null argument replacing its property.
  ///
  /// A list the new type does not use is dropped unless the call writes it:
  /// [enumValues] belongs to `enum` only, [docTypes] to `doc_ref` only.
  MergedField copyWith({
    FieldType? type,
    bool? list,
    bool? required,
    List<String>? enumValues,
    List<String>? docTypes,
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
      description: description ?? this.description,
    );
  }
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

  /// Returns a copy with each non-null argument replacing its property.
  MergedSection copyWith({
    String? header,
    String? prefixId,
    bool? required,
    String? description,
    String? template,
    int? maxChars,
    int? maxLines,
  }) => MergedSection(
    id: id,
    header: header ?? this.header,
    prefixId: prefixId ?? this.prefixId,
    required: required ?? this.required,
    description: description ?? this.description,
    template: template ?? this.template,
    maxChars: maxChars ?? this.maxChars,
    maxLines: maxLines ?? this.maxLines,
  );
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
    fields: fields ?? this.fields,
    sections: sections ?? this.sections,
    lint: lint ?? this.lint,
    reference: reference ?? this.reference,
    pack: pack ?? this.pack,
    files: files ?? this.files,
  );
}
