import 'package:specstone_core/src/doc_model/records_root.dart'
    show projectPathOfDocPath;
import 'package:specstone_core/src/document_writing/models/path_move.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';

/// Names how a run compares a path and the folders a list of moves empties.
abstract final class PathMoves {
  /// Returns [path] as every legacy path comparison sees it.
  ///
  /// Dart's locale-free simple Unicode lowercase, so `Ä` and `ä` fold too. It
  /// is not a file system's fold: NTFS and APFS fold some names it keeps apart
  /// (`ς` and `Σ`) and keep apart some it folds (`İ` and `i`).
  static String caseBlindPath(String path) => path.toLowerCase();

  /// Returns the folders the moves empty, the deepest first, as ProjectPaths.
  static List<String> prunesOf(List<PathMove> moves) => {
    for (final move in moves)
      projectPathOfDocPath(move.from.substring(0, move.from.lastIndexOf('/'))),
  }.toList()..sort((a, b) => compareCodePoints(b, a));
}
