/// A doc type path pattern, matched against a whole DocPath.
///
/// `{nn}` matches `[0-9]+`, `{slug}` matches `[a-z0-9_]+`, and every other
/// character is literal. A placeholder never crosses a `/`.
final class PathPattern {
  new(this.source)
    : _whole = _compile(source),
      _segments = [for (final part in source.split('/')) _compile(part)],
      _slugs = _compile(source, slugGroups: true),
      _values = _compile(source, allGroups: true);

  static final _placeholder = RegExp(r'\{nn\}|\{slug\}');

  /// The pattern text, as the doc type declares it.
  final String source;

  final RegExp _whole;
  final List<RegExp> _segments;
  final RegExp _slugs;
  final RegExp _values;

  /// Returns whether the pattern matches all of [docPath].
  bool matches(String docPath) => _whole.hasMatch(docPath);

  /// Whether the pattern ends in a fixed file name inside a folder that holds
  /// a placeholder, such as `prds/features/f{nn}_{slug}/FEATURE.md`.
  bool get isFolderDoc {
    final segments = source.split('/');
    return segments.length > 1 &&
        !_placeholder.hasMatch(segments.last) &&
        segments.take(segments.length - 1).any(_placeholder.hasMatch);
  }

  /// Returns the first `{nn}` value of the pattern segment at the depth of
  /// the entry [segments], or null.
  ///
  /// Null when an earlier pattern segment does not match its entry segment,
  /// when the entry is deeper than the pattern, when the last segment does
  /// not match, when the pattern segment holds no `{nn}`, or when the digits
  /// overflow an int.
  int? numberAt(List<String> segments) {
    final depth = segments.length - 1;
    if (depth < 0 || depth >= _segments.length) return null;
    for (var i = 0; i < depth; i++) {
      if (!_segments[i].hasMatch(segments[i])) return null;
    }
    final match = _segments[depth].firstMatch(segments[depth]);
    final digits = match == null || match.groupCount == 0
        ? null
        : match.group(1);
    return digits == null ? null : int.tryParse(digits);
  }

  /// Returns the `{slug}` values of [docPath] in pattern order.
  ///
  /// Empty for a pattern with no `{slug}`; null when the pattern does not match
  /// all of [docPath]. The `{nn}` values are dropped.
  List<String>? slugValues(String docPath) {
    final match = _slugs.firstMatch(docPath);
    if (match == null) return null;
    return [for (var i = 1; i <= match.groupCount; i++) match.group(i)!];
  }

  /// Returns every `{nn}` and `{slug}` value of [docPath] in pattern order.
  ///
  /// Null when the pattern does not match all of [docPath]. A `{nn}` value
  /// keeps its leading zeros.
  List<String>? valuesOf(String docPath) {
    final match = _values.firstMatch(docPath);
    if (match == null) return null;
    return [for (var i = 1; i <= match.groupCount; i++) match.group(i)!];
  }

  /// Returns the pattern with its placeholders replaced by [values], in order.
  ///
  /// Throws [ArgumentError] when [values] and the placeholders differ in count.
  String fill(List<String> values) {
    final tokens = _placeholder.allMatches(source).toList();
    if (tokens.length != values.length) {
      throw ArgumentError.value(
        values,
        'values',
        'expected ${tokens.length} values for "$source"',
      );
    }
    final buffer = StringBuffer();
    var literalStart = 0;
    for (final (index, token) in tokens.indexed) {
      buffer
        ..write(source.substring(literalStart, token.start))
        ..write(values[index]);
      literalStart = token.end;
    }
    return (buffer..write(source.substring(literalStart))).toString();
  }

  /// Compiles [text] to an anchored expression.
  ///
  /// Each `{nn}` is a group, or each `{slug}` when [slugGroups] is set, or
  /// every placeholder when [allGroups] is set.
  static RegExp _compile(
    String text, {
    bool slugGroups = false,
    bool allGroups = false,
  }) {
    final buffer = StringBuffer('^');
    var literalStart = 0;
    for (final token in _placeholder.allMatches(text)) {
      buffer
        ..write(RegExp.escape(text.substring(literalStart, token.start)))
        ..write(
          token.group(0) == '{nn}'
              ? (slugGroups ? '[0-9]+' : '([0-9]+)')
              : (slugGroups || allGroups ? '([a-z0-9_]+)' : '[a-z0-9_]+'),
        );
      literalStart = token.end;
    }
    buffer
      ..write(RegExp.escape(text.substring(literalStart)))
      ..write(r'$');
    return RegExp(buffer.toString());
  }
}
