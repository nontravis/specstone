import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart' show docsFolderName;
import 'package:specstone_core/src/document_writing/models/path_move.dart';
import 'package:specstone_core/src/document_writing/rewrite_mentions.dart'
    show rewritePathMentions;
import 'package:specstone_core/src/document_writing/rewrite_refs.dart'
    show rewriteDocLinksCounted;
import 'package:specstone_core/src/setup_migration/models/labeled_rewrite.dart';

/// Rewrites the links and path mentions of a doc for a set of moves, and
/// renames a section header.
abstract final class MoveRewrites {
  /// Points each relative link of [lf], to a file of any extension or a
  /// folder, at the path [moves] leave its target at.
  ///
  /// [docPath] is where the doc sits before the moves; a link that leaves the
  /// docs root follows a doc that changes depth. The label is `1 link` or
  /// `<n> links`, and null when no link changes.
  static LabeledRewrite links(
    String lf, {
    required String docPath,
    required List<PathMove> moves,
  }) {
    final result = rewriteDocLinksCounted(lf, docPath: docPath, moves: moves);
    if (result == null) return LabeledRewrite(lf: lf, label: null);
    return LabeledRewrite(
      lf: result.lfText,
      label: result.count == 1 ? '1 link' : '${result.count} links',
    );
  }

  /// Points each path mention of [lf] that names a file or folder [exists] at
  /// the path [moves] leave it at.
  ///
  /// [docPath] is where the doc sits before the moves, and [exists] reads the
  /// legacy tree as it stands before them, from the docs root. The label is
  /// `1 mention` or `<n> mentions`, and null when no mention changes.
  static LabeledRewrite mentions(
    String lf, {
    required String docPath,
    required List<PathMove> moves,
    required bool Function(String path) exists,
  }) {
    final result = rewritePathMentions(
      lf,
      docPath: docPath,
      moves: moves,
      exists: (projectPath) => exists(_docsRootPathOf(projectPath)),
    );
    if (result == null) return LabeledRewrite(lf: lf, label: null);
    return LabeledRewrite(
      lf: result.lfText,
      label: result.count == 1 ? '1 mention' : '${result.count} mentions',
    );
  }

  /// Returns [lf] with the `##` header [from] written as [to], or [lf] when it
  /// has no such section.
  static String headerRenamed(String lf, String from, String to) {
    final doc = Doc.parse(lf);
    final index = doc.sections.indexWhere((s) => s.headerText == from);
    if (index < 0) return lf;
    final lines = doc.afterFrontmatter.split('\n');
    final lineAt = doc.sectionLineIndexes[index];
    lines[lineAt] = lines[lineAt].replaceRange(
      0,
      doc.sections[index].headerLine.length,
      '## $to',
    );
    final frontmatterLength = lf.length - doc.afterFrontmatter.length;
    return lf.substring(0, frontmatterLength) + lines.join('\n');
  }

  /// Returns [projectPath], a path from the project root, as a path from the
  /// docs root, leaving it by `../` when it lies outside the docs folder.
  static String _docsRootPathOf(String projectPath) =>
      projectPath.startsWith('$docsFolderName/')
      ? projectPath.substring(docsFolderName.length + 1)
      : '../$projectPath';
}
