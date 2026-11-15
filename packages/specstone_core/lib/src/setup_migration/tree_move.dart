import 'dart:io';

import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/doc_model/path_pattern.dart';
import 'package:specstone_core/src/doc_model/records_root.dart';
import 'package:specstone_core/src/document_writing/moved_paths.dart'
    show PathMove;
import 'package:specstone_core/src/templates/code_target.dart' show twinNamesOf;
import 'package:specstone_core/src/templates/merged_set.dart';

/// Returns the moves that put each per-target doc at a one-target path into
/// the first of [targetNames], each with its placeholder values kept.
///
/// With fewer than two targets the spec root stays as it is, so nothing moves.
/// A doc moves only when no target's pattern set matches its path and a
/// per-target doc type's one-target pattern does, or one of [olderPatterns]
/// does; a doc already in a target folder and a file no per-target doc type
/// matches stay. [docPaths] are the DocPaths under the docs root.
///
/// [olderPatterns] are the one-target patterns that a pack's `move_file` steps
/// of per-target doc types read their docs from, which the doc types of [set]
/// no longer hold.
List<PathMove> treeMovesOf(
  List<String> docPaths,
  MergedSet set, {
  required List<String> targetNames,
  List<String> olderPatterns = const [],
}) {
  if (twinNamesOf(targetNames).isEmpty) return const [];
  final inTargets = DocTypeMatcher(set, targetNames: targetNames);
  final oneTarget = DocTypeMatcher(set, targetNames: const []);
  final first = targetNames.first;
  final moves = <PathMove>[];
  for (final path in docPaths) {
    if (inTargets.match(path) is! NoDocType) continue;
    final match = oneTarget.match(path);
    final patterns = [
      if (match is MatchedDocType && match.docType.isPerTarget)
        ...match.docType.paths,
      ...olderPatterns,
    ];
    if (_inTargetFolder(path, patterns, first) case final to?) {
      moves.add((from: path, to: to));
    }
  }
  return moves;
}

/// Returns [docPath] at the same path in [target]'s folder, or null when no
/// one of [patterns] matches it.
String? _inTargetFolder(String docPath, List<String> patterns, String target) {
  for (final path in patterns) {
    final pattern = PathPattern(path);
    if (pattern.valuesOf(docPath) case final values?) {
      return pattern.forTarget(target).fill(values);
    }
  }
  return null;
}

/// Returns the DocPath of every Markdown file under [docsRoot], then of every
/// one under the records root of [projectRoot].
List<String> docPathsOf(Directory docsRoot, Directory projectRoot) => [
  ..._markdownUnder(docsRoot, ''),
  ...recordDocPathsOf(projectRoot),
];

/// Returns the DocPath of every Markdown file under the records root of
/// [projectRoot]; none when it has no records root.
List<String> recordDocPathsOf(Directory projectRoot) => [
  if (recordsRootOf(projectRoot) case final records?)
    ..._markdownUnder(records, recordsRootDocPath),
];

/// Returns the DocPath, opening with [prefix], of every Markdown file under
/// [folder]; none when it does not exist.
List<String> _markdownUnder(Directory folder, String prefix) {
  if (!folder.existsSync()) return [];
  // A file URI path always uses `/`, so no platform separator is split on.
  final prefixLength = folder.uri.path.length;
  return [
    for (final entity in folder.listSync(recursive: true, followLinks: false))
      if (entity is File && entity.path.endsWith('.md'))
        prefix + Uri.decodeComponent(entity.uri.path.substring(prefixLength)),
  ];
}
