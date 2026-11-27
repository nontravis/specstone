import 'package:specstone_core/src/doc_model/records_root.dart';

/// A doc type path pattern, matched against a whole DocPath.
///
/// `{nn}` matches `[0-9]+`, `{slug}` matches `[a-z0-9_]+`, and every other
/// character is literal. A placeholder never crosses a `/`.
final class PathPattern {
  new(String source)
    : this._(source, [for (final part in source.split('/')) PathSegment(part)]);

  new _(this.source, this._segments)
    : _whole = RegExp('^${_segments.map((s) => s.body).join('/')}\$'),
      _tokens = [for (final segment in _segments) ...segment.tokens];

  /// The pattern text, as the doc type declares it.
  final String source;

  final List<PathSegment> _segments;
  final RegExp _whole;

  /// The placeholders of the whole pattern in order; group i + 1 of [_whole]
  /// holds token i.
  final List<String> _tokens;

  /// Returns this pattern with [target] as a literal folder right after its
  /// first segment, or right after `.specstone/records/` for a records path:
  /// a pattern with no folder takes the target as its folder.
  PathPattern forTarget(String target) {
    final _FolderSplit(:head, :rest) = _splitAtFirstFolder();
    return PathPattern('$head$target/$rest');
  }

  /// Returns the folder, ending in `/`, that holds [target]'s docs of this
  /// pattern: its first folder, or the records root, then the target folder.
  String targetFolder(String target) => '${_splitAtFirstFolder().head}$target/';

  // The text up to and including the first `/`, or the records root, and the
  // rest.
  _FolderSplit _splitAtFirstFolder() {
    final cut = isRecordsDocPath(source)
        ? recordsRootDocPath.length
        : source.indexOf('/') + 1;
    return _FolderSplit(
      head: source.substring(0, cut),
      rest: source.substring(cut),
    );
  }

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
      if (!_segments[i].regex.hasMatch(segments[i])) return null;
    }
    final segment = _segments[depth];
    final at = segment.tokens.indexOf(PathSegment.numberToken);
    if (at < 0) return null;
    final digits = segment.regex.firstMatch(segments[depth])?.group(at + 1);
    return digits == null ? null : int.tryParse(digits);
  }

  /// Returns the `{slug}` values of [docPath] in pattern order.
  ///
  /// Empty for a pattern with no `{slug}`; null when the pattern does not match
  /// all of [docPath]. The `{nn}` values are dropped.
  List<String>? slugValues(String docPath) {
    final match = _whole.firstMatch(docPath);
    if (match == null) return null;
    return [
      for (final (i, token) in _tokens.indexed)
        if (token == PathSegment.slugToken) match.group(i + 1)!,
    ];
  }

  /// Returns every `{nn}` and `{slug}` value of [docPath] in pattern order.
  ///
  /// Null when the pattern does not match all of [docPath]. A `{nn}` value
  /// keeps its leading zeros.
  List<String>? valuesOf(String docPath) {
    final match = _whole.firstMatch(docPath);
    if (match == null) return null;
    return [for (var i = 1; i <= _tokens.length; i++) match.group(i)!];
  }

  /// Returns the pattern with its placeholders replaced by [values], in order.
  ///
  /// Throws [ArgumentError] when [values] and the placeholders differ in count.
  String fill(List<String> values) {
    final tokens = PathSegment.placeholder.allMatches(source).toList();
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
}

/// One `/`-separated segment of a doc type path, with its placeholders.
///
/// The one compiler of the placeholder grammar: [regex] matches a whole
/// segment and holds one group per placeholder, in order, so a reader picks
/// its group by token index.
final class PathSegment {
  new(this.source)
    : tokens = [for (final m in placeholder.allMatches(source)) m.group(0)!],
      body = source.splitMapJoin(
        placeholder,
        onMatch: (m) => m.group(0) == numberToken ? '([0-9]+)' : '([a-z0-9_]+)',
        onNonMatch: RegExp.escape,
      );

  /// A placeholder: `{nn}` or `{slug}`.
  static final placeholder = RegExp(r'\{nn\}|\{slug\}');

  /// Returns how many placeholders [text] holds.
  static int placeholderCount(String text) =>
      placeholder.allMatches(text).length;

  /// Returns how many `{slug}` placeholders [text] holds.
  static int slugCount(String text) =>
      placeholder.allMatches(text).where((m) => m[0] == slugToken).length;

  /// The placeholder that matches digits.
  static const numberToken = '{nn}';

  /// The placeholder that matches a slug.
  static const slugToken = '{slug}';

  final String source;

  /// The placeholders of the segment in order: [numberToken] or [slugToken].
  final List<String> tokens;

  /// The unanchored expression of the segment, for joining into a longer one.
  final String body;

  /// Matches a whole segment; one group per placeholder.
  late final RegExp regex = RegExp('^$body\$');

  /// Returns [source] with each placeholder replaced by the next of [values],
  /// taken from [next] on.
  String fill(List<String> values, int Function() next) =>
      source.splitMapJoin(placeholder, onMatch: (_) => values[next()]);
}

/// A pattern's text up to and including its first folder, or the records root,
/// and the rest.
final class _FolderSplit {
  const new({required this.head, required this.rest});

  final String head;
  final String rest;
}
