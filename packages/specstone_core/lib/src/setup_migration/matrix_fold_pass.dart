import 'package:specstone_core/src/index_query/indexed_doc.dart'
    show IndexedDoc, docNameOf, frType;
import 'package:specstone_core/src/index_query/parents.dart'
    show resolveParents;
import 'package:specstone_core/src/setup_migration/feature_relative.dart';
import 'package:specstone_core/src/setup_migration/matrix_fold.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/models/matrix_mode.dart';

/// A typed doc as the pass reads it: its DocPath after the moves, its doc type
/// and code target, and its LF text after the passes before this one.
typedef MatrixFoldDoc = ({
  String plannedPath,
  MergedDocType? type,
  String? target,
  String lf,
});

/// The matrix fold pass of an upgrade: each record's per-edge-case rows of an
/// FR of its feature become one per-FR row.
///
/// The one decision whether a project holds a foldable row is [plan] returning
/// non-null, which the plan and the run kind both read.
final class MatrixFoldPass {
  const new _({
    required this.recordEdits,
    required this.planLine,
    required this.json,
  });

  /// Plans the pass over [docs] under [mode]; null when the mode is
  /// `edge_case`, [set] holds no record doc type, or no record holds a
  /// foldable row.
  static MatrixFoldPass? plan(
    MatrixMode mode,
    MergedSet set,
    List<MatrixFoldDoc> docs,
  ) {
    final recordType = set.recordDocType;
    if (mode == MatrixMode.edgeCase || recordType == null) return null;
    final frNames = _frNamesByFeature(set, docs);
    final edits = <String, String>{};
    var rowsBefore = 0;
    var rowsAfter = 0;
    for (final doc in docs) {
      final type = doc.type;
      if (type == null || type.id != recordType.id) continue;
      final feature = docNameOf(doc.plannedPath, type, target: doc.target);
      final folded = foldMatrixRows(
        doc.lf,
        recordType,
        frNames[feature] ?? const {},
      );
      if (folded == null) continue;
      edits[doc.plannedPath] = folded.text;
      rowsBefore += folded.rowsBefore;
      rowsAfter += folded.rowsAfter;
    }
    if (edits.isEmpty) return null;
    return MatrixFoldPass._(
      recordEdits: edits,
      planLine:
          'matrix rows: $rowsBefore rows folded into $rowsAfter rows in '
          '${edits.length} records',
      json: {'folded': edits.keys.toList()..sort(compareCodePoints)},
    );
  }

  /// The folded text of each record the pass rewrites, by DocPath.
  final Map<String, String> recordEdits;

  /// The plan's `matrix rows:` line.
  final String planLine;

  /// The `matrixRows` object of the JSON plan.
  final Map<String, Object?> json;
}

/// Returns the FR names of each feature of the typed [docs], each relative to
/// its feature, by the feature's name.
Map<String, Set<String>> _frNamesByFeature(
  MergedSet set,
  List<MatrixFoldDoc> docs,
) {
  final indexed = {
    for (final doc in docs)
      if (doc.type case final type?)
        doc.plannedPath: IndexedDoc(
          docPath: doc.plannedPath,
          docTypeId: type.id,
          name: docNameOf(doc.plannedPath, type, target: doc.target),
          frontmatter: const {},
          tokens: 0,
        ),
  };
  final parents = resolveParents(indexed.values, set).parents;
  final names = <String, Set<String>>{};
  for (final doc in indexed.values) {
    if (doc.docTypeId != frType) continue;
    final landing = featureRelativeOf(doc, indexed, parents);
    if (landing == null) continue;
    (names[landing.feature.name] ??= {}).add(landing.relative);
  }
  return names;
}
