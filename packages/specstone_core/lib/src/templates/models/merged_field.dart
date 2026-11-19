import 'package:specstone_core/src/templates/models/field_caps.dart';
import 'package:specstone_core/src/templates/template_fault.dart';

/// The five fields every doc type carries below its lowest layer.
const builtInFields = <MergedField>[
  MergedField(id: 'slug', type: FieldType.string, list: true),
  MergedField(
    id: 'status',
    type: FieldType.enumType,
    enumValues: ['planned', 'implemented', 'deprecated'],
  ),
  MergedField(id: 'draft', type: FieldType.boolean),
  MergedField(id: 'approved', type: FieldType.string),
  MergedField(id: 'reference', type: FieldType.docRef, list: true),
];

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
    PointerRoot? root,
    this.export,
    this.description,
    this.lint,
  }) : pointer = type == FieldType.outputRef ? pointer : null,
       root = type == FieldType.outputRef ? root : null;

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

  /// The folder an `output_ref` field's pointers resolve against; null when no
  /// layer sets it, which reads as `code`, and for any other type.
  final PointerRoot? root;

  /// Whether the field joins an export; null when no layer sets it.
  final bool? export;

  /// Whether the field joins an export: [export], else `true`.
  bool get exported => export ?? true;

  /// What the field holds.
  final String? description;

  /// The sentence caps of a prose field; null for any other field.
  final FieldCaps? lint;

  /// Whether the field is a prose field, one that sets `lint`.
  bool get isProse => lint != null;

  /// Whether Specstone or the Owner sets the field, so a layer cannot own it.
  bool get isBuiltIn => builtInFields.any((field) => field.id == id);

  /// Returns a copy with each non-null argument replacing its property.
  ///
  /// A list the new type does not use is dropped unless the call writes it:
  /// [enumValues] belongs to `enum` only, [docTypes] to `doc_ref` only, and
  /// [pointer] and [root] to `output_ref` only. [lint] replaces the whole caps
  /// value.
  MergedField copyWith({
    FieldType? type,
    bool? list,
    bool? required,
    List<String>? enumValues,
    List<String>? docTypes,
    PointerKind? pointer,
    PointerRoot? root,
    bool? export,
    String? description,
    FieldCaps? lint,
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
      root: root ?? this.root,
      export: export ?? this.export,
      description: description ?? this.description,
      lint: lint ?? this.lint,
    );
  }

  /// Returns the JSON object of this field with only the keys set.
  ///
  /// `list` and `required` print only when true; `root` and `export` print
  /// only when a layer writes them.
  Map<String, Object> toJson() => {
    'id': id,
    'type': type.wire,
    if (list) 'list': true,
    if (required) 'required': true,
    'enum': ?enumValues,
    'docTypes': ?docTypes,
    'pointer': ?pointer?.wire,
    'root': ?root?.wire,
    'export': ?export,
    'description': ?description,
    'lint': ?lint?.toJson(),
  };
}

/// A field's type; [wire] is the snake_case name the format uses.
enum FieldType {
  string('string'),
  integer('integer'),
  boolean('boolean'),
  date('date'),
  enumType('enum'),
  docRef('doc_ref'),
  outputRef('output_ref'),
  recordStatus('record_status'),
  taskRef('task_ref'),
  sourceRef('source_ref');

  new(this.wire);

  /// The snake_case name the doc-type format uses for this type.
  final String wire;

  /// Returns the type named [wire], or throws `unknown_value` at [prefix]type.
  static FieldType byWire(
    String wire, {
    required String file,
    required String prefix,
  }) {
    final type = values.where((t) => t.wire == wire).firstOrNull;
    if (type != null) return type;
    throw TemplateFault(
      FaultCode.unknownValue,
      'the key type must be one of the ten field types',
      file: file,
      key: '${prefix}type',
    );
  }
}

/// How an `output_ref` field's pointer is matched; [wire] is the format name.
enum PointerKind {
  exact('exact'),
  prefix('prefix'),
  itemExact('item_exact'),
  itemTest('item_test');

  new(this.wire);

  /// The name the doc-type format uses for this pointer kind.
  final String wire;

  /// Returns the kind named [wire], or throws `unknown_value`.
  ///
  /// The fault key is [prefix]pointer.
  static PointerKind byWire(
    String wire, {
    required String file,
    required String prefix,
  }) {
    final kind = values.where((k) => k.wire == wire).firstOrNull;
    if (kind != null) return kind;
    throw _unknownPointer(file: file, prefix: prefix);
  }

  /// Returns the kind a field wrote as [value].
  ///
  /// Throws `unknown_value` at [prefix]pointer when [value] is not a string
  /// naming a kind; a YAML value other than a string never names one.
  static PointerKind read(
    Object? value, {
    required String file,
    required String prefix,
  }) {
    if (value is String) return byWire(value, file: file, prefix: prefix);
    throw _unknownPointer(file: file, prefix: prefix);
  }
}

/// The folder an `output_ref` field's pointers resolve against; [wire] is the
/// format name.
enum PointerRoot {
  code('code'),
  project('project');

  new(this.wire);

  /// The name the doc-type format uses for this root.
  final String wire;

  /// Returns the root a field wrote as [value].
  ///
  /// Throws `unknown_value` at [prefix]root when [value] is not a string
  /// naming a root.
  static PointerRoot read(
    Object? value, {
    required String file,
    required String prefix,
  }) {
    final root = values.where((r) => r.wire == value).firstOrNull;
    if (root != null) return root;
    throw TemplateFault(
      FaultCode.unknownValue,
      'the key root must be code or project',
      file: file,
      key: '${prefix}root',
    );
  }
}

TemplateFault _unknownPointer({required String file, required String prefix}) =>
    TemplateFault(
      FaultCode.unknownValue,
      'the key pointer must be exact, prefix, item_exact, or item_test',
      file: file,
      key: '${prefix}pointer',
    );
