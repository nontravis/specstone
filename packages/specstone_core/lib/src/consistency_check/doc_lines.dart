import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:yaml/yaml.dart';

/// One frontmatter list item or scalar with its source line.
///
/// `text` is the item's source text, its span.
typedef YamlEntry = ({Object? value, int line, String text});

final _sectionHeader = RegExp(r'^ {0,3}##(?:[ \t]|$)');
final _fenceOpen = RegExp(r'^ {0,3}(`{3,}|~{3,})(.*)$');
final _fenceClose = RegExp(r'^ {0,3}(`{3,}|~{3,})[ \t]*$');

/// The 1-based file lines of a doc's title, sections, and frontmatter items.
final class DocLines {
  new _({
    required this.lines,
    required this.charCount,
    required this.titleLine,
    required this.sectionLines,
    required YamlNode? frontmatter,
    required this.frontmatterErrorLine,
  }) : _frontmatter = frontmatter;

  /// Reads [text], a file's decoded text with any line ends.
  factory of(String text) {
    final lf = toLf(text);
    final lines = lf.isEmpty ? <String>[] : lf.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    final doc = Doc.parse(lf);
    final bodyStart = doc.frontmatter == null
        ? 0
        : lines.length - _lineCount(doc.afterFrontmatter);
    final titleIndex = doc.titleLineIndex;
    final sectionLines = _sectionLines(lines, bodyStart);
    assert(
      sectionLines.length == doc.sections.length,
      'section lines disagree with Doc.parse',
    );
    final yaml = _parseFrontmatter(
      doc.frontmatter == null ? null : lines,
      bodyStart,
    );
    return DocLines._(
      lines: lines,
      charCount: lf.runes.length,
      titleLine: titleIndex == null ? null : bodyStart + titleIndex + 1,
      sectionLines: sectionLines,
      frontmatter: yaml.node,
      frontmatterErrorLine: yaml.errorLine,
    );
  }

  /// The LF lines without their `\n`.
  final List<String> lines;

  /// The code points of the LF text.
  final int charCount;

  /// The line of the first `# ` head line, or null without one.
  final int? titleLine;

  /// The header line of each section, in the order of `Doc.sections`.
  final List<int> sectionLines;

  /// The line the YAML parser names, 1 when the frontmatter is no mapping.
  ///
  /// Null when the frontmatter is valid or absent.
  final int? frontmatterErrorLine;

  final YamlNode? _frontmatter;

  /// The line of frontmatter [key], or null when it is absent.
  int? keyLine(String key) {
    final entry = _keyEntry(key);
    return entry == null ? null : _lineOf(entry.key);
  }

  /// Each item of the list value of [key], or its one scalar, with lines.
  ///
  /// Empty when [key] is absent.
  List<YamlEntry> entriesOf(String key) {
    final value = _keyEntry(key)?.value;
    if (value == null) return const [];
    final items = value is YamlList ? value.nodes : [value];
    return [
      for (final item in items)
        (value: item.value, line: _lineOf(item), text: item.span.text),
    ];
  }

  MapEntry<YamlNode, YamlNode>? _keyEntry(String key) {
    final frontmatter = _frontmatter;
    if (frontmatter is! YamlMap) return null;
    for (final entry in frontmatter.nodes.entries) {
      final name = entry.key;
      if (name is YamlNode && name.value == key) {
        return MapEntry(name, entry.value);
      }
    }
    return null;
  }
}

// The frontmatter text starts on file line 2, and YAML lines start at 0.
int _lineOf(YamlNode node) => node.span.start.line + 2;

int _lineCount(String text) {
  if (text.isEmpty) return 0;
  final breaks = '\n'.allMatches(text).length;
  return text.endsWith('\n') ? breaks : breaks + 1;
}

({YamlNode? node, int? errorLine}) _parseFrontmatter(
  List<String>? lines,
  int bodyStart,
) {
  if (lines == null) return (node: null, errorLine: null);
  final source = lines.sublist(1, bodyStart - 1).map((l) => '$l\n').join();
  try {
    final node = loadYamlNode(source);
    if (node is YamlMap) return (node: node, errorLine: null);
    // An empty or comment-only block is no key, not a malformed one.
    if (node is YamlScalar && node.value == null) {
      return (node: null, errorLine: null);
    }
    return (node: null, errorLine: 1);
  } on YamlException catch (e) {
    return (node: null, errorLine: e.span!.start.line + 2);
  }
}

List<int> _sectionLines(List<String> lines, int bodyStart) {
  final result = <int>[];
  String? fence;
  for (var i = bodyStart; i < lines.length; i++) {
    final line = lines[i];
    if (fence == null) {
      final open = _fenceOpen.firstMatch(line);
      if (open != null) {
        fence = open.group(1);
      } else if (_sectionHeader.hasMatch(line)) {
        result.add(i + 1);
      }
    } else {
      final close = _fenceClose.firstMatch(line)?.group(1);
      if (close != null &&
          close[0] == fence[0] &&
          close.length >= fence.length) {
        fence = null;
      }
    }
  }
  return result;
}
