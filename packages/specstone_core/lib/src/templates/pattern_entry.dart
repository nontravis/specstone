import 'package:specstone_core/src/templates/format_keys.dart';
import 'package:specstone_core/src/templates/models/pattern_entry.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/yaml_reader.dart';
import 'package:yaml/yaml.dart';

/// Parses one entry, at fault key [key].
///
/// [path] is the dotted doc-type format path of the pattern list the entry
/// sits in; the keys it holds are the keys of that path.
/// Throws `unknown_value` for a `pattern` or `except` entry that does not
/// compile, so no later reader meets a `FormatException`, and
/// `pattern_ref_invalid` for an entry that holds `pattern` and `pattern_ref`.
LayerPattern parsePatternEntry(
  YamlMap map, {
  required String file,
  required String key,
  required String path,
}) {
  final prefix = '$key.';
  checkKeys(
    map,
    formatKeysAt(docTypeFileFormat, path),
    file: file,
    format: 'doc-type',
    prefix: prefix,
  );
  final id = requireValue<String>(map, 'id', file: file, prefix: prefix);
  final ref = optionalPatternRef(map, file: file, prefix: prefix);
  if (ref != null) {
    return _parseRef(map, id: id, ref: ref, file: file, key: key);
  }
  return _parseOwn(map, id: id, file: file, prefix: prefix);
}

RefPattern _parseRef(
  YamlMap map, {
  required String id,
  required String ref,
  required String file,
  required String key,
}) {
  final prefix = '$key.';
  final message = requireValue<String>(
    map,
    'message',
    file: file,
    prefix: prefix,
  );
  final except = stringList(map, 'except', file: file, prefix: prefix);
  checkPatternSources(null, except, file: file, prefix: prefix);
  return RefPattern(
    id: id,
    ref: ref,
    message: message,
    key: key,
    scope:
        optionalPatternScope(map, file: file, prefix: prefix) ??
        PatternScope.text,
    except: List.unmodifiable(except),
    perSubsection:
        optionalValue<bool>(
          map,
          'per_subsection',
          file: file,
          prefix: prefix,
        ) ??
        false,
  );
}

OwnPattern _parseOwn(
  YamlMap map, {
  required String id,
  required String file,
  required String prefix,
}) {
  final pattern = requireValue<String>(
    map,
    'pattern',
    file: file,
    prefix: prefix,
  );
  final message = requireValue<String>(
    map,
    'message',
    file: file,
    prefix: prefix,
  );
  final except = stringList(map, 'except', file: file, prefix: prefix);
  final scope =
      optionalPatternScope(map, file: file, prefix: prefix) ??
      PatternScope.text;
  final perSubsection =
      optionalValue<bool>(map, 'per_subsection', file: file, prefix: prefix) ??
      false;
  try {
    return OwnPattern(
      PatternEntry(
        id: id,
        pattern: pattern,
        message: message,
        scope: scope,
        except: List.unmodifiable(except),
        perSubsection: perSubsection,
      ),
    );
  } on FormatException {
    checkPatternSources(pattern, except, file: file, prefix: prefix);
    rethrow;
  }
}

/// Returns the `pattern_ref` id [map] writes, or null when absent.
///
/// Throws `pattern_ref_invalid` at `<prefix>pattern_ref` when [map] also
/// writes `pattern`.
String? optionalPatternRef(
  YamlMap map, {
  required String file,
  required String prefix,
}) {
  final ref = optionalValue<String>(
    map,
    'pattern_ref',
    file: file,
    prefix: prefix,
  );
  if (ref == null || map['pattern'] == null) return ref;
  throw TemplateFault(
    FaultCode.patternRefInvalid,
    'an entry holds pattern or pattern_ref, not both',
    file: file,
    key: '${prefix}pattern_ref',
  );
}

/// Throws `unknown_value` at `<prefix>pattern` or `<prefix>except` for the
/// first source that does not compile.
void checkPatternSources(
  String? pattern,
  List<String> except, {
  required String file,
  required String prefix,
}) {
  if (pattern != null) _compile(pattern, file: file, key: '${prefix}pattern');
  for (final entry in except) {
    _compile(_fullMatch(entry), file: file, key: '${prefix}except');
  }
}

/// Returns the scope the `in` key writes, or null when absent.
///
/// Throws `unknown_value` at `<prefix>in` for any other value.
PatternScope? optionalPatternScope(
  YamlMap map, {
  required String file,
  required String prefix,
}) {
  final wire = optionalValue<String>(map, 'in', file: file, prefix: prefix);
  if (wire == null) return null;
  for (final scope in PatternScope.values) {
    if (scope.wire == wire) return scope;
  }
  throw TemplateFault(
    FaultCode.unknownValue,
    'the key in must be text, code, or all',
    file: file,
    key: '${prefix}in',
  );
}

/// Returns the expression that matches [source] against a whole text.
String _fullMatch(String source) => '^(?:$source)\$';

void _compile(String source, {required String file, required String key}) {
  try {
    RegExp(source, unicode: true);
  } on FormatException catch (error) {
    throw TemplateFault(
      FaultCode.unknownValue,
      'the pattern does not compile: ${error.message}',
      file: file,
      key: key,
    );
  }
}
