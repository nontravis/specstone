import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';

/// A doc line that names another doc's file in text: the DocPath of the doc
/// holding the line and its 1-based file line.
typedef Mention = ({String path, int line});

/// A character that ends a path written in prose.
final _pathBreak = RegExp(r'''[\s`'"()\[\]<>{}|,;*~!?=]''');

/// A character that continues a file name.
final _nameChar = RegExp(r'[\p{L}\p{M}\p{N}_-]', unicode: true);

/// An inline link's `](` and its destination, `<…>` or a run up to a space
/// or `)`.
final _inlineDestination = RegExp(r'\]\(\s*(?:<[^>]*>|[^\s)]*)');

/// A link reference definition, from its label to its destination's end.
final _definition = RegExp(r'^ {0,3}\[[^\]]+\]:\s*(?:<[^>]*>|\S+)');

/// Returns the lines of other docs that name [target]'s file in text, docs
/// in tree order, each line once.
///
/// A line names it with a path ending in the target's file name, such as the
/// bare file name or the DocPath, plain or in a code span. The path's
/// segments and the DocPath's agree, one a suffix of the other, and no other
/// doc of that file name shares more of them: a bare file name names every
/// doc carrying it, `prds/INDEX.md` never names `specs/INDEX.md`. Fenced code
/// and link destinations are skipped, and so is a line linking to [target]:
/// a link is a reference, listed apart.
List<Mention> mentionsOf(DocIndex index, IndexedDoc target) {
  final targetSegments = _segmentsOf(target.docPath);
  final fileName = targetSegments.last;
  final namesakes = [
    for (final doc in index.docs)
      if (_segmentsOf(doc.docPath) case final segments
          when segments.lastOrNull == fileName)
        segments,
  ];
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
      if (_names(prose, targetSegments, namesakes)) {
        mentions.add((path: doc.docPath, line: line));
      }
    }
  }
  return mentions;
}

/// Whether [line] writes a path that names the doc at [target] segments
/// rather than one of its [namesakes].
bool _names(String line, List<String> target, List<List<String>> namesakes) {
  final fileName = target.last;
  for (
    var at = line.indexOf(fileName);
    at >= 0;
    at = line.indexOf(fileName, at + 1)
  ) {
    final end = at + fileName.length;
    if (!_opensName(line, at) || !_closesName(line, end)) continue;
    var start = at;
    while (start > 0 && !_pathBreak.hasMatch(line[start - 1])) {
      start--;
    }
    final written = _segmentsOf(line.substring(start, end));
    final shared = _alignedLength(written, target);
    if (shared == 0) continue;
    if (namesakes.every((doc) => _alignedLength(written, doc) <= shared)) {
      return true;
    }
  }
  return false;
}

/// Whether a file name starting at [at] in [line] is not the tail of a
/// longer name, such as `INDEX.md` in `MY_INDEX.md`.
bool _opensName(String line, int at) {
  if (at == 0) return true;
  final before = line[at - 1];
  return before == '/' || _pathBreak.hasMatch(before);
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
