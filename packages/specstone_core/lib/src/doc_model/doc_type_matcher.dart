import 'package:specstone_core/src/doc_model/path_pattern.dart';
import 'package:specstone_core/src/templates/code_target.dart' show twinNamesOf;
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/nested_paths.dart';

/// The result of matching one DocPath against a [MergedSet].
sealed class DocTypeMatch {
  const new();
}

/// Exactly one doc type's path pattern matches.
final class MatchedDocType extends DocTypeMatch {
  new(this.docType, {this.target});

  /// The doc type whose pattern matches.
  final MergedDocType docType;

  /// The code target whose pattern set matched; null for a shared doc type.
  final String? target;
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
  new(MergedSet set, {required List<String> targetNames})
    : this._(set, twinNamesOf(targetNames));

  new _(MergedSet set, List<String> twinNames)
    : _twinNames = twinNames,
      _candidates = [
        for (final docType in set.docTypes)
          for (final path in docType.paths)
            if (docType.isPerTarget && twinNames.isNotEmpty)
              for (final target in twinNames)
                (docType, PathPattern(path).forTarget(target), target)
            else
              (docType, PathPattern(path), null),
      ],
      _nesting = set.nestingType;

  /// One (doc type, pattern, target) entry per path pattern, in set order.
  final List<(MergedDocType, PathPattern, String?)> _candidates;

  /// The target names the per-target patterns expand into, as [twinNamesOf]
  /// gives them.
  final List<String> _twinNames;

  final MergedDocType? _nesting;

  /// The over-limit pattern per (target, depth), compiled on first use.
  final Map<(String?, int), PathPattern> _overDeepPatterns = {};

  /// Returns the doc type whose pattern matches [docPath], or why none does.
  DocTypeMatch match(String docPath) {
    final matched = [
      for (final (docType, pattern, target) in _candidates)
        if (pattern.matches(docPath)) (docType, target),
    ];
    return switch (matched) {
      [] => const NoDocType(),
      [final only] => MatchedDocType(only.$1, target: only.$2),
      _ => AmbiguousDocType([for (final (docType, _) in matched) docType.id]),
    };
  }

  /// Returns the depth of [docPath] when it reads the nesting type's `path`
  /// with its segment repeated more than `max_depth` times; null otherwise.
  ///
  /// A per-target nesting type reads one check per target name (RULE-20), so
  /// its plain pattern checks nothing.
  int? depthPastLimit(String docPath) {
    final nesting = _nesting;
    final path = nesting?.path;
    if (nesting == null || path == null) return null;
    final segment = nestingSegmentOf(path, nesting);
    if (segment == null) return null;
    final targets = nesting.isPerTarget && _twinNames.isNotEmpty
        ? _twinNames
        : const <String?>[null];
    final extra = docPath.split('/').length - path.split('/').length;
    for (final target in targets) {
      final base = target == null
          ? path
          : PathPattern(path).forTarget(target).source;
      for (var depth = nesting.maxDepth! + 1; depth <= extra; depth++) {
        final pattern = _overDeepPatterns[(target, depth)] ??= PathPattern(
          pathAtDepth(base, segment, depth),
        );
        if (pattern.matches(docPath)) return depth;
      }
    }
    return null;
  }

  /// Returns the first number any doc type reads from [segments], or null.
  int? entryNumber(List<String> segments) {
    for (final (_, pattern, _) in _candidates) {
      final number = pattern.numberAt(segments);
      if (number != null) return number;
    }
    return null;
  }
}
