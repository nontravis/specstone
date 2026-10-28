import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/index_query/link_places.dart';
import 'package:specstone_core/src/index_query/section_counts.dart';
import 'package:yaml/yaml.dart';

const _space = 0x20;
const _backtick = 0x60;
const _tilde = 0x7E;

/// The 1-based file lines `first` through `last`, both included.
typedef LineRange = ({int first, int last});

/// The frontmatter YAML read once: the mapping it holds, or the line that
/// makes it invalid.
///
/// Both are null for an empty or comment-only block. `errorLine` is the line
/// the YAML parser names, or 1 when the block is no mapping.
typedef FrontmatterYaml = ({YamlMap? map, int? errorLine});

/// Returns [source], the frontmatter lines between the `---` delimiters, as
/// a mapping or the line that makes it invalid.
///
/// File line numbers are the node line plus 2, since [source] starts on line 2.
FrontmatterYaml parseFrontmatterYaml(String source) {
  try {
    final node = loadYamlNode(source);
    if (node is YamlMap) return (map: node, errorLine: null);
    if (node is YamlScalar && node.value == null) {
      return (map: null, errorLine: null);
    }
    return (map: null, errorLine: 1);
  } on YamlException catch (e) {
    return (map: null, errorLine: e.span!.start.line + 2);
  }
}

/// Returns the lines of [lfText] without their `\n` and with no final empty
/// line.
List<String> lfLinesOf(String lfText) {
  final lines = lfText.isEmpty ? <String>[] : lfText.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  return lines;
}

/// What a doc's file lines say, computed once when the index refreshes.
///
/// A check reads these instead of parsing the text again.
final class LineFacts {
  const new({
    required this.links,
    required this.sectionLines,
    required this.sectionCounts,
    required this.fenced,
    required this.lineCount,
    required this.charCount,
    required this.frontmatterErrorLine,
  });

  /// Computes the facts of [lfText], its [doc] at [docPath], and the
  /// [sectionCounts] of each section of [doc].
  ///
  /// [lfText] is the file text with LF line ends, and [frontmatterErrorLine]
  /// is `FrontmatterYaml.errorLine` of its frontmatter.
  factory of({
    required String lfText,
    required String docPath,
    required Doc doc,
    required List<SectionCounts> sectionCounts,
    required int? frontmatterErrorLine,
  }) {
    final prefix = doc.frontmatter == null
        ? ''
        : lfText.substring(0, lfText.length - doc.afterFrontmatter.length);
    final bodyStart = _lineCount(prefix);
    final whole = scanText(lfText);
    return LineFacts(
      links: linkPlacesOf(
        doc.afterFrontmatter,
        docPath: docPath,
        firstLine: bodyStart + 1,
      ),
      sectionLines: [for (final i in doc.sectionLineIndexes) bodyStart + i + 1],
      sectionCounts: sectionCounts,
      fenced: _fencedRanges(doc.afterFrontmatter, bodyStart),
      lineCount: _lineCount(lfText, breaks: whole.breaks),
      charCount: lfText.length - whole.pairs,
      frontmatterErrorLine: frontmatterErrorLine,
    );
  }

  /// Reads the facts [toJson] wrote, with the section counts the section rows
  /// kept.
  factory fromJson(
    Map<String, Object?> json, {
    required List<SectionCounts> sectionCounts,
  }) {
    final fenced = json['fenced']! as List<Object?>;
    return LineFacts(
      links: [
        for (final place
            in (json['links']! as List<Object?>).cast<List<Object?>>())
          (
            target: place[0]! as String,
            line: place[1]! as int,
            shown: place[2]! as String,
          ),
      ],
      sectionLines: (json['sections']! as List<Object?>).cast<int>(),
      sectionCounts: sectionCounts,
      fenced: [
        for (final range in fenced.cast<List<Object?>>())
          (first: range[0]! as int, last: range[1]! as int),
      ],
      lineCount: json['lines']! as int,
      charCount: json['chars']! as int,
      frontmatterErrorLine: json['yaml_error'] as int?,
    );
  }

  /// The doc links that resolve to another `.md` doc, in source order.
  final List<LinkPlace> links;

  /// The header line of each section, in the order of `Doc.sections`.
  final List<int> sectionLines;

  /// The line and code point counts of each section's text, in the order of
  /// [sectionLines].
  ///
  /// The section rows store these, so [toJson] leaves them out.
  final List<SectionCounts> sectionCounts;

  /// The runs of fenced code lines, fence lines included, in file order.
  final List<LineRange> fenced;

  /// The lines of the LF text.
  final int lineCount;

  /// The code points of the LF text.
  final int charCount;

  /// The line the YAML parser names, 1 when the frontmatter is no mapping.
  ///
  /// Null when the frontmatter is valid or absent.
  final int? frontmatterErrorLine;

  /// Whether file [line] (1-based) is fenced code content or a fence line.
  ///
  /// False for a line the file does not have.
  bool isFenced(int line) {
    var low = 0;
    var high = fenced.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final range = fenced[mid];
      if (line < range.first) {
        high = mid - 1;
      } else if (line > range.last) {
        low = mid + 1;
      } else {
        return true;
      }
    }
    return false;
  }

  /// Returns the facts as JSON values, apart from [sectionCounts].
  Map<String, Object?> toJson() => {
    'links': [
      for (final place in links) [place.target, place.line, place.shown],
    ],
    'sections': sectionLines,
    'fenced': [
      for (final range in fenced) [range.first, range.last],
    ],
    'lines': lineCount,
    'chars': charCount,
    'yaml_error': frontmatterErrorLine,
  };
}

/// Returns the lines of [text], using [breaks] as its `\n` count when known.
int _lineCount(String text, {int? breaks}) {
  if (text.isEmpty) return 0;
  final count = breaks ?? scanText(text).breaks;
  return text.endsWith('\n') ? count : count + 1;
}

/// Returns the runs of fenced lines of [body], the lines from file line
/// `bodyStart + 1` on.
///
/// A body with no line that opens with a backtick or a tilde holds no fence,
/// so its lines are never split.
List<LineRange> _fencedRanges(String body, int bodyStart) {
  if (!_mayHoldFence(body)) return const [];
  final fenced = fencedLines(lfLinesOf(body));
  final ranges = <LineRange>[];
  int? first;
  for (var i = 0; i < fenced.length; i++) {
    if (fenced[i]) {
      first ??= bodyStart + i + 1;
    } else if (first != null) {
      ranges.add((first: first, last: bodyStart + i));
      first = null;
    }
  }
  if (first != null) {
    ranges.add((first: first, last: bodyStart + fenced.length));
  }
  return ranges;
}

/// Whether a line of [text] opens, after up to three spaces, with a backtick
/// or a tilde: the least a fence line needs.
bool _mayHoldFence(String text) {
  var start = 0;
  while (start < text.length) {
    var at = start;
    while (at < text.length &&
        at - start < 3 &&
        text.codeUnitAt(at) == _space) {
      at++;
    }
    if (at < text.length) {
      final unit = text.codeUnitAt(at);
      if (unit == _backtick || unit == _tilde) return true;
    }
    final end = text.indexOf('\n', start);
    if (end < 0) return false;
    start = end + 1;
  }
  return false;
}
