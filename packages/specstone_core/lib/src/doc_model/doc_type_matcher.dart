import 'package:specstone_core/src/doc_model/path_pattern.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/nested_paths.dart';

/// The result of matching one DocPath against a [MergedSet].
sealed class DocTypeMatch {
  const new();
}

/// Exactly one doc type's path pattern matches.
final class MatchedDocType extends DocTypeMatch {
  new(this.docType);

  /// The doc type whose pattern matches.
  final MergedDocType docType;
}

/// No doc type's path pattern matches.
final class NoDocType extends DocTypeMatch {
  const new();
}

/// Two or more doc types' path patterns match.
final class AmbiguousDocType extends DocTypeMatch {
  new(this.docTypeIds);

  /// The matching doc type ids, in code point order.
  final List<String> docTypeIds;
}

/// Finds the doc type of a DocPath from the path patterns of a [MergedSet].
final class DocTypeMatcher {
  new(MergedSet set)
    : _candidates = [
        for (final docType in set.docTypes)
          for (final path in docType.paths) (docType, PathPattern(path)),
      ],
      _nesting = set.nestingType;

  /// One (doc type, pattern) entry per path pattern, in set order.
  final List<(MergedDocType, PathPattern)> _candidates;

  final MergedDocType? _nesting;

  /// The over-limit pattern per depth, compiled on first use.
  final Map<int, PathPattern> _overDeepPatterns = {};

  /// Returns the doc type whose pattern matches [docPath], or why none does.
  DocTypeMatch match(String docPath) {
    final matched = [
      for (final (docType, pattern) in _candidates)
        if (pattern.matches(docPath)) docType,
    ];
    return switch (matched) {
      [] => const NoDocType(),
      [final only] => MatchedDocType(only),
      _ => AmbiguousDocType([for (final docType in matched) docType.id]),
    };
  }

  /// Returns the depth of [docPath] when it reads the nesting type's `path`
  /// with its segment repeated more than `max_depth` times; null otherwise.
  int? depthPastLimit(String docPath) {
    final nesting = _nesting;
    final path = nesting?.path;
    if (nesting == null || path == null) return null;
    final segment = nestingSegmentOf(path, nesting);
    if (segment == null) return null;
    final extra = docPath.split('/').length - path.split('/').length;
    for (var depth = nesting.maxDepth! + 1; depth <= extra; depth++) {
      final pattern = _overDeepPatterns[depth] ??= PathPattern(
        pathAtDepth(path, segment, depth),
      );
      if (pattern.matches(docPath)) return depth;
    }
    return null;
  }

  /// Returns the first number any doc type reads from [segments], or null.
  int? entryNumber(List<String> segments) {
    for (final (_, pattern) in _candidates) {
      final number = pattern.numberAt(segments);
      if (number != null) return number;
    }
    return null;
  }
}
