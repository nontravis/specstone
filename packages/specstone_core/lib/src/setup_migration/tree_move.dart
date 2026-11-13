import 'dart:io';

import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/doc_model/path_pattern.dart';
import 'package:specstone_core/src/document_writing/moved_paths.dart'
    show PathMove;
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';

/// Returns the moves that put each per-target doc at a one-target path into
/// the first of [targetNames], each with its placeholder values kept.
///
/// With fewer than two targets the spec root stays as it is, so nothing moves.
/// A doc moves only when no target's pattern set matches its path and a
/// per-target doc type's one-target pattern does; a doc already in a target
/// folder and a file no per-target doc type matches stay. [docPaths] are the
/// DocPaths under the docs root.
List<PathMove> treeMovesOf(
  List<String> docPaths,
  MergedSet set, {
  required List<String> targetNames,
}) {
  if (targetNames.length < 2) return const [];
  final inTargets = DocTypeMatcher(set, targetNames: targetNames);
  final oneTarget = DocTypeMatcher(set);
  final first = targetNames.first;
  final moves = <PathMove>[];
  for (final path in docPaths) {
    if (inTargets.match(path) is! NoDocType) continue;
    final match = oneTarget.match(path);
    if (match is! MatchedDocType || !match.docType.isPerTarget) continue;
    if (_inTargetFolder(path, match.docType, first) case final to?) {
      moves.add((from: path, to: to));
    }
  }
  return moves;
}

/// Returns [docPath], a doc of [docType], at the same path in [target]'s
/// folder, or null when no pattern of [docType] matches it.
String? _inTargetFolder(String docPath, MergedDocType docType, String target) {
  for (final path in docType.paths) {
    final pattern = PathPattern(path);
    if (pattern.valuesOf(docPath) case final values?) {
      return pattern.forTarget(target).fill(values);
    }
  }
  return null;
}

/// Returns the DocPath of every Markdown file under [docsRoot].
List<String> docPathsOf(Directory docsRoot) {
  if (!docsRoot.existsSync()) return [];
  // A file URI path always uses `/`, so no platform separator is split on.
  final prefixLength = docsRoot.uri.path.length;
  return [
    for (final entity in docsRoot.listSync(recursive: true, followLinks: false))
      if (entity is File && entity.path.endsWith('.md'))
        Uri.decodeComponent(entity.uri.path.substring(prefixLength)),
  ];
}
