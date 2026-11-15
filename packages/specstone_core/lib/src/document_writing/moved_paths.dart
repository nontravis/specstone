import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/doc_model/percent_decode.dart'
    show percentDecoded;
import 'package:specstone_core/src/doc_model/records_root.dart'
    show projectPathOfDocPath;

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

/// Returns [moves] with each path as a path from the project root.
List<PathMove> projectMovesOf(List<PathMove> moves) => [
  for (final move in moves)
    (from: projectPathOfDocPath(move.from), to: projectPathOfDocPath(move.to)),
];

/// Returns the `/`-separated path from the folder of [fromDocPath] to
/// [toDocPath], with `..` segments up to the common folder.
///
/// An empty [toDocPath] names the root of both, and the path to it ends in
/// no `/`.
String relativeHref(String fromDocPath, String toDocPath) {
  final fromFolder = fromDocPath.split('/')..removeLast();
  final to = toDocPath.isEmpty ? <String>[] : toDocPath.split('/');
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
/// path (see [relativeFilePathOf]). A leading `./` stays unless the new path
/// starts with `../`. A link and a prose mention share this one decision.
///
/// The comparison runs in project-root paths, so a link between a doc and a
/// record, which sit under different roots, follows a move of either.
String? movedRelativePath(String path, String docPath, List<PathMove> moves) {
  final target = relativeFilePathOf(path, docPath);
  if (target == null) return null;
  final projectMoves = projectMovesOf(moves);
  final movedDoc = movedPath(docPath, moves);
  final movedTarget = movedFilePath(
    projectFilePathOf(target, docPath),
    projectMoves,
  );
  final kept = relativeFilePathOf(path, movedDoc);
  if (kept != null && projectFilePathOf(kept, movedDoc) == movedTarget) {
    return null;
  }
  final after = relativeHref(projectPathOfDocPath(movedDoc), movedTarget);
  return _keptDotSlash(path, after);
}

/// Returns [path], written in the doc at [fromDocPath], as the path that
/// reaches the same file or folder from the doc at [toDocPath], or null when
/// it is unchanged.
///
/// [path] has no `?` or `#` part; an empty one names [fromDocPath] itself.
/// Works on the segments as written, so an escape, an encoded slash
/// included, and a trailing `/` stay; a `.` or `..` segment, decoded, moves
/// the walk, which may leave the docs root.
String? rebasedHref(String path, String fromDocPath, String toDocPath) {
  final target = path.isEmpty
      ? fromDocPath.split('/')
      : _walked(_folderOf(fromDocPath), path.split('/'));
  final from = _folderOf(toDocPath);
  var common = 0;
  while (common < from.length &&
      common < target.length &&
      from[common] == percentDecoded(target[common])) {
    common++;
  }
  final segments = [
    ...List.filled(from.length - common, '..'),
    ...target.skip(common),
  ];
  final joined = segments.isEmpty ? '.' : segments.join('/');
  final slash = path.endsWith('/') ? '/' : '';
  final after = _keptDotSlash(path, '$joined$slash');
  return after == path ? null : after;
}

/// Returns [after] with the leading `./` of [path] when [after] opens with
/// neither `../` nor `.` alone.
String _keptDotSlash(String path, String after) =>
    path.startsWith('./') &&
        !after.startsWith('../') &&
        !after.startsWith('./') &&
        after != '.'
    ? './$after'
    : after;

/// Returns the folder segments of [docPath].
List<String> _folderOf(String docPath) => docPath.split('/')..removeLast();

/// Returns [folder] after walking [segments] as written: an empty or `.`
/// segment stays, `..` pops, or is kept once the walk leaves the root.
List<String> _walked(List<String> folder, List<String> segments) {
  final walk = [...folder];
  for (final segment in segments) {
    switch (percentDecoded(segment)) {
      case '' || '.':
        continue;
      case '..':
        if (walk.isEmpty || walk.last == '..') {
          walk.add('..');
        } else {
          walk.removeLast();
        }
      default:
        walk.add(segment);
    }
  }
  return walk;
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
