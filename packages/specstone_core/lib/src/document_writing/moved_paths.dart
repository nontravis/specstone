import 'package:specstone_core/src/doc_model/doc_link.dart';

/// One move of a doc or a folder, as DocPaths.
///
/// A folder ends in `/`, a file does not.
typedef PathMove = ({String from, String to});

/// Returns [docPath] after the first of [moves] whose `from` is the path
/// itself or a folder holding it.
String movedPath(String docPath, List<PathMove> moves) {
  for (final move in moves) {
    final holds = move.from.endsWith('/')
        ? docPath.startsWith(move.from)
        : docPath == move.from;
    if (holds) return move.to + docPath.substring(move.from.length);
  }
  return docPath;
}

/// Returns the `/`-separated path from the folder of [fromDocPath] to
/// [toDocPath], with `..` segments up to the common folder.
String relativeHref(String fromDocPath, String toDocPath) {
  final fromFolder = fromDocPath.split('/')..removeLast();
  final to = toDocPath.split('/');
  var common = 0;
  while (common < fromFolder.length &&
      common < to.length - 1 &&
      fromFolder[common] == to[common]) {
    common++;
  }
  return [
    ...List.filled(fromFolder.length - common, '..'),
    ...to.skip(common),
  ].join('/');
}

/// Returns the decoded path [path], written in the doc at [docPath], must
/// carry after [moves], or null when it keeps its text.
///
/// [path] has no `?` or `#` part. It keeps its text when, read from the doc's
/// place after the moves, it still reaches the moved target, which it may do
/// by leaving a moved folder and re-entering it, or when it names no file
/// path (see [relativeFilePathOf]). A leading `./` stays. A link and a prose
/// mention share this one decision.
String? movedRelativePath(String path, String docPath, List<PathMove> moves) {
  final target = relativeFilePathOf(path, docPath);
  if (target == null) return null;
  final movedDoc = movedPath(docPath, moves);
  final movedTarget = movedFilePath(target, moves);
  if (relativeFilePathOf(path, movedDoc) == movedTarget) return null;
  final after = relativeHref(movedDoc, movedTarget);
  return path.startsWith('./') ? './$after' : after;
}

/// Returns [path], a file or a folder under the docs root or outside it,
/// after [moves].
///
/// A folder path has no trailing `/`, so it is moved as the folder it names
/// when no move names it as a file.
String movedFilePath(String path, List<PathMove> moves) {
  final moved = movedPath(path, moves);
  if (moved != path) return moved;
  final folder = movedPath('$path/', moves);
  return folder == '$path/' ? path : folder.substring(0, folder.length - 1);
}
