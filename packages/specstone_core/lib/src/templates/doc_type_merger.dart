import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/reference_entry.dart';
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

  /// Returns [base] with [layer] applied on top, entries in file order.
  ///
  /// Throws `override_id_not_found` for an entry that cannot add or override,
  /// `after_id_not_found` for a section whose `after:` names an id the base
  /// built so far lacks, `locked_field_disabled` for a layer that breaks a
  /// built-in field or clears a parent the base has,
  /// `list_override_needs_add_remove` for a plain word or reference list over
  /// one a lower layer defines, `lint_word_not_found` for a removed word the
  /// base lacks, and `reference_title_not_found` for a removed title the base
  /// lacks.
  MergedDocType apply(MergedDocType base, DocTypeLayer layer) {
    final parent = _mergeParent(base, layer);
    return base.copyWith(
      description: layer.description,
      parent: parent,
      extendsId: layer.extendsId,
      path: layer.path,
      fields: _mergeFields(base.fields, layer),
      sections: _mergeSections(base.sections, layer),
      lint: _mergeLint(base.lint, layer),
      reference: _mergeReference(base.reference, layer),
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

  MergedLint _mergeLint(MergedLint base, DocTypeLayer layer) {
    final lint = layer.lint;
    if (lint == null) return base;
    return base.copyWith(
      maxChars: lint.maxChars,
      maxLines: lint.maxLines,
      bannedWords: _mergeList<String>(
        base.bannedWords,
        lint.bannedWords,
        layer,
        key: 'lint.banned_words',
        nameOf: (word) => word,
        notFound: FaultCode.lintWordNotFound,
      ),
      allowedWords: _mergeList<String>(
        base.allowedWords,
        lint.allowedWords,
        layer,
        key: 'lint.allowed_words',
        nameOf: (word) => word,
        notFound: FaultCode.lintWordNotFound,
      ),
    );
  }

  List<ReferenceEntry>? _mergeReference(
    List<ReferenceEntry>? base,
    DocTypeLayer layer,
  ) => _mergeList<ReferenceEntry>(
    base,
    layer.reference,
    layer,
    key: 'reference',
    nameOf: (entry) => entry.title,
    notFound: FaultCode.referenceTitleNotFound,
  );

  /// Returns [base] with [write] applied, or [base] when [write] is null.
  ///
  /// A [PlainList] is accepted only where [base] is null. A [ListChange]
  /// starts from an empty list when [base] is null and must remove only names
  /// [base] holds, else it throws the [notFound] fault.
  List<T>? _mergeList<T>(
    List<T>? base,
    ListWrite<T>? write,
    DocTypeLayer layer, {
    required String key,
    required String Function(T) nameOf,
    required FaultCode notFound,
  }) {
    switch (write) {
      case null:
        return base;
      case PlainList(:final items):
        if (base == null) return items;
        throw TemplateFault(
          FaultCode.listOverrideNeedsAddRemove,
          'a lower layer already defines $key; write add and remove to '
          'change it',
          file: layer.file,
          key: key,
        );
      case ListChange(:final add, :final remove):
        final lower = base ?? <T>[];
        final names = lower.map(nameOf).toSet();
        for (final name in remove) {
          if (names.contains(name)) continue;
          throw TemplateFault(
            notFound,
            'cannot remove $name from $key; no lower layer holds it',
            file: layer.file,
            key: key,
          );
        }
        return [
          for (final item in lower)
            if (!remove.contains(nameOf(item))) item,
          ...add,
        ];
    }
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
        final position = _positionAfter(sections, entry, layer);
        sections.insert(
          position,
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
      final merged = sections[index].copyWith(
        header: entry.header,
        prefixId: entry.prefixId,
        required: entry.required,
        description: entry.description,
        template: entry.template,
        maxChars: entry.lint?.maxChars,
        maxLines: entry.lint?.maxLines,
      );
      if (entry.after == null || entry.after == entry.id) {
        sections[index] = merged;
        continue;
      }
      sections.removeAt(index);
      sections.insert(_positionAfter(sections, entry, layer), merged);
    }
    return sections;
  }

  /// Returns the index right after the section [entry] names, else the end.
  ///
  /// Throws `after_id_not_found` when [entry] names an id [sections] lacks.
  int _positionAfter(
    List<MergedSection> sections,
    SectionEntry entry,
    DocTypeLayer layer,
  ) {
    final after = entry.after;
    if (after == null) return sections.length;
    final index = sections.indexWhere((s) => s.id == after);
    if (index != -1) return index + 1;
    throw TemplateFault(
      FaultCode.afterIdNotFound,
      'the section ${entry.id} follows $after, which the lower layers and '
      'earlier entries do not define',
      file: layer.file,
      key: 'sections.${entry.id}.after',
    );
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
