import 'package:specstone_core/src/templates/models/pattern_entry.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/yaml_reader.dart';
import 'package:yaml/yaml.dart';

/// Parses one entry, at fault key [key].
///
/// With [forRequired], the entry allows only `id`, `pattern`, `message`, and
/// `per_subsection`.
/// Throws `unknown_value` for a `pattern` or `except` entry that does not
/// compile, so no later reader meets a `FormatException`.
PatternEntry parsePatternEntry(
  YamlMap map, {
  required String file,
  required String key,
  required bool forRequired,
}) {
  final prefix = '$key.';
  checkKeys(
    map,
    forRequired ? _requiredKeys : _bannedKeys,
    file: file,
    format: 'doc-type',
    prefix: prefix,
  );
  final id = requireValue<String>(map, 'id', file: file, prefix: prefix);
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
  final scope = _scopeOf(map, file: file, prefix: prefix);
  final perSubsection =
      optionalValue<bool>(map, 'per_subsection', file: file, prefix: prefix) ??
      false;
  try {
    return PatternEntry(
      id: id,
      pattern: pattern,
      message: message,
      scope: scope,
      except: List.unmodifiable(except),
      perSubsection: perSubsection,
    );
  } on FormatException {
    _compile(pattern, file: file, key: '${prefix}pattern');
    for (final entry in except) {
      _compile(_fullMatch(entry), file: file, key: '${prefix}except');
    }
    rethrow;
  }
}

const _bannedKeys = {'id', 'pattern', 'message', 'in', 'except'};

const _requiredKeys = {'id', 'pattern', 'message', 'per_subsection'};

/// Returns the expression that matches [source] against a whole text.
String _fullMatch(String source) => '^(?:$source)\$';

PatternScope _scopeOf(
  YamlMap map, {
  required String file,
  required String prefix,
}) {
  final wire = optionalValue<String>(map, 'in', file: file, prefix: prefix);
  if (wire == null) return PatternScope.text;
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
