import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/yaml_reader.dart';
import 'package:yaml/yaml.dart';

const _linesKey = 'shared_lines';
const _fieldsKey = 'shared_fields';
const _forDocTypesKey = 'for_doc_types';
const _patternsId = 'patterns';
const Set<String> _lineKeys = {'id', 'text', _forDocTypesKey, 'disabled'};

/// One `shared_lines` entry of a `pack.yaml`, as its file writes it.
///
/// [text] is null when the entry only disables or retargets a lower line.
final class SharedLine {
  new({
    required this.id,
    this.text,
    this.forDocTypes,
    required this.disabled,
    required this.file,
    required this.index,
  });

  /// The id the merge matches lines by.
  final String id;

  /// The one line of guide text, without a line break, when written.
  final String? text;

  /// The doc type ids the line reaches, when written.
  final List<String>? forDocTypes;

  /// Whether this entry turns the line off.
  final bool disabled;

  /// The file the entry was read from.
  final String file;

  /// The position of the entry in its list.
  final int index;
}

/// One `shared_fields` entry of a `pack.yaml`, as its file writes it.
final class SharedField {
  new({
    required this.entry,
    this.forDocTypes,
    required this.file,
    required this.index,
  });

  /// The field as the doc-type format reads it.
  final FieldEntry entry;

  /// The doc type ids the field reaches, when written.
  final List<String>? forDocTypes;

  /// The file the entry was read from.
  final String file;

  /// The position of the entry in its list.
  final int index;

  /// The id the merge matches fields by.
  String get id => entry.id;
}

/// The shared lines and fields one file declares, in file order.
final class SharedEntries {
  const new({required this.lines, required this.fields});

  /// No shared entries.
  static const SharedEntries empty = SharedEntries(lines: [], fields: []);

  /// The `shared_lines` entries.
  final List<SharedLine> lines;

  /// The `shared_fields` entries.
  final List<SharedField> fields;
}

/// Reads `shared_lines` and `shared_fields` from the top-level [map] of [file].
///
/// Checks only what one file shows. The keys of a fault are
/// `shared_lines[<i>].<key>` and `shared_fields[<i>].<key>`. A file that
/// allows no fields ([allowsFields] false) refuses `shared_fields` as
/// `unknown_key`. The caller checks the other top-level keys.
SharedEntries parseSharedEntries(
  YamlMap map, {
  required String file,
  required bool allowsFields,
}) {
  if (!allowsFields && map.containsKey(_fieldsKey)) {
    throw TemplateFault(
      FaultCode.unknownKey,
      'this file defines no key $_fieldsKey',
      file: file,
      key: _fieldsKey,
    );
  }
  return SharedEntries(
    lines: _parseLines(map, file: file),
    fields: _parseFields(map, file: file),
  );
}

List<SharedLine> _parseLines(YamlMap map, {required String file}) {
  final entries = optionalValue<YamlList>(map, _linesKey, file: file);
  if (entries == null) return <SharedLine>[];
  final seen = <String>{};
  return [
    for (final (i, entry) in entries.indexed)
      _parseLine(
        _entryMap(entry, '$_linesKey[$i]', file: file),
        index: i,
        file: file,
        seen: seen,
      ),
  ];
}

SharedLine _parseLine(
  YamlMap entry, {
  required int index,
  required String file,
  required Set<String> seen,
}) {
  final prefix = '$_linesKey[$index].';
  final id = requireValue<String>(entry, 'id', file: file, prefix: prefix);
  checkKeys(entry, _lineKeys, file: file, format: 'pack', prefix: prefix);
  _claimId(seen, id, file: file, key: '${prefix}id');
  final text = optionalValue<String>(entry, 'text', file: file, prefix: prefix);
  return SharedLine(
    id: id,
    text: text == null
        ? null
        : _oneLine(text, file: file, key: '${prefix}text'),
    forDocTypes: _forDocTypes(entry, file: file, prefix: prefix),
    disabled:
        optionalValue<bool>(entry, 'disabled', file: file, prefix: prefix) ??
        false,
    file: file,
    index: index,
  );
}

List<SharedField> _parseFields(YamlMap map, {required String file}) {
  final entries = optionalValue<YamlList>(map, _fieldsKey, file: file);
  if (entries == null) return <SharedField>[];
  final seen = <String>{};
  return [
    for (final (i, entry) in entries.indexed)
      _parseField(
        _entryMap(entry, '$_fieldsKey[$i]', file: file),
        index: i,
        file: file,
        seen: seen,
      ),
  ];
}

SharedField _parseField(
  YamlMap entry, {
  required int index,
  required String file,
  required Set<String> seen,
}) {
  final prefix = '$_fieldsKey[$index].';
  final field = parseFieldEntry(
    entry,
    index: index,
    file: file,
    keyPrefix: _fieldsKey,
    keyByIndex: true,
    extraKeys: const {_forDocTypesKey},
  );
  _checkFieldId(field.id, file: file, key: '${prefix}id');
  if (field.type == FieldType.recordStatus) {
    throw TemplateFault(
      FaultCode.unknownValue,
      'a shared field takes no type ${FieldType.recordStatus.wire}',
      file: file,
      key: '${prefix}type',
    );
  }
  _claimId(seen, field.id, file: file, key: '${prefix}id');
  return SharedField(
    entry: field,
    forDocTypes: _forDocTypes(entry, file: file, prefix: prefix),
    file: file,
    index: index,
  );
}

void _checkFieldId(String id, {required String file, required String key}) {
  final message = switch (id) {
    _patternsId => 'a shared field takes no id $_patternsId',
    _ when builtInFields.any((field) => field.id == id) =>
      'a shared field takes no built-in field id: $id',
    _ => null,
  };
  if (message == null) return;
  throw TemplateFault(FaultCode.unknownValue, message, file: file, key: key);
}

void _claimId(
  Set<String> seen,
  String id, {
  required String file,
  required String key,
}) {
  if (seen.add(id)) return;
  throw TemplateFault(
    FaultCode.unknownValue,
    'shared entry id repeated: $id',
    file: file,
    key: key,
  );
}

List<String>? _forDocTypes(
  YamlMap entry, {
  required String file,
  required String prefix,
}) {
  final list = optionalValue<YamlList>(
    entry,
    _forDocTypesKey,
    file: file,
    prefix: prefix,
  );
  if (list == null) return null;
  if (list.isEmpty) {
    throw TemplateFault(
      FaultCode.unknownValue,
      '$_forDocTypesKey holds no doc type',
      file: file,
      key: '$prefix$_forDocTypesKey',
    );
  }
  return stringsOf(list, _forDocTypesKey, file: file, prefix: prefix);
}

/// Returns [text] without its one trailing line break.
///
/// Throws `unknown_value` at [key] when nothing is left or a line break
/// remains.
String _oneLine(String text, {required String file, required String key}) {
  final normalized = text.replaceAll('\r\n', '\n');
  final line = normalized.endsWith('\n')
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
  if (line.trim().isNotEmpty && !line.contains('\n')) return line;
  throw TemplateFault(
    FaultCode.unknownValue,
    'a shared line holds one line of text',
    file: file,
    key: key,
  );
}

YamlMap _entryMap(Object? entry, String key, {required String file}) {
  if (entry is YamlMap) return entry;
  throw TemplateFault(
    FaultCode.unknownValue,
    'the entry must be a mapping',
    file: file,
    key: key,
  );
}
