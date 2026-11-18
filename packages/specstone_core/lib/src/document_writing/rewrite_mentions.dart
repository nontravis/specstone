import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/doc_model/models/text_range.dart';
import 'package:specstone_core/src/doc_model/name_mentions.dart'
    show nameMentionsInFile;
import 'package:specstone_core/src/document_writing/models/counted_rewrite.dart';
import 'package:specstone_core/src/document_writing/models/path_move.dart';
import 'package:specstone_core/src/document_writing/models/renamed_names.dart';
import 'package:specstone_core/src/document_writing/moved_paths.dart';
import 'package:specstone_core/src/index_query/doc_mentions.dart'
    show pathBreak;
import 'package:specstone_core/src/index_query/link_scan.dart' show linkScanOf;
import 'package:specstone_core/src/index_query/models/scanned_destination.dart';
import 'package:specstone_core/src/portable_path.dart';
import 'package:specstone_core/src/rendering/line_ending.dart' show toLf;

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
/// changes only when that path is an [isPortablePath] and [exists] holds for
/// it, as a path from the project root (see [projectFilePathOf]), and the
/// shared decision of
/// [movedRelativePath] says the text no longer reaches the moved file. A
/// token holding an escape, a web address, a path of dots alone, and a word
/// with neither a `/` nor a file extension are not mentions. [exists] runs
/// once per path.
///
/// Only the text after the frontmatter is read. Fenced code and link
/// destinations keep every byte, since the link rewrite owns the
/// destinations; link text is prose.
CountedRewrite? rewritePathMentions(
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
      for (final TextRange(:start, :end) in _tokensOf(line)) {
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
  return CountedRewrite(
    lfText: lfText.substring(0, lfText.length - body.length) + result,
    count: edits.length,
  );
}

/// Returns, per character of [body], whether a link destination the link
/// scan reads, inline or in a definition, covers it, as the mention scan
/// reads them.
List<bool> _destinationMask(String body) {
  final mask = List.filled(body.length, false);
  for (final ScannedDestination(:start, :end) in linkScanOf(
    body,
    firstLine: 1,
  ).destinations) {
    mask.fillRange(start, end, true);
  }
  return mask;
}

/// Returns the runs of [line] that no path-break character splits.
Iterable<TextRange> _tokensOf(String line) sync* {
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
    yield TextRange(start: start, end: i);
  }
}

/// A path mention as written and the text that replaces it.
final class _PathEdit {
  const new({required this.path, required this.text});

  final String path;
  final String text;
}

/// Returns the written path of [token] and the text that replaces it, or
/// null when [token] is no mention that changes.
_PathEdit? _editFor(
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
  if (target == null ||
      !isPortablePath(target) ||
      !exists(projectFilePathOf(target, docPath))) {
    return null;
  }
  final text = path.endsWith('/') ? '$after/' : after;
  return text == path ? null : _PathEdit(path: path, text: text);
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

/// Returns [text], a file of [extension], with the Name of each doc-name
/// mention of a doc in [renamed] set to its new name, or null when none
/// changes.
///
/// [renamed] maps `(doc type id, old name)` to the new name. The mention's
/// `<doc type>:` prefix and `#<section key>` stay as written; a bare name
/// takes the rename only when every renamed doc called so agrees on one new
/// name. Mentions are read as [nameMentionsInFile] reads them from the text
/// with `\r\n` as `\n`, a markdown file's `mermaid` tokens included, and every
/// byte outside a changed Name, line ends included, stays.
String? rewriteNameMentions(
  String text,
  String extension,
  RenamedNames renamed,
) {
  if (renamed.isEmpty) return null;
  final edits = <({int line, int column, int length, String text})>[];
  for (final mention in nameMentionsInFile(
    toLf(text),
    extension,
    withMermaid: true,
  )) {
    final name = renamed.newNameFor(mention.address);
    if (name == null) continue;
    final address = mention.address;
    final prefix = address.typeId == null ? '' : '${address.typeId}:';
    final kept = mention.text.substring(address.docPart.length);
    edits.add((
      line: mention.line,
      column: mention.column,
      length: mention.text.length,
      text: '$prefix$name$kept',
    ));
  }
  if (edits.isEmpty) return null;
  final lines = text.split('\n');
  for (final edit in edits.reversed) {
    final line = lines[edit.line - 1];
    lines[edit.line - 1] =
        line.substring(0, edit.column) +
        edit.text +
        line.substring(edit.column + edit.length);
  }
  return lines.join('\n');
}
