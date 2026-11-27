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
    this.perSubsection = false,
  }) : regExp = RegExp(pattern, unicode: true),
       _exceptRegExps = [
         for (final entry in except) RegExp(_fullMatch(entry), unicode: true),
       ];

  /// The entry id; the merge key.
  final String id;

  /// The regular expression source, compiled case sensitive.
  final String pattern;

  /// What a finding says when the entry fires.
  final String message;

  /// Where the entry looks, the prose when the `in` key is absent.
  final PatternScope scope;

  /// Matched texts the entry lets pass; each is a full-match expression.
  final List<String> except;

  /// Whether each `###` subsection of the section must match; a
  /// `required_patterns` entry only.
  final bool perSubsection;

  /// The compiled [pattern], Unicode mode.
  final RegExp regExp;

  final List<RegExp> _exceptRegExps;

  /// Whether [matched] equals any [except] entry, matched as a whole.
  bool isExcepted(String matched) =>
      _exceptRegExps.any((entry) => entry.hasMatch(matched));

  /// Returns the JSON object of this entry; `except` and `perSubsection` print
  /// only when set.
  Map<String, Object> toJson() => {
    'id': id,
    'pattern': pattern,
    'message': message,
    'in': scope.wire,
    if (except.isNotEmpty) 'except': except,
    if (perSubsection) 'perSubsection': true,
  };
}

/// One `banned_patterns` or `required_patterns` entry as a layer writes it:
/// its own regex, or a ref to a shared one that resolves at load.
sealed class LayerPattern {
  const new(this.id);

  /// The entry id; the merge key.
  final String id;
}

/// A layer entry that holds its own `pattern`.
final class OwnPattern extends LayerPattern {
  new(this.entry) : super(entry.id);

  /// The entry, compiled.
  final PatternEntry entry;
}

/// A layer entry that holds `pattern_ref` in place of `pattern`.
final class RefPattern extends LayerPattern {
  new({
    required String id,
    required this.ref,
    required this.message,
    required this.key,
    this.scope = PatternScope.text,
    this.except = const [],
    this.perSubsection = false,
  }) : super(id);

  /// The id of the shared pattern whose regex the entry takes.
  final String ref;

  /// What a finding says when the entry fires.
  final String message;

  /// The fault key of the entry in its layer file.
  final String key;

  /// Where the entry looks, the prose when the `in` key is absent.
  final PatternScope scope;

  /// Matched texts the entry lets pass; each is a full-match expression.
  final List<String> except;

  /// Whether each `###` subsection of the section must match; a
  /// `required_patterns` entry only.
  final bool perSubsection;

  /// Returns the entry with the shared [pattern] as its regex.
  PatternEntry resolve(String pattern) => PatternEntry(
    id: id,
    pattern: pattern,
    message: message,
    scope: scope,
    except: except,
    perSubsection: perSubsection,
  );
}

/// Returns the expression that matches [source] against a whole text.
String _fullMatch(String source) => '^(?:$source)\$';
