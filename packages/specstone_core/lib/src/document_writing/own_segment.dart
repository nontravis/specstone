import 'dart:io';

import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';

final _slugShape = RegExp(r'^[a-z0-9_]+$');
final _placeholder = RegExp(r'\{nn\}|\{slug\}');

const _numberToken = '{nn}';

/// Returns [n] zero-padded to two digits; a number past 99 keeps its digits.
String padNumber(int n) => n.toString().padLeft(2, '0');

/// Throws [IndexFault] `argument_invalid` unless [slug] is lowercase letters,
/// digits, and `_`.
void checkSlug(String slug) {
  if (_slugShape.hasMatch(slug)) return;
  throw IndexFault(
    IndexFaultCode.argumentInvalid,
    '$slug is no slug: use lowercase letters, digits, and _',
  );
}

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

  /// Whether [own], an entry that fits the own segment, holds the doc.
  ///
  /// A folder with no doc file under it is no sibling: INV-8 counts docs. A
  /// file, or a doc file name with placeholders, is taken as is.
  bool _holdsDoc(FileSystemEntity own) {
    if (ownIsFile) return true;
    final rest = segments.sublist(ownIndex + 1);
    if (rest.any(_placeholder.hasMatch)) return true;
    return File([own.path, ...rest].join(Platform.pathSeparator)).existsSync();
  }

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

/// One folder or file of a doc type's own segment on disk.
final class SiblingEntry {
  const new({required this.name, required this.number, required this.slug});

  /// The folder or file name.
  final String name;

  /// The `{nn}` value; null when the segment holds none.
  final int? number;

  /// The `{slug}` value; null when the segment holds none.
  final String? slug;
}

/// Returns the siblings of [shape]'s own segment under [parentValues], sorted
/// by number, then name.
///
/// They are the folders that hold the doc file, or for a file segment the
/// files, of the container whose name matches the segment. Empty when the
/// container is absent.
/// Throws [RenderFault] `output_not_writable` when the container is unreadable.
List<SiblingEntry> siblingsOnDisk(
  Directory docsRoot,
  DocPathShape shape,
  List<String> parentValues,
) {
  final folder = shape
      .containerOf(parentValues)
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .join(Platform.pathSeparator);
  final container = Directory(
    '${docsRoot.path}${Platform.pathSeparator}$folder',
  );
  if (!container.existsSync()) return const [];
  final pattern = shape._patterns[shape.ownIndex];
  final entries = <SiblingEntry>[];
  final List<FileSystemEntity> children;
  try {
    children = container.listSync(followLinks: false);
  } on FileSystemException catch (error) {
    throw RenderFault(
      RenderFaultCode.outputNotWritable,
      'cannot read ${folder.replaceAll(Platform.pathSeparator, '/')}: '
      '${error.osError?.message ?? error.message}',
    );
  }
  for (final entity in children) {
    final isOwn = shape.ownIsFile ? entity is File : entity is Directory;
    if (!isOwn) continue;
    final name = entity.path.split(Platform.pathSeparator).last;
    final match = pattern.regex.firstMatch(name);
    if (match == null || !shape._holdsDoc(entity)) continue;
    final values = {
      for (var i = 0; i < pattern.tokens.length; i++)
        pattern.tokens[i]: match.group(i + 1)!,
    };
    entries.add(
      SiblingEntry(
        name: name,
        number: int.tryParse(values[_numberToken] ?? ''),
        slug: values['{slug}'],
      ),
    );
  }
  return entries..sort((a, b) {
    final byNumber = (a.number ?? 0).compareTo(b.number ?? 0);
    return byNumber != 0 ? byNumber : a.name.compareTo(b.name);
  });
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
  final own = shape.ownPathOf(shape.build(values));
  final folders = <String>{};
  for (final child in set.docTypes) {
    if (child.parent != docType.id) continue;
    final childShape = DocPathShape.of(child, set);
    if (childShape == null || !childShape.ownIsFile) continue;
    if (childShape.numbered || childShape.slugged) continue;
    final folder = childShape.containerOf(values);
    if (folder.isNotEmpty && !folder.startsWith(own)) folders.add(folder);
  }
  return folders.toList()..sort();
}
