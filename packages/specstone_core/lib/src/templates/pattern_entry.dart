import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/yaml_reader.dart';
import 'package:yaml/yaml.dart';

/// Where a pattern looks in a doc: its prose, its code, or both.
///
/// [wire] is the value the `in` key takes.
enum PatternScope {
  text('text'),
  code('code'),
  all('all');

  new(this.wire);

  /// The value the doc-type format writes for this scope.
  final String wire;
}

/// One `banned_patterns` or `required_patterns` entry of a doc type.
final class PatternEntry {
  /// Compiles [pattern] and each [except] entry once.
  ///
  /// Throws a [FormatException] for a source that does not compile.
  new({
    required this.id,
    required this.pattern,
    required this.message,
    this.scope = PatternScope.text,
    this.except = const [],
  }) : regExp = RegExp(pattern, unicode: true),
       _exceptRegExps = [
         for (final entry in except) RegExp('^(?:$entry)\$', unicode: true),
       ];

  /// The entry id; the merge key.
  final String id;

  /// The regular expression source, compiled case sensitive.
  final String pattern;

  /// What a finding says when the entry fires.
  final String message;

  /// Where the entry looks; a `required_patterns` entry always uses text.
  final PatternScope scope;

  /// Matched texts the entry lets pass; each is a full-match expression.
  final List<String> except;

  /// The compiled [pattern], Unicode mode.
  final RegExp regExp;

  final List<RegExp> _exceptRegExps;

  /// Whether [matched] equals any [except] entry, matched as a whole.
  bool isExcepted(String matched) =>
      _exceptRegExps.any((entry) => entry.hasMatch(matched));

  /// Returns the JSON object of this entry; `except` prints only when set.
  Map<String, Object> toJson() => {
    'id': id,
    'pattern': pattern,
    'message': message,
    'in': scope.wire,
    if (except.isNotEmpty) 'except': except,
  };

  /// Parses one entry, at fault key [key].
  ///
  /// With [forRequired], the entry allows only `id`, `pattern`, and `message`.
  /// Throws `unknown_value` for a `pattern` or `except` entry that does not
  /// compile, so no later reader meets a `FormatException`.
  static PatternEntry parse(
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
    try {
      return PatternEntry(
        id: id,
        pattern: pattern,
        message: message,
        scope: scope,
        except: List.unmodifiable(except),
      );
    } on FormatException {
      _compile(pattern, file: file, key: '${prefix}pattern');
      for (final entry in except) {
        _compile('^(?:$entry)\$', file: file, key: '${prefix}except');
      }
      rethrow;
    }
  }
}

const _bannedKeys = {'id', 'pattern', 'message', 'in', 'except'};

const _requiredKeys = {'id', 'pattern', 'message'};

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
