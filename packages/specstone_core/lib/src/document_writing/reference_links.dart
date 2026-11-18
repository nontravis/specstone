import 'dart:math' show max;

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/markdown_body.dart'
    show holdsLinkSyntax;
import 'package:specstone_core/src/document_writing/rewrite_refs.dart'
    show destinationWithPath, isAngleBracketed;
import 'package:specstone_core/src/index_query/link_places.dart'
    show hrefDestinationsOf, sourceHrefsOf;
import 'package:specstone_core/src/index_query/link_scan.dart' show linkScanOf;
import 'package:specstone_core/src/index_query/models/href_destination.dart';
import 'package:specstone_core/src/index_query/models/href_destinations.dart';
import 'package:specstone_core/src/index_query/models/link_scan.dart';
import 'package:specstone_core/src/rendering/skill_references.dart';

const _bang = 0x21;
final _backtickRun = RegExp('`+');

/// Returns [lfText], a doc's LF text, with each link and image after its
/// frontmatter rewritten as [actionOf] gives for its href; a [LinkRewriter].
///
/// A [RetargetLink] sets the path of an inline link's destination, or of the
/// definition a reference link reads; a [LinkAsText] writes the whole link
/// as its text and its path in a code span, and leaves a definition as
/// written. A link in a code span or a fenced block stays.
String rewriteReferenceLinks(
  String lfText,
  LinkAction Function(String href) actionOf,
) {
  final body = Doc.parse(lfText).afterFrontmatter;
  if (!holdsLinkSyntax(body)) return lfText;
  final scan = linkScanOf(body, firstLine: 1);
  final edits = [
    ..._shownLinks(body, scan, actionOf),
    ..._retargetedPaths(body, scan, actionOf),
  ];
  if (edits.isEmpty) return lfText;
  // Outer first, so an edit inside another one is written by that one.
  edits.sort((a, b) => a.start != b.start ? a.start - b.start : b.end - a.end);
  final head = lfText.substring(0, lfText.length - body.length);
  return '$head${_rendered(body, 0, body.length, edits)}';
}

// MARK: - Edits

/// One replacement of a range of the body. Two edits never cross: they lie
/// apart, or one holds the other, as a link holds an image in its text.
sealed class _Edit {
  new(this.start, this.end);

  final int start;
  final int end;
}

/// A destination written anew.
final class _Replaced extends _Edit {
  new(super.start, super.end, this.text);

  final String text;
}

/// A link or image written as its text and [path] in a code span.
final class _Shown extends _Edit {
  new(
    super.start,
    super.end, {
    required this.textStart,
    required this.textEnd,
    required this.path,
  });

  final int textStart;
  final int textEnd;
  final String path;
}

/// Returns an edit per link or image whose href [actionOf] shows as text.
///
/// A link takes the href `markdown` gives it, or, when the readers disagree,
/// its destination as written.
List<_Edit> _shownLinks(
  String body,
  LinkScan scan,
  LinkAction Function(String href) actionOf,
) {
  final hrefs = sourceHrefsOf(body, scan.sources);
  return [
    for (final (index, source) in scan.sources.indexed)
      if ((source.textEnd, hrefs?[index] ?? source.shown) case (
        final textEnd?,
        final href?,
      ))
        if (actionOf(href) case LinkAsText(:final path))
          _Shown(
            source.offset,
            source.end,
            textStart:
                source.offset +
                (body.codeUnitAt(source.offset) == _bang ? 2 : 1),
            textEnd: textEnd,
            path: path,
          ),
  ];
}

/// Returns an edit per inline or definition destination whose href
/// [actionOf] retargets, its `?` and `#` part kept.
List<_Edit> _retargetedPaths(
  String body,
  LinkScan scan,
  LinkAction Function(String href) actionOf,
) {
  final HrefDestinations(:destinations) = hrefDestinationsOf(
    body,
    scan,
    canMove: (href) => actionOf(href) is RetargetLink,
  );
  return [
    for (final HrefDestination(:start, :end, :href, :kind) in destinations)
      if (actionOf(href) case RetargetLink(:final path))
        _Replaced(
          start,
          end,
          destinationWithPath(
            body.substring(start, end),
            kind,
            path,
            isAngle: isAngleBracketed(body, start, kind),
          ),
        ),
  ];
}

// MARK: - Writing

/// Returns [body] from [from] to [to] with each edit of [edits], sorted outer
/// first, that lies in that range applied.
String _rendered(String body, int from, int to, List<_Edit> edits) {
  final out = StringBuffer();
  var at = from;
  for (final edit in edits) {
    if (edit.start < at || edit.end > to) continue;
    out
      ..write(body.substring(at, edit.start))
      ..write(switch (edit) {
        _Replaced(:final text) => text,
        _Shown(:final textStart, :final textEnd, :final path) =>
          '${_rendered(body, textStart, textEnd, edits)} '
              '(${_codeSpan(path)})',
      });
    at = edit.end;
  }
  return (out..write(body.substring(at, to))).toString();
}

/// Returns [text] in a code span whose backtick run is longer than any run
/// [text] holds.
String _codeSpan(String text) {
  final longest = _backtickRun
      .allMatches(text)
      .fold(0, (length, run) => max(length, run.end - run.start));
  final fence = '`' * (longest + 1);
  final pad = text.startsWith('`') || text.endsWith('`') ? ' ' : '';
  return '$fence$pad$text$pad$fence';
}
