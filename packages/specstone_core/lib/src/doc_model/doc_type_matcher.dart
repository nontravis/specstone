import 'package:specstone_core/src/doc_model/path_pattern.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';

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
          if (docType.path case final path?) (docType, PathPattern(path)),
      ];

  /// Doc types with a path, in set order (sorted by id in code point order).
  final List<(MergedDocType, PathPattern)> _candidates;

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

  /// Returns the first number any doc type reads from [segments], or null.
  int? entryNumber(List<String> segments) {
    for (final (_, pattern) in _candidates) {
      final number = pattern.numberAt(segments);
      if (number != null) return number;
    }
    return null;
  }
}
