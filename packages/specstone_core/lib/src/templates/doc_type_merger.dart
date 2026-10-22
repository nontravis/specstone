import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/template_fault.dart';

/// The four fields every doc type carries below its lowest layer (INV-20).
const _builtInFields = <MergedField>[
  MergedField(id: 'slug', type: FieldType.string, list: true),
  MergedField(
    id: 'status',
    type: FieldType.enumType,
    enumValues: ['planned', 'implemented', 'deprecated'],
  ),
  MergedField(id: 'draft', type: FieldType.boolean),
  MergedField(id: 'reference', type: FieldType.docRef, list: true),
];

/// Folds sparse doc-type layers onto a base, matching entries by id.
final class DocTypeMerger {
  const new();

  /// Returns the empty doc type [id] holding only the built-in fields.
  MergedDocType builtInBase(String id) => MergedDocType(
    id: id,
    fields: _builtInFields,
    sections: const [],
    lint: const MergedLint(),
    files: const [],
  );

  /// Returns [base] with [layer] applied on top.
  ///
  /// Throws `override_id_not_found` for an entry that cannot add or override,
  /// and `locked_field_disabled` for a layer that breaks a built-in field or
  /// clears a parent the base has.
  MergedDocType apply(MergedDocType base, DocTypeLayer layer) {
    final parent = _mergeParent(base, layer);
    return base.copyWith(
      description: layer.description,
      parent: parent,
      extendsId: layer.extendsId,
      path: layer.path,
      fields: _mergeFields(base.fields, layer),
      sections: _mergeSections(base.sections, layer),
      files: [...base.files, layer.file],
    );
  }

  String? _mergeParent(MergedDocType base, DocTypeLayer layer) {
    if (!layer.writesParent) return base.parent;
    if (layer.parent == null && base.parent != null) {
      throw TemplateFault(
        FaultCode.lockedFieldDisabled,
        'a layer cannot clear the parent of a doc type',
        file: layer.file,
        key: 'parent',
      );
    }
    return layer.parent;
  }

  List<MergedField> _mergeFields(List<MergedField> base, DocTypeLayer layer) {
    final fields = [...base];
    for (final entry in layer.fields) {
      final index = fields.indexWhere((f) => f.id == entry.id);
      if (index == -1) {
        final type = entry.type;
        if (entry.disabled || type == null) {
          throw _notFound(layer, 'fields.${entry.id}');
        }
        fields.add(
          MergedField(
            id: entry.id,
            type: type,
            list: entry.list ?? false,
            required: entry.required ?? false,
            enumValues: entry.enumValues,
            docTypes: entry.docTypes,
            description: entry.description,
          ),
        );
        continue;
      }
      final current = fields[index];
      if (_isBuiltIn(current.id)) _checkLocked(current, entry, layer);
      if (entry.disabled) {
        fields.removeAt(index);
        continue;
      }
      fields[index] = current.copyWith(
        type: entry.type,
        list: entry.list,
        required: entry.required,
        enumValues: entry.enumValues,
        docTypes: entry.docTypes,
        description: entry.description,
      );
    }
    return fields;
  }

  List<MergedSection> _mergeSections(
    List<MergedSection> base,
    DocTypeLayer layer,
  ) {
    final sections = [...base];
    for (final entry in layer.sections) {
      final index = sections.indexWhere((s) => s.id == entry.id);
      if (index == -1) {
        final header = entry.header;
        if (entry.disabled || header == null) {
          throw _notFound(layer, 'sections.${entry.id}');
        }
        sections.add(
          MergedSection(
            id: entry.id,
            header: header,
            prefixId: entry.prefixId,
            required: entry.required ?? false,
            description: entry.description,
            template: entry.template,
            maxChars: entry.lint?.maxChars,
            maxLines: entry.lint?.maxLines,
          ),
        );
        continue;
      }
      if (entry.disabled) {
        sections.removeAt(index);
        continue;
      }
      sections[index] = sections[index].copyWith(
        header: entry.header,
        prefixId: entry.prefixId,
        required: entry.required,
        description: entry.description,
        template: entry.template,
        maxChars: entry.lint?.maxChars,
        maxLines: entry.lint?.maxLines,
      );
    }
    return sections;
  }

  bool _isBuiltIn(String id) => _builtInFields.any((f) => f.id == id);

  void _checkLocked(MergedField current, FieldEntry entry, DocTypeLayer layer) {
    final changesType = entry.type != null && entry.type != current.type;
    if (!entry.disabled && !changesType) return;
    throw TemplateFault(
      FaultCode.lockedFieldDisabled,
      'the built-in field ${entry.id} cannot be disabled or change its type',
      file: layer.file,
      key: 'fields.${entry.id}',
    );
  }

  TemplateFault _notFound(DocTypeLayer layer, String key) => TemplateFault(
    FaultCode.overrideIdNotFound,
    'the entry names an id the lower layers do not define and is not '
    'complete enough to add',
    file: layer.file,
    key: key,
  );
}
