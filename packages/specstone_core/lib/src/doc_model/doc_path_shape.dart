import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';

final _placeholder = RegExp(r'\{nn\}|\{slug\}');

const _numberToken = '{nn}';

/// One `/`-separated segment of a doc type path, with its placeholders.
final class _Segment {
  new(this.source)
    : tokens = [for (final m in _placeholder.allMatches(source)) m.group(0)!],
      regex = _compile(source);

  static RegExp _compile(String source) {
    final pattern = source.splitMapJoin(
      _placeholder,
      onMatch: (m) => m.group(0) == _numberToken ? '([0-9]+)' : '([a-z0-9_]+)',
      onNonMatch: RegExp.escape,
    );
    return RegExp('^$pattern\$');
  }

  final String source;

  /// The placeholders of the segment in order: `{nn}` or `{slug}`.
  final List<String> tokens;

  /// Matches a whole segment; one group per placeholder.
  final RegExp regex;

  /// Returns [source] with each placeholder replaced by the next of [values],
  /// taken from [next] on.
  String fill(List<String> values, int Function() next) =>
      source.splitMapJoin(_placeholder, onMatch: (_) => values[next()]);
}

/// The shape of a doc type's `path:`: which segment is the doc's own, and
/// what its placeholders hold (s03 OwnSegment).
final class DocPathShape {
  new _(this.segments, this.ownIndex, this.parentCount, this._patterns);

  /// Returns the shape of [docType], or null when it or its parent type has
  /// no `path:`.
  static DocPathShape? of(MergedDocType docType, MergedSet set) {
    final path = docType.path;
    if (path == null) return null;
    final parentId = docType.parent;
    final parentCount = switch (parentId) {
      null => 0,
      final id => _placeholdersIn(set.lookup(id)?.path),
    };
    if (parentCount == null) return null;
    final segments = path.split('/');
    final patterns = [for (final s in segments) _Segment(s)];
    var running = 0;
    var ownIndex = segments.length - 1;
    for (var i = 0; i < patterns.length; i++) {
      running += patterns[i].tokens.length;
      if (running > parentCount) {
        ownIndex = i;
        break;
      }
    }
    return DocPathShape._(segments, ownIndex, parentCount, patterns);
  }

  static int? _placeholdersIn(String? path) =>
      path == null ? null : _placeholder.allMatches(path).length;

  /// The `path:` split on `/`.
  final List<String> segments;

  /// The index of the segment that names the doc itself.
  final int ownIndex;

  /// The number of placeholders in the parent doc type's `path:`.
  final int parentCount;

  final List<_Segment> _patterns;

  /// Whether the own segment is the file, not a folder.
  bool get ownIsFile => ownIndex == segments.length - 1;

  /// Returns the `{nn}` and `{slug}` values [name] holds when it fits the own
  /// segment, else null; a value the segment lacks is null.
  ({int? number, String? slug})? matchOwn(String name) {
    final pattern = _patterns[ownIndex];
    final match = pattern.regex.firstMatch(name);
    if (match == null) return null;
    final values = {
      for (var i = 0; i < pattern.tokens.length; i++)
        pattern.tokens[i]: match.group(i + 1)!,
    };
    return (
      number: int.tryParse(values[_numberToken] ?? ''),
      slug: values['{slug}'],
    );
  }

  /// Whether a segment after the own one holds a placeholder.
  bool get belowOwnHasPlaceholder =>
      segments.skip(ownIndex + 1).any(_placeholder.hasMatch);

  /// Whether the own segment holds `{nn}`.
  bool get numbered => _patterns[ownIndex].tokens.contains(_numberToken);

  /// Whether the own segment holds `{slug}`.
  bool get slugged => _patterns[ownIndex].tokens.contains('{slug}');

  /// Returns the placeholder values of [docPath] in pattern order, `{nn}`
  /// digits as written; null when the pattern does not match.
  List<String>? valuesOf(String docPath) {
    final parts = docPath.split('/');
    if (parts.length != segments.length) return null;
    final values = <String>[];
    for (var i = 0; i < parts.length; i++) {
      final match = _patterns[i].regex.firstMatch(parts[i]);
      if (match == null) return null;
      values.addAll([
        for (var g = 1; g <= match.groupCount; g++) match.group(g)!,
      ]);
    }
    return values;
  }

  /// Returns the DocPath that [values] fill, the inverse of [valuesOf].
  String build(List<String> values) => _fill(segments.length, values).join('/');

  /// Returns the values of the own segment's placeholders in pattern order.
  ///
  /// Throws [ArgumentError] when the segment holds a placeholder whose value
  /// is null.
  List<String> ownValues({String? number, String? slug}) => [
    for (final token in _patterns[ownIndex].tokens)
      (token == _numberToken ? number : slug) ??
          (throw ArgumentError('the own segment takes $token')),
  ];

  /// Returns the DocPath of the own segment of [docPath]: a folder ending in
  /// `/`, or the file.
  String ownPathOf(String docPath) {
    final own = docPath.split('/').take(ownIndex + 1).join('/');
    return ownIsFile ? own : '$own/';
  }

  /// Returns the folder that holds the own segment, built from the parent's
  /// [parentValues]: ending in `/`, or `''` for the docs root.
  String containerOf(List<String> parentValues) {
    if (ownIndex == 0) return '';
    return '${_fill(ownIndex, parentValues).join('/')}/';
  }

  List<String> _fill(int count, List<String> values) {
    var next = 0;
    return [
      for (final pattern in _patterns.take(count))
        pattern.fill(values, () => next++),
    ];
  }
}

/// Whether [shape] is a spec doc's (dw INV-8): a file with no placeholder of
/// its own, so its parent names the folder it sits in.
bool isSpecDocShape(DocPathShape shape) =>
    shape.ownIsFile && !shape.numbered && !shape.slugged;

/// Returns the child doc types of [docType] whose docs sit in a folder
/// outside [docType]'s own segment, with that folder for [values].
///
/// A child counts when its own segment is its last segment and holds no
/// placeholder (a feature's spec docs).
Iterable<(MergedDocType, String)> specChildrenOf(
  MergedSet set,
  MergedDocType docType,
  DocPathShape shape,
  List<String> values,
) sync* {
  final own = shape.ownPathOf(shape.build(values));
  for (final child in set.docTypes) {
    if (child.parent != docType.id) continue;
    final childShape = DocPathShape.of(child, set);
    if (childShape == null || !isSpecDocShape(childShape)) continue;
    final folder = childShape.containerOf(values);
    if (folder.isNotEmpty && !folder.startsWith(own)) yield (child, folder);
  }
}

/// Returns the folders of the docs that [docType] holds outside its own
/// segment, for the doc whose placeholder [values] are given.
///
/// These are the folders of the child doc types whose own segment is their
/// last segment and holds no placeholder (a feature's spec docs), each once,
/// sorted.
List<String> specFoldersOf(
  MergedSet set,
  MergedDocType docType,
  List<String> values,
) {
  final shape = DocPathShape.of(docType, set);
  if (shape == null) return const [];
  return {
    for (final (_, folder) in specChildrenOf(set, docType, shape, values))
      folder,
  }.toList()..sort();
}

/// Returns the paths of the delete unit of the doc at [docPath]: its own
/// segment, a folder ending in `/` or the file, then the folders of its spec
/// docs; null when [docType] has no `path:` or [docPath] does not match it.
List<String>? unitRootsOf(
  MergedSet set,
  MergedDocType docType,
  String docPath,
) {
  final shape = DocPathShape.of(docType, set);
  if (shape == null) return null;
  final values = shape.valuesOf(docPath);
  if (values == null) return null;
  return [shape.ownPathOf(docPath), ...specFoldersOf(set, docType, values)];
}
