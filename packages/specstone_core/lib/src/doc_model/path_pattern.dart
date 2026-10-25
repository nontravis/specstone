/// A doc type path pattern, matched against a whole DocPath.
///
/// `{nn}` matches `[0-9]+`, `{slug}` matches `[a-z0-9_]+`, and every other
/// character is literal. A placeholder never crosses a `/`.
final class PathPattern {
  new(this.source)
    : _whole = _compile(source),
      _segments = [for (final part in source.split('/')) _compile(part)],
      _slugs = _compile(source, slugGroups: true);

  static final _placeholder = RegExp(r'\{nn\}|\{slug\}');

  /// The pattern text, as the doc type declares it.
  final String source;

  final RegExp _whole;
  final List<RegExp> _segments;
  final RegExp _slugs;

  /// Returns whether the pattern matches all of [docPath].
  bool matches(String docPath) => _whole.hasMatch(docPath);

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

  /// Compiles [text] to an anchored expression.
  ///
  /// Each `{nn}` is a group, or each `{slug}` when [slugGroups] is set.
  static RegExp _compile(String text, {bool slugGroups = false}) {
    final buffer = StringBuffer('^');
    var literalStart = 0;
    for (final token in _placeholder.allMatches(text)) {
      buffer
        ..write(RegExp.escape(text.substring(literalStart, token.start)))
        ..write(
          token.group(0) == '{nn}'
              ? (slugGroups ? '[0-9]+' : '([0-9]+)')
              : (slugGroups ? '([a-z0-9_]+)' : '[a-z0-9_]+'),
        );
      literalStart = token.end;
    }
    buffer
      ..write(RegExp.escape(text.substring(literalStart)))
      ..write(r'$');
    return RegExp(buffer.toString());
  }
}
