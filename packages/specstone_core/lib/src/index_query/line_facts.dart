import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/index_query/section_counts.dart';
import 'package:yaml/yaml.dart';

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
    required this.bodyLine,
    required this.titleLine,
    required this.sectionLines,
    required this.sectionCounts,
    required this.fenced,
    required this.lineCount,
    required this.charCount,
    required this.frontmatterErrorLine,
  });

  /// Computes the facts of [lfText], its [doc], and the [sectionCounts] of
  /// each section of [doc].
  ///
  /// [lfText] is the file text with LF line ends, and [frontmatterErrorLine]
  /// is `FrontmatterYaml.errorLine` of its frontmatter.
  factory of({
    required String lfText,
    required Doc doc,
    required List<SectionCounts> sectionCounts,
    required int? frontmatterErrorLine,
  }) {
    final lines = lfLinesOf(lfText);
    final bodyStart = doc.frontmatter == null
        ? 0
        : lines.length - _lineCount(doc.afterFrontmatter);
    final titleIndex = doc.titleLineIndex;
    return LineFacts(
      bodyLine: bodyStart + 1,
      titleLine: titleIndex == null ? null : bodyStart + titleIndex + 1,
      sectionLines: [for (final i in doc.sectionLineIndexes) bodyStart + i + 1],
      sectionCounts: sectionCounts,
      fenced: _rangesOf(fencedLines(lines.sublist(bodyStart)), bodyStart),
      lineCount: lines.length,
      charCount: lfText.runes.length,
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
      bodyLine: json['body']! as int,
      titleLine: json['title'] as int?,
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

  /// The line the doc body starts on: after the frontmatter, else 1.
  final int bodyLine;

  /// The line of the first `# ` head line, or null without one.
  final int? titleLine;

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
    'body': bodyLine,
    'title': titleLine,
    'sections': sectionLines,
    'fenced': [
      for (final range in fenced) [range.first, range.last],
    ],
    'lines': lineCount,
    'chars': charCount,
    'yaml_error': frontmatterErrorLine,
  };
}

int _lineCount(String text) {
  if (text.isEmpty) return 0;
  final breaks = '\n'.allMatches(text).length;
  return text.endsWith('\n') ? breaks : breaks + 1;
}

/// Returns the runs of true in [fenced] as file lines, where the first entry
/// is file line `offset + 1`.
List<LineRange> _rangesOf(List<bool> fenced, int offset) {
  final ranges = <LineRange>[];
  int? first;
  for (var i = 0; i < fenced.length; i++) {
    if (fenced[i]) {
      first ??= offset + i + 1;
    } else if (first != null) {
      ranges.add((first: first, last: offset + i));
      first = null;
    }
  }
  if (first != null) ranges.add((first: first, last: offset + fenced.length));
  return ranges;
}
