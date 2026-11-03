import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';

/// A doc line that names another doc's file in text: the doc holding the line
/// and its 1-based file line.
typedef Mention = ({IndexedDoc doc, int line});

/// A character that ends a path written in prose.
final pathBreak = RegExp(r'''[\s`'"()\[\]<>{}|,;*~!?=]''');

/// A character that continues a file name.
final _nameChar = RegExp(r'[\p{L}\p{M}\p{N}_-]', unicode: true);

/// An inline link's `](` and its destination, `<…>` or a run up to a space
/// or `)`.
final _inlineDestination = RegExp(r'\]\(\s*(?:<[^>]*>|[^\s)]*)');

/// A link reference definition, from its label to its destination's end.
final _definition = RegExp(r'^ {0,3}\[[^\]]+\]:\s*(?:<[^>]*>|\S+)');

/// Returns the lines of other docs whose text names [target] by a path, plain
/// or in a code span, docs in tree order, each line once.
///
/// A path names the doc it reaches from its own doc, as a link would, else
/// the one doc of its file name it aligns with deepest: a bare file name that
/// several docs carry names none. Fenced code, link destinations, and a line
/// linking to [target] are skipped; a link is a reference, listed apart.
List<Mention> mentionsOf(DocIndex index, IndexedDoc target) {
  final fileName = _segmentsOf(target.docPath).last;
  final namesakes = {
    for (final doc in index.docs)
      if (_segmentsOf(doc.docPath) case final segments
          when segments.lastOrNull == fileName)
        doc.docPath: segments,
  };
  final mentions = <Mention>[];
  for (final doc in index.holding(fileName)) {
    if (doc.docPath == target.docPath) continue;
    final content = index.contentOf(doc);
    final facts = content.lineFacts;
    final linking = {
      for (final link in facts.links)
        if (link.target == target.docPath) link.line,
    };
    for (final (i, text) in lfLinesOf(toLf(content.text)).indexed) {
      final line = i + 1;
      if (linking.contains(line) || facts.isFenced(line)) continue;
      final prose = text
          .replaceAll(_definition, ' ')
          .replaceAll(_inlineDestination, '] ');
      if (_names(prose, doc.docPath, target.docPath, namesakes)) {
        mentions.add((doc: doc, line: line));
      }
    }
  }
  return mentions;
}

/// Whether [line], in the doc at DocPath [from], writes a path that names the
/// doc at DocPath [target] rather than another of its [namesakes].
bool _names(
  String line,
  String from,
  String target,
  Map<String, List<String>> namesakes,
) {
  final fileName = target.substring(target.lastIndexOf('/') + 1);
  for (
    var at = line.indexOf(fileName);
    at >= 0;
    at = line.indexOf(fileName, at + 1)
  ) {
    final end = at + fileName.length;
    if (!_opensName(line, at) || !_closesName(line, end)) continue;
    var start = at;
    while (start > 0 && !pathBreak.hasMatch(line[start - 1])) {
      start--;
    }
    final written = line.substring(start, end);
    if (_docNamedBy(written, from, namesakes) == target) return true;
  }
  return false;
}

/// Returns the DocPath of the one doc of [namesakes] that [written], in the
/// doc at DocPath [from], names, or null when it names none alone.
///
/// The doc [written] reaches from [from], as a link would, wins; else the doc
/// whose segments align with it deepest (see [_alignedLength]), and a tie at
/// that depth names none.
String? _docNamedBy(
  String written,
  String from,
  Map<String, List<String>> namesakes,
) {
  if (resolveDocLink(written, from) case DocTarget(:final docPath)
      when namesakes.containsKey(docPath)) {
    return docPath;
  }
  final segments = _segmentsOf(written);
  String? deepest;
  var depth = 0;
  for (final MapEntry(key: docPath, value: docSegments) in namesakes.entries) {
    final shared = _alignedLength(segments, docSegments);
    if (shared > depth) {
      deepest = docPath;
      depth = shared;
    } else if (shared == depth) {
      deepest = null;
    }
  }
  return deepest;
}

/// Whether a file name starting at [at] in [line] is not the tail of a
/// longer name, such as `INDEX.md` in `MY_INDEX.md`.
bool _opensName(String line, int at) {
  if (at == 0) return true;
  final before = line[at - 1];
  return before == '/' || pathBreak.hasMatch(before);
}

/// Whether a file name ending at [end] in [line] is not the head of a longer
/// name or path, such as `INDEX.md` in `INDEX.md.bak` or `INDEX.md/x`.
///
/// A `.` closing a sentence still ends it.
bool _closesName(String line, int end) {
  if (end == line.length) return true;
  final after = line[end];
  if (after == '/' || _nameChar.hasMatch(after)) return false;
  if (after != '.' || end + 1 == line.length) return true;
  return !_nameChar.hasMatch(line[end + 1]);
}

/// Returns the segments of [path] without empty, `.`, and `..` segments.
List<String> _segmentsOf(String path) => [
  for (final segment in path.split('/'))
    if (segment.isNotEmpty && segment != '.' && segment != '..') segment,
];

/// Returns how many trailing segments [a] and [b] share when the shorter is
/// a suffix of the longer, else 0.
int _alignedLength(List<String> a, List<String> b) {
  var shared = 0;
  while (shared < a.length &&
      shared < b.length &&
      a[a.length - 1 - shared] == b[b.length - 1 - shared]) {
    shared++;
  }
  final shorter = a.length < b.length ? a.length : b.length;
  return shared == shorter ? shared : 0;
}
