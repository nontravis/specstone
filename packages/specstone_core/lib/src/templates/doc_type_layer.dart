import 'package:specstone_core/src/templates/reference_entry.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/yaml_reader.dart';
import 'package:yaml/yaml.dart';

/// The layer a doc-type file sits in: shipped, personal, or project.
enum LayerKind { shipped, personal, project }

/// A field's type; [wire] is the snake_case name the format uses (INV-13).
enum FieldType {
  string('string'),
  integer('integer'),
  boolean('boolean'),
  date('date'),
  enumType('enum'),
  docRef('doc_ref'),
  outputRef('output_ref');

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
      'the key type must be one of the seven field types',
      file: file,
      key: '${prefix}type',
    );
  }
}

/// A word list as written: a whole list, or `add`/`remove` changes.
sealed class ListWrite<T>;

/// A whole list written in the layer that first defines it.
final class PlainList<T> extends ListWrite<T> {
  new(this.items);

  /// The written list.
  final List<T> items;
}

/// An `add`/`remove` change to a list a lower layer defines.
final class ListChange<T> extends ListWrite<T> {
  new(this.add, this.remove);

  /// The entries added to the lower list.
  final List<T> add;

  /// The entries removed from the lower list.
  final List<String> remove;
}

/// One frontmatter field of a doc type, as one layer writes it.
///
/// Every field but [id] and [disabled] is nullable so an overriding layer can
/// write a field sparsely.
final class FieldEntry {
  new({
    required this.id,
    this.type,
    this.list,
    this.required,
    this.enumValues,
    this.docTypes,
    this.description,
    required this.disabled,
  });

  /// The field id; the merge key.
  final String id;

  /// The field type, when this layer writes it.
  final FieldType? type;

  /// Whether the field is a list of [type], when written.
  final bool? list;

  /// Whether a doc must carry the field, when written.
  final bool? required;

  /// The allowed values of an `enum` field, when written.
  final List<String>? enumValues;

  /// The target doc type ids of a `doc_ref` field, when written.
  final List<String>? docTypes;

  /// What the field holds, when written.
  final String? description;

  /// Whether the field is turned off by this layer.
  final bool disabled;
}

/// A section's own lint limits, replacing the doc-level values.
final class SectionLint {
  new({this.maxChars, this.maxLines});

  /// The section's character limit, when written.
  final int? maxChars;

  /// The section's line ceiling, when written.
  final int? maxLines;
}

/// One guide section of a doc type, as one layer writes it.
///
/// Every field but [id] and [disabled] is nullable for sparse overrides.
final class SectionEntry {
  new({
    required this.id,
    this.prefixId,
    this.required,
    this.header,
    this.description,
    this.template,
    this.lint,
    this.after,
    required this.disabled,
  });

  /// The section id; the merge key.
  final String id;

  /// The section's numbering prefix, when written.
  final String? prefixId;

  /// Whether a doc must carry the section, when written.
  final bool? required;

  /// The section's heading, when written.
  final String? header;

  /// What the section holds, when written.
  final String? description;

  /// The section's body template, when written.
  final String? template;

  /// The section's own lint limits, when written.
  final SectionLint? lint;

  /// The section this one follows in an adding layer, when written.
  final String? after;

  /// Whether the section is turned off by this layer.
  final bool disabled;
}

/// A doc type's doc-level lint block, as one layer writes it.
final class LintLayer {
  new({this.maxChars, this.maxLines, this.bannedWords, this.allowedWords});

  /// The doc-level character limit, when written.
  final int? maxChars;

  /// The doc-level line ceiling, when written.
  final int? maxLines;

  /// The banned word list, plain or as changes, when written.
  final ListWrite<String>? bannedWords;

  /// The allowed word list, plain or as changes, when written.
  final ListWrite<String>? allowedWords;
}

/// One layer's view of a doc type, parsed from one doc-type YAML file.
final class DocTypeLayer {
  const new _({
    required this.docTypeId,
    required this.file,
    required this.kind,
    required this.id,
    required this.description,
    required this.writesParent,
    required this.parent,
    required this.extendsId,
    required this.path,
    required this.fields,
    required this.sections,
    required this.lint,
    required this.reference,
  });

  /// Parses one doc-type file; [docTypeId] is the file name without `.yaml`.
  ///
  /// [files] answers whether the layer holds a file at a layer-relative path,
  /// for `reference` checks.
  /// Throws a [TemplateFault] for any format fault.
  static DocTypeLayer parse(
    String text, {
    required String file,
    required String docTypeId,
    required LayerKind kind,
    required LayerFiles files,
  }) {
    final map = readYamlMap(text, file: file);
    checkKeys(map, _topKeys, file: file, format: 'doc-type');
    final id = optionalValue<String>(map, 'id', file: file);
    if (id != null && id != docTypeId) {
      throw TemplateFault(
        FaultCode.docTypeIdMismatch,
        'the key id must equal the file name without .yaml',
        file: file,
        key: 'id',
      );
    }
    final parentWritten = map.keys.contains('parent');
    final lintMap = optionalValue<YamlMap>(map, 'lint', file: file);
    return DocTypeLayer._(
      docTypeId: docTypeId,
      file: file,
      kind: kind,
      id: id,
      description: optionalValue<String>(map, 'description', file: file),
      writesParent: parentWritten,
      parent: optionalValue<String>(map, 'parent', file: file),
      extendsId: optionalValue<String>(map, 'extends', file: file),
      path: optionalValue<String>(map, 'path', file: file),
      fields: _parseFields(map, file: file),
      sections: _parseSections(map, file: file),
      lint: lintMap == null ? null : _parseLint(lintMap, file: file),
      reference: _parseReference(map, file: file, kind: kind, files: files),
    );
  }

  /// The file name without `.yaml`; the doc type id this layer carries.
  final String docTypeId;

  /// The file this layer was parsed from, with `/` separators.
  final String file;

  /// The layer this file sits in.
  final LayerKind kind;

  /// The written `id`, or null when the layer writes none.
  final String? id;

  /// The guide intro, when this layer writes it.
  final String? description;

  /// Whether the layer writes `parent` at all, even with no value.
  final bool writesParent;

  /// The parent doc type id, when written and not cleared.
  final String? parent;

  /// The doc type this one builds on, when written.
  final String? extendsId;

  /// The file pattern, when this layer writes it.
  final String? path;

  /// The fields this layer writes, in file order.
  final List<FieldEntry> fields;

  /// The sections this layer writes, in file order.
  final List<SectionEntry> sections;

  /// The doc-level lint block, when written.
  final LintLayer? lint;

  /// The reference list this layer writes, when written.
  final ListWrite<ReferenceEntry>? reference;
}

/// Reads the `reference` key of [map] as a [ListWrite] of entries.
///
/// A doc-type file sits at the top of its layer folder, so its entries
/// resolve `file` links against an empty template folder.
ListWrite<ReferenceEntry>? _parseReference(
  YamlMap map, {
  required String file,
  required LayerKind kind,
  required LayerFiles files,
}) {
  final value = map['reference'];
  return switch (value) {
    null => null,
    final YamlList list => PlainList<ReferenceEntry>([
      for (var i = 0; i < list.length; i++)
        ReferenceEntry.parse(
          _entryMap(list[i], 'reference[$i]', file: file),
          file: file,
          key: 'reference[$i]',
          kind: kind,
          templateFolder: '',
          files: files,
        ),
    ]),
    final YamlMap changeMap => _referenceChange(
      changeMap,
      file: file,
      kind: kind,
      files: files,
    ),
    _ => throw TemplateFault(
      FaultCode.unknownValue,
      'the key reference must be a list or a mapping of add and remove',
      file: file,
      key: 'reference',
    ),
  };
}

ListChange<ReferenceEntry> _referenceChange(
  YamlMap map, {
  required String file,
  required LayerKind kind,
  required LayerFiles files,
}) {
  checkKeys(
    map,
    const {'add', 'remove'},
    file: file,
    format: 'doc-type',
    prefix: 'reference.',
  );
  final add = optionalValue<YamlList>(
    map,
    'add',
    file: file,
    prefix: 'reference.',
  );
  final remove = optionalValue<YamlList>(
    map,
    'remove',
    file: file,
    prefix: 'reference.',
  );
  return ListChange<ReferenceEntry>(
    add == null
        ? <ReferenceEntry>[]
        : [
            for (var i = 0; i < add.length; i++)
              ReferenceEntry.parse(
                _entryMap(add[i], 'reference.add[$i]', file: file),
                file: file,
                key: 'reference.add[$i]',
                kind: kind,
                templateFolder: '',
                files: files,
              ),
          ],
    remove == null
        ? <String>[]
        : _stringsOf(remove, 'remove', file: file, prefix: 'reference.'),
  );
}

/// Whether [name] is a doc-type file: a top-level `<id>.yaml`, not `pack.yaml`.
bool isDocTypeFileName(String name) {
  if (name.contains('/')) return false;
  if (name == 'pack.yaml') return false;
  return name.endsWith('.yaml');
}

const _topKeys = {
  'id',
  'description',
  'path',
  'parent',
  'extends',
  'fields',
  'sections',
  'lint',
  'reference',
};

const _fieldKeys = {
  'id',
  'type',
  'list',
  'enum',
  'doc_types',
  'required',
  'description',
  'disabled',
};

const _sectionKeys = {
  'id',
  'prefix_id',
  'required',
  'header',
  'description',
  'template',
  'lint',
  'disabled',
  'after',
};

const _docLintKeys = {
  'max_chars',
  'max_lines',
  'banned_words',
  'allowed_words',
};

const _sectionLintKeys = {'max_chars', 'max_lines'};

List<FieldEntry> _parseFields(YamlMap map, {required String file}) {
  final entries = optionalValue<YamlList>(map, 'fields', file: file);
  if (entries == null) return <FieldEntry>[];
  return [
    for (var i = 0; i < entries.length; i++)
      _parseField(
        _entryMap(entries[i], 'fields[$i]', file: file),
        index: i,
        file: file,
      ),
  ];
}

FieldEntry _parseField(
  YamlMap entry, {
  required int index,
  required String file,
}) {
  final id = requireValue<String>(
    entry,
    'id',
    file: file,
    prefix: 'fields[$index].',
  );
  checkKeys(
    entry,
    _fieldKeys,
    file: file,
    format: 'doc-type',
    prefix: 'fields.$id.',
  );
  final prefix = 'fields.$id.';
  final type = _optionalFieldType(entry, file: file, prefix: prefix);
  if (type == FieldType.enumType) {
    requireValue<YamlList>(entry, 'enum', file: file, prefix: prefix);
  }
  final enumList = optionalValue<YamlList>(
    entry,
    'enum',
    file: file,
    prefix: prefix,
  );
  final docTypesList = optionalValue<YamlList>(
    entry,
    'doc_types',
    file: file,
    prefix: prefix,
  );
  return FieldEntry(
    id: id,
    type: type,
    list: optionalValue<bool>(entry, 'list', file: file, prefix: prefix),
    required: optionalValue<bool>(
      entry,
      'required',
      file: file,
      prefix: prefix,
    ),
    enumValues: enumList == null
        ? null
        : _stringsOf(enumList, 'enum', file: file, prefix: prefix),
    docTypes: docTypesList == null
        ? null
        : _stringsOf(docTypesList, 'doc_types', file: file, prefix: prefix),
    description: optionalValue<String>(
      entry,
      'description',
      file: file,
      prefix: prefix,
    ),
    disabled:
        optionalValue<bool>(entry, 'disabled', file: file, prefix: prefix) ??
        false,
  );
}

List<SectionEntry> _parseSections(YamlMap map, {required String file}) {
  final entries = optionalValue<YamlList>(map, 'sections', file: file);
  if (entries == null) return <SectionEntry>[];
  return [
    for (var i = 0; i < entries.length; i++)
      _parseSection(
        _entryMap(entries[i], 'sections[$i]', file: file),
        index: i,
        file: file,
      ),
  ];
}

SectionEntry _parseSection(
  YamlMap entry, {
  required int index,
  required String file,
}) {
  final id = requireValue<String>(
    entry,
    'id',
    file: file,
    prefix: 'sections[$index].',
  );
  checkKeys(
    entry,
    _sectionKeys,
    file: file,
    format: 'doc-type',
    prefix: 'sections.$id.',
  );
  final prefix = 'sections.$id.';
  final lintMap = optionalValue<YamlMap>(
    entry,
    'lint',
    file: file,
    prefix: prefix,
  );
  return SectionEntry(
    id: id,
    prefixId: optionalValue<String>(
      entry,
      'prefix_id',
      file: file,
      prefix: prefix,
    ),
    required: optionalValue<bool>(
      entry,
      'required',
      file: file,
      prefix: prefix,
    ),
    header: optionalValue<String>(entry, 'header', file: file, prefix: prefix),
    description: optionalValue<String>(
      entry,
      'description',
      file: file,
      prefix: prefix,
    ),
    template: optionalValue<String>(
      entry,
      'template',
      file: file,
      prefix: prefix,
    ),
    lint: lintMap == null
        ? null
        : _parseSectionLint(lintMap, file: file, prefix: prefix),
    after: optionalValue<String>(entry, 'after', file: file, prefix: prefix),
    disabled:
        optionalValue<bool>(entry, 'disabled', file: file, prefix: prefix) ??
        false,
  );
}

LintLayer _parseLint(YamlMap map, {required String file}) {
  checkKeys(map, _docLintKeys, file: file, format: 'doc-type', prefix: 'lint.');
  return LintLayer(
    maxChars: optionalValue<int>(map, 'max_chars', file: file, prefix: 'lint.'),
    maxLines: optionalValue<int>(map, 'max_lines', file: file, prefix: 'lint.'),
    bannedWords: _listWrite(map, 'banned_words', file: file, prefix: 'lint.'),
    allowedWords: _listWrite(map, 'allowed_words', file: file, prefix: 'lint.'),
  );
}

SectionLint _parseSectionLint(
  YamlMap map, {
  required String file,
  required String prefix,
}) {
  checkKeys(
    map,
    _sectionLintKeys,
    file: file,
    format: 'doc-type',
    prefix: '${prefix}lint.',
  );
  return SectionLint(
    maxChars: optionalValue<int>(
      map,
      'max_chars',
      file: file,
      prefix: '${prefix}lint.',
    ),
    maxLines: optionalValue<int>(
      map,
      'max_lines',
      file: file,
      prefix: '${prefix}lint.',
    ),
  );
}

/// Reads the value at [key] as a [PlainList] or a [ListChange].
ListWrite<String>? _listWrite(
  YamlMap map,
  String key, {
  required String file,
  required String prefix,
}) {
  final value = map[key];
  return switch (value) {
    null => null,
    final YamlList list => PlainList<String>(
      _stringsOf(list, key, file: file, prefix: prefix),
    ),
    final YamlMap changeMap => _listChange(
      changeMap,
      key,
      file: file,
      prefix: prefix,
    ),
    _ => throw TemplateFault(
      FaultCode.unknownValue,
      'the key $key must be a list or a mapping of add and remove',
      file: file,
      key: '$prefix$key',
    ),
  };
}

ListChange<String> _listChange(
  YamlMap map,
  String key, {
  required String file,
  required String prefix,
}) {
  checkKeys(
    map,
    const {'add', 'remove'},
    file: file,
    format: 'doc-type',
    prefix: '$prefix$key.',
  );
  final add = optionalValue<YamlList>(
    map,
    'add',
    file: file,
    prefix: '$prefix$key.',
  );
  final remove = optionalValue<YamlList>(
    map,
    'remove',
    file: file,
    prefix: '$prefix$key.',
  );
  return ListChange<String>(
    add == null
        ? <String>[]
        : _stringsOf(add, 'add', file: file, prefix: '$prefix$key.'),
    remove == null
        ? <String>[]
        : _stringsOf(remove, 'remove', file: file, prefix: '$prefix$key.'),
  );
}

/// Returns the entry as a [YamlMap], or throws `unknown_value`.
YamlMap _entryMap(Object? entry, String keyPath, {required String file}) {
  if (entry is YamlMap) return entry;
  throw TemplateFault(
    FaultCode.unknownValue,
    'the entry must be a mapping',
    file: file,
    key: keyPath,
  );
}

List<String> _stringsOf(
  YamlList list,
  String key, {
  required String file,
  required String prefix,
}) {
  return [
    for (final element in list)
      if (element is String)
        element
      else
        throw TemplateFault(
          FaultCode.unknownValue,
          'the key $key must hold only strings',
          file: file,
          key: '$prefix$key',
        ),
  ];
}

FieldType? _optionalFieldType(
  YamlMap map, {
  required String file,
  required String prefix,
}) {
  final wire = optionalValue<String>(map, 'type', file: file, prefix: prefix);
  if (wire == null) return null;
  return FieldType.byWire(wire, file: file, prefix: prefix);
}
