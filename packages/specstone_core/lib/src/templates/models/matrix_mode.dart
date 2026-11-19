import 'package:specstone_core/src/index_query/models/matrix_line.dart'
    show RowForm;

/// The Verification matrix mode the config's `verification_coverage:` names.
enum MatrixMode {
  off,
  fr,
  edgeCase;

  /// Whether the matrix is on: any mode but [off].
  bool get isOn => this != off;

  /// The form of row the mode reads: per-FR for [off] and [fr], per-edge-case
  /// for [edgeCase].
  RowForm get readsForm => switch (this) {
    off || fr => RowForm.perFr,
    edgeCase => RowForm.perEdgeCase,
  };
}
