import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/pattern_entry.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/yaml_reader.dart';
import 'package:yaml/yaml.dart';

const _linesKey = 'shared_lines';
const _fieldsKey = 'shared_fields';
const _forDocTypesKey = 'for_doc_types';
const _sectionsKey = 'sections';
const _disabledKey = 'disabled';
const _patternsId = 'patterns';
const Set<String> _lineKeys = {'id', 'text', _forDocTypesKey, _disabledKey};
const Set<String> _patternExtraKeys = {
  _forDocTypesKey,
  _sectionsKey,
  _disabledKey,
};

/// The shared list a [SharedPattern] comes from.
///
/// [listKey] is the `pack.yaml` key of the list.
enum SharedPatternKind {
  banned('shared_banned_patterns'),
  required('shared_required_patterns');

  new(this.listKey);

  /// The `pack.yaml` key of the list.
  final String listKey;
}

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

/// One `shared_banned_patterns` or `shared_required_patterns` entry of a
/// `pack.yaml`, as its file writes it.
///
/// Each pattern key is null when unwritten, as an entry that changes a lower
/// pattern writes only what it changes.
final class SharedPattern {
  new({
    required this.id,
    required this.kind,
    this.pattern,
    this.message,
    this.scope,
    this.except,
    this.perSubsection,
    this.forDocTypes,
    this.sections,
    required this.disabled,
    required this.file,
    required this.index,
  });

  /// The id the merge matches patterns of one [kind] by.
  final String id;

  /// The list the entry comes from.
  final SharedPatternKind kind;

  /// The regular expression source, when written.
  final String? pattern;

  /// What a finding says when the entry fires, when written.
  final String? message;

  /// Where a banned entry looks, when written.
  final PatternScope? scope;

  /// The matched texts a banned entry lets pass, when written.
  final List<String>? except;

  /// Whether each `###` subsection must match, when a required entry writes
  /// it.
  final bool? perSubsection;

  /// The doc type ids the pattern reaches, when written.
  final List<String>? forDocTypes;

  /// The section ids the pattern is limited to, when written.
  final List<String>? sections;

  /// Whether this entry turns the pattern off.
  final bool disabled;

  /// The file the entry was read from.
  final String file;

  /// The position of the entry in its list.
  final int index;
}

/// The shared lines, fields, and patterns one file declares, in file order.
final class SharedEntries {
  const new({
    required this.lines,
    required this.fields,
    required this.patterns,
  });

  /// No shared entries.
  static const SharedEntries empty = SharedEntries(
    lines: [],
    fields: [],
    patterns: [],
  );

  /// The `shared_lines` entries.
  final List<SharedLine> lines;

  /// The `shared_fields` entries.
  final List<SharedField> fields;

  /// The `shared_banned_patterns` entries, then the
  /// `shared_required_patterns` entries.
  final List<SharedPattern> patterns;
}

/// Reads the shared lists from the top-level [map] of [file].
///
/// Checks only what one file shows. The key of a fault is
/// `<list>[<i>].<key>`, such as `shared_fields[0].type`. The caller checks
/// the top-level keys.
///
/// - [format]: the file's format name an unknown line or pattern key's fault
///   names.
SharedEntries parseSharedEntries(
  YamlMap map, {
  required String file,
  required String format,
}) => SharedEntries(
  lines: _parseLines(map, file: file, format: format),
  fields: _parseFields(map, file: file),
  patterns: [
    for (final kind in SharedPatternKind.values)
      ..._parsePatterns(map, file: file, format: format, kind: kind),
  ],
);

List<SharedLine> _parseLines(
  YamlMap map, {
  required String file,
  required String format,
}) {
  final entries = optionalValue<YamlList>(map, _linesKey, file: file);
  if (entries == null) return <SharedLine>[];
  final seen = <String>{};
  return [
    for (final (i, entry) in entries.indexed)
      _parseLine(
        _entryMap(entry, '$_linesKey[$i]', file: file),
        index: i,
        file: file,
        format: format,
        seen: seen,
      ),
  ];
}

SharedLine _parseLine(
  YamlMap entry, {
  required int index,
  required String file,
  required String format,
  required Set<String> seen,
}) {
  final prefix = '$_linesKey[$index].';
  final id = requireValue<String>(entry, 'id', file: file, prefix: prefix);
  checkKeys(entry, _lineKeys, file: file, format: format, prefix: prefix);
  if (!isDocTypeIdShaped(id)) {
    throw TemplateFault(
      FaultCode.unknownValue,
      slugIdMessage,
      file: file,
      key: '${prefix}id',
    );
  }
  _claimId(seen, id, file: file, key: '${prefix}id');
  final text = optionalValue<String>(entry, 'text', file: file, prefix: prefix);
  return SharedLine(
    id: id,
    text: text == null
        ? null
        : _oneLine(text, file: file, key: '${prefix}text'),
    forDocTypes: _forDocTypes(entry, file: file, prefix: prefix),
    disabled: _disabled(entry, file: file, prefix: prefix),
    file: file,
    index: index,
  );
}

List<SharedPattern> _parsePatterns(
  YamlMap map, {
  required String file,
  required String format,
  required SharedPatternKind kind,
}) {
  final entries = optionalValue<YamlList>(map, kind.listKey, file: file);
  if (entries == null) return <SharedPattern>[];
  final seen = <String>{};
  return [
    for (final (i, entry) in entries.indexed)
      _parsePattern(
        _entryMap(entry, '${kind.listKey}[$i]', file: file),
        index: i,
        kind: kind,
        file: file,
        format: format,
        seen: seen,
      ),
  ];
}

SharedPattern _parsePattern(
  YamlMap entry, {
  required int index,
  required SharedPatternKind kind,
  required String file,
  required String format,
  required Set<String> seen,
}) {
  final prefix = '${kind.listKey}[$index].';
  final id = requireValue<String>(entry, 'id', file: file, prefix: prefix);
  final isRequired = kind == SharedPatternKind.required;
  checkKeys(
    entry,
    {...patternEntryKeys(forRequired: isRequired), ..._patternExtraKeys},
    file: file,
    format: format,
    prefix: prefix,
  );
  _claimId(seen, id, file: file, key: '${prefix}id');
  final pattern = optionalValue<String>(
    entry,
    'pattern',
    file: file,
    prefix: prefix,
  );
  final except = _optionalStrings(entry, 'except', file: file, prefix: prefix);
  checkPatternSources(pattern, except ?? const [], file: file, prefix: prefix);
  return SharedPattern(
    id: id,
    kind: kind,
    pattern: pattern,
    message: optionalValue<String>(
      entry,
      'message',
      file: file,
      prefix: prefix,
    ),
    scope: optionalPatternScope(entry, file: file, prefix: prefix),
    except: except,
    perSubsection: optionalValue<bool>(
      entry,
      'per_subsection',
      file: file,
      prefix: prefix,
    ),
    forDocTypes: _forDocTypes(entry, file: file, prefix: prefix),
    sections: _optionalStrings(entry, _sectionsKey, file: file, prefix: prefix),
    disabled: _disabled(entry, file: file, prefix: prefix),
    file: file,
    index: index,
  );
}

/// Returns the strings at [key], or null when [key] is absent or null.
List<String>? _optionalStrings(
  YamlMap entry,
  String key, {
  required String file,
  required String prefix,
}) {
  final list = optionalValue<YamlList>(entry, key, file: file, prefix: prefix);
  if (list == null) return null;
  return stringsOf(list, key, file: file, prefix: prefix);
}

bool _disabled(YamlMap entry, {required String file, required String prefix}) =>
    optionalValue<bool>(entry, _disabledKey, file: file, prefix: prefix) ??
    false;

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
  if (line.trim().isNotEmpty && !line.contains(RegExp('[\r\n]'))) return line;
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
