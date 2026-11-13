import 'package:specstone_core/src/doc_model/path_pattern.dart';
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
  new _(
    this.segments,
    this.ownIndex,
    this.parentCount,
    this.depth,
    this._patterns,
  );

  /// Returns the shape of [docType] at nesting [depth], or null when it or
  /// its parent type has no `path:` at that depth.
  ///
  /// The parent count at [depth] is the placeholders in the parent type's
  /// pattern for the same depth; the nesting type above depth 0 counts its
  /// own pattern one depth up. [target], when given, reads the pattern with
  /// that code target's folder in it (RULE-20), as a per-target doc type's
  /// docs sit in it with two or more targets.
  static DocPathShape? of(
    MergedDocType docType,
    MergedSet set, {
    int depth = 0,
    String? target,
  }) {
    final paths = docType.paths;
    if (depth < 0 || depth >= paths.length) return null;
    final parentCount = _parentCountAt(docType, set, depth);
    if (parentCount == null) return null;
    final path = target == null
        ? paths[depth]
        : PathPattern(paths[depth]).forTarget(target).source;
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
    return DocPathShape._(segments, ownIndex, parentCount, depth, patterns);
  }

  /// Returns the shape of the depth whose pattern [docPath] matches, or null
  /// when none does.
  ///
  /// [target] is the code target of a per-target doc: its pattern, with the
  /// target folder in it, is tried first, then the plain one, as a doc sits
  /// outside the folder when the project names one target.
  static DocPathShape? ofDoc(
    MergedDocType docType,
    MergedSet set,
    String docPath, {
    String? target,
  }) {
    for (var depth = 0; depth < docType.paths.length; depth++) {
      for (final folder in [?target, null]) {
        final shape = of(docType, set, depth: depth, target: folder);
        if (shape?.valuesOf(docPath) != null) return shape;
      }
    }
    return null;
  }

  static int? _parentCountAt(MergedDocType docType, MergedSet set, int depth) {
    if (depth > 0 && docType.id == set.nestingType?.id) {
      return _placeholdersIn(docType.paths[depth - 1]);
    }
    final parentId = docType.parent;
    if (parentId == null) return 0;
    final parentPaths = set.lookup(parentId)?.paths ?? const <String>[];
    return depth < parentPaths.length
        ? _placeholdersIn(parentPaths[depth])
        : null;
  }

  static int _placeholdersIn(String path) =>
      _placeholder.allMatches(path).length;

  /// The pattern at [depth], split on `/`.
  final List<String> segments;

  /// The index of the segment that names the doc itself.
  final int ownIndex;

  /// The number of placeholders in the parent pattern at [depth]; for the
  /// nesting type above depth 0, in its own pattern one depth up.
  final int parentCount;

  /// How many more times the nesting segment repeats than in the base `path:`.
  final int depth;

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
    final childShape = DocPathShape.of(child, set, depth: shape.depth);
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
/// sorted. [depth] is the nesting depth of the doc.
///
/// A per-target child's folder is read once per name of [targetNames], with
/// the target folder where RULE-20 puts it; empty [targetNames] leaves it as
/// the plain pattern gives it.
List<String> specFoldersOf(
  MergedSet set,
  MergedDocType docType,
  List<String> values, {
  int depth = 0,
  List<String> targetNames = const [],
}) {
  final shape = DocPathShape.of(docType, set, depth: depth);
  if (shape == null) return const [];
  return {
    for (final (child, folder) in specChildrenOf(set, docType, shape, values))
      if (child.isPerTarget && targetNames.isNotEmpty)
        for (final name in targetNames)
          PathPattern(folder).forTarget(name).source
      else
        folder,
  }.toList()..sort();
}

/// Returns the paths of the delete unit of the doc at [docPath]: its own
/// segment, a folder ending in `/` or the file, then the folders of its spec
/// docs; null when [docType] has no `path:` or [docPath] does not match it.
///
/// [targetNames] are the code targets a per-target spec doc type's folder is
/// read in, as [specFoldersOf] takes them; [target] is the code target of the
/// doc itself, as [DocPathShape.ofDoc] takes it.
List<String>? unitRootsOf(
  MergedSet set,
  MergedDocType docType,
  String docPath, {
  List<String> targetNames = const [],
  String? target,
}) {
  final shape = DocPathShape.ofDoc(docType, set, docPath, target: target);
  final values = shape?.valuesOf(docPath);
  if (shape == null || values == null) return null;
  return [
    shape.ownPathOf(docPath),
    ...specFoldersOf(
      set,
      docType,
      values,
      depth: shape.depth,
      targetNames: targetNames,
    ),
  ];
}
