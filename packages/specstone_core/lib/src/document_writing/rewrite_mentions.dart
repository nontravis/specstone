import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/document_writing/link_destinations.dart';
import 'package:specstone_core/src/document_writing/moved_paths.dart';
import 'package:specstone_core/src/index_query/doc_mentions.dart'
    show pathBreak;

/// A closing `.`, `,`, `;`, or `:` that prose adds after a path.
final _closingMark = RegExp(r'[.,;:]$');

/// A file extension: a `.` and letters or digits that end a path.
final _extension = RegExp(r'\.[A-Za-z0-9]+$');

/// A line, or line and column, suffix such as `:12` or `:12:5`.
final _lineSuffix = RegExp(r'(?::\d+)+$');

/// Returns [lfText] with each path mention set to the path [moves] leave its
/// file at, with the number of mentions changed, or null when none changes.
///
/// A mention is prose text, plain or in a code span, that reads as a relative
/// path from the doc at [docPath], read before the moves. Its `#` suffix, a
/// closing mark, and a line suffix are not part of the path and stay. It
/// changes only when [exists] holds for the path it names, given as
/// [relativeFilePathOf] gives it, and the shared decision of
/// [movedRelativePath] says the text no longer reaches the moved file. A
/// token holding an escape, a web address, a path of dots alone, and a word
/// with neither a `/` nor a file extension are not mentions. [exists] runs
/// once per path.
///
/// Only the text after the frontmatter is read. Fenced code and link
/// destinations keep every byte, since the link rewrite owns the
/// destinations; link text is prose.
({String lfText, int count})? rewritePathMentions(
  String lfText, {
  required String docPath,
  required List<PathMove> moves,
  required bool Function(String path) exists,
}) {
  final body = Doc.parse(lfText).afterFrontmatter;
  final lines = body.split('\n');
  final fenced = fencedLines(lines);
  final inDestination = _destinationMask(body);
  final edits = <({int start, int end, String text})>[];
  // A prose word is stat'ed once per run, however often it repeats.
  final known = <String, bool>{};
  bool existsOnce(String path) => known.putIfAbsent(path, () => exists(path));
  var lineStart = 0;
  for (final (i, line) in lines.indexed) {
    if (!fenced[i]) {
      for (final (:start, :end) in _tokensOf(line)) {
        final edit = _editFor(
          line.substring(start, end),
          docPath,
          moves,
          existsOnce,
        );
        if (edit == null) continue;
        final from = lineStart + start;
        final to = from + edit.path.length;
        if (inDestination.sublist(from, to).any((masked) => masked)) continue;
        edits.add((start: from, end: to, text: edit.text));
      }
    }
    lineStart += line.length + 1;
  }
  if (edits.isEmpty) return null;
  var result = body;
  for (final edit in edits.reversed) {
    result = result.replaceRange(edit.start, edit.end, edit.text);
  }
  return (
    lfText: lfText.substring(0, lfText.length - body.length) + result,
    count: edits.length,
  );
}

/// Returns, per character of [body], whether a link destination covers it.
List<bool> _destinationMask(String body) {
  final mask = List.filled(body.length, false);
  for (final span in destinationsIn(body)) {
    mask.fillRange(span.start, span.end, true);
  }
  return mask;
}

/// Returns the runs of [line] that no path-break character splits.
Iterable<({int start, int end})> _tokensOf(String line) sync* {
  var i = 0;
  while (i < line.length) {
    if (pathBreak.hasMatch(line[i])) {
      i++;
      continue;
    }
    final start = i;
    while (i < line.length && !pathBreak.hasMatch(line[i])) {
      i++;
    }
    yield (start: start, end: i);
  }
}

/// Returns the written path of [token] and the text that replaces it, or
/// null when [token] is no mention that changes.
({String path, String text})? _editFor(
  String token,
  String docPath,
  List<PathMove> moves,
  bool Function(String path) exists,
) {
  final path = _pathOf(token);
  if (path == null) return null;
  final after = movedRelativePath(path, docPath, moves);
  if (after == null) return null;
  final target = relativeFilePathOf(path, docPath);
  if (target == null || !exists(target)) return null;
  final text = path.endsWith('/') ? '$after/' : after;
  return text == path ? null : (path: path, text: text);
}

/// Returns the path part of [token], or null when it holds none a prose
/// reader could mean.
String? _pathOf(String token) {
  final hash = token.indexOf('#');
  final path = (hash < 0 ? token : token.substring(0, hash))
      .replaceFirst(_closingMark, '')
      .replaceFirst(_lineSuffix, '');
  // Dots and slashes alone (`...`, `../..`) name an ancestor folder that
  // exists, so an ellipsis would be rewritten when its doc moves.
  final named = path
      .split('/')
      .any((s) => s.isNotEmpty && s != '.' && s != '..');
  // A plain word is no path, though a sibling may carry its name: a mention
  // holds a `/` or ends in a file extension.
  final shaped = path.contains('/') || _extension.hasMatch(path);
  // Prose carries no percent escape, and the path resolver would decode one.
  return named && shaped && !path.contains('%') ? path : null;
}
