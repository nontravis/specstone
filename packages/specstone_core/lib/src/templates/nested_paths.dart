import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// A folder segment of a path that repeats once per nesting level.
typedef NestingSegment = ({int index, String text});

final _placeholder = RegExp(r'\{nn\}|\{slug\}');

int _placeholderCount(Iterable<String> segments) =>
    segments.fold(0, (sum, s) => sum + _placeholder.allMatches(s).length);

/// Returns the folder segment of [path] that repeats for [nesting], or null.
///
/// [nesting]'s segment is the last folder segment of its `path`, with `c` the
/// placeholders in the segments up to it. The segment of [path] is the first
/// folder segment whose running placeholder count reaches `c`, when it reads
/// the same text.
NestingSegment? nestingSegmentOf(String path, MergedDocType nesting) {
  final own = nesting.path?.split('/');
  if (own == null || own.length < 2) return null;
  final text = own[own.length - 2];
  final wanted = _placeholderCount(own.take(own.length - 1));
  if (wanted == 0) return null;
  final segments = path.split('/');
  var running = 0;
  for (var index = 0; index < segments.length - 1; index++) {
    running += _placeholderCount([segments[index]]);
    if (running >= wanted) {
      return segments[index] == text ? (index: index, text: text) : null;
    }
  }
  return null;
}

/// Returns [path] with [segment] repeated [depth] more times after itself.
String pathAtDepth(String path, NestingSegment segment, int depth) {
  final segments = path.split('/');
  final cut = segment.index + 1;
  return [
    ...segments.take(cut),
    ...List.filled(depth, segment.text),
    ...segments.skip(cut),
  ].join('/');
}

/// Returns the nesting type of [docTypes]: the first that writes `max_depth`,
/// 0 included, or null.
MergedDocType? nestingTypeOf(List<MergedDocType> docTypes) {
  for (final docType in docTypes) {
    if (docType.maxDepth != null) return docType;
  }
  return null;
}

/// Returns [docTypes] with a pattern per depth on each doc type that nests.
///
/// The nesting type is the doc type that writes `max_depth`; a doc type nests
/// with it when its `parent` chain reaches it and its `path` holds the
/// repeating segment. Every other doc type comes back as the same object.
List<MergedDocType> withNestedPaths(List<MergedDocType> docTypes) {
  final nesting = nestingTypeOf(docTypes);
  if (nesting == null || !nesting.nests) return docTypes;
  final byId = {for (final docType in docTypes) docType.id: docType};
  return [for (final docType in docTypes) _nestedCopy(docType, nesting, byId)];
}

MergedDocType _nestedCopy(
  MergedDocType docType,
  MergedDocType nesting,
  Map<String, MergedDocType> byId,
) {
  final path = docType.path;
  if (path == null || !_reaches(docType, nesting.id, byId)) return docType;
  final segment = nestingSegmentOf(path, nesting);
  if (segment == null) return docType;
  return docType.copyWith(
    nestedPaths: [
      for (var depth = 0; depth <= nesting.maxDepth!; depth++)
        pathAtDepth(path, segment, depth),
    ],
  );
}

/// Whether [start] or one of its `parent` ancestors has the id [targetId].
bool _reaches(
  MergedDocType start,
  String targetId,
  Map<String, MergedDocType> byId,
) {
  final visited = <String>{};
  for (
    MergedDocType? current = start;
    current != null && visited.add(current.id);
    current = switch (current.parent) {
      final parent? => byId[parent],
      null => null,
    }
  ) {
    if (current.id == targetId) return true;
  }
  return false;
}
