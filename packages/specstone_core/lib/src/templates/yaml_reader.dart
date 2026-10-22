import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:yaml/yaml.dart';

/// Parses [text] into a [YamlMap], mapping YAML errors to a [TemplateFault].
///
/// Empty text gives an empty map. A YAML syntax error, a duplicate key, or a
/// root that is not a map is `yaml_syntax`. [file] names the source.
YamlMap readYamlMap(String text, {required String file}) {
  final Object? root;
  try {
    root = loadYaml(text, sourceUrl: Uri.file(file));
  } on YamlException catch (error) {
    throw TemplateFault(
      FaultCode.yamlSyntax,
      error.message,
      file: file,
      line: error.span == null ? null : error.span!.start.line + 1,
    );
  }
  return switch (root) {
    null => YamlMap(),
    final YamlMap map => map,
    _ => throw TemplateFault(
      FaultCode.yamlSyntax,
      'the document must be a mapping of keys to values',
      file: file,
      line: 1,
    ),
  };
}

/// Throws `unknown_key` for the first key of [map] not in [allowed].
///
/// Keys are checked in file order; the fault key is `'$prefix$name'`.
void checkKeys(
  YamlMap map,
  Set<String> allowed, {
  required String file,
  String prefix = '',
}) {
  for (final name in map.keys) {
    if (name is String && allowed.contains(name)) continue;
    throw TemplateFault(
      FaultCode.unknownKey,
      'the doc-type format defines no key $name',
      file: file,
      key: '$prefix$name',
    );
  }
}

/// Returns the [T] at [key] of [map].
///
/// Throws `missing_key` when [key] is absent or null, and `unknown_value` when
/// the value is not a [T].
T requireValue<T extends Object>(
  YamlMap map,
  String key, {
  required String file,
  String prefix = '',
}) {
  final value = optionalValue<T>(map, key, file: file, prefix: prefix);
  if (value != null) return value;
  throw TemplateFault(
    FaultCode.missingKey,
    'the key $key is required',
    file: file,
    key: '$prefix$key',
  );
}

/// Returns the [T] at [key] of [map], or null when [key] is absent or null.
///
/// Throws `unknown_value` when the value is not a [T].
T? optionalValue<T extends Object>(
  YamlMap map,
  String key, {
  required String file,
  String prefix = '',
}) {
  final value = map[key];
  return switch (value) {
    null => null,
    final T typed => typed,
    _ => throw TemplateFault(
      FaultCode.unknownValue,
      'the key $key must be a $T',
      file: file,
      key: '$prefix$key',
    ),
  };
}

/// Returns the list of strings at [key] of [map], empty when [key] is absent.
///
/// Throws `unknown_value` when the value is not a list or holds a non-string.
List<String> stringList(
  YamlMap map,
  String key, {
  required String file,
  String prefix = '',
}) {
  final list = optionalValue<YamlList>(map, key, file: file, prefix: prefix);
  if (list == null) return const [];
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
