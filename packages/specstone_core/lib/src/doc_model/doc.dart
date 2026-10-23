import 'package:yaml/yaml.dart';

/// One frontmatter key kept as its original text, comments included.
///
/// A block with an empty [key] holds the leading frontmatter lines no key
/// owns, so no text is lost; it has no value.
final class KeyBlock {
  const new(this.key, this.text);

  /// The key as written, quotes included; empty for the keyless block.
  final String key;

  /// Every line of the block, each ending in `\n`, comments included.
  final String text;

  /// The text after `<key>:`, comment lines dropped, trimmed.
  ///
  /// Empty for the keyless block.
  String get valueText {
    if (key.isEmpty) return '';
    final lines = _splitLines(text);
    final keyIndex = lines.indexWhere((line) => !_isTrivia(line));
    if (keyIndex < 0) return '';
    final keyMatch = _keyLine.firstMatch(lines[keyIndex]);
    if (keyMatch == null) return '';
    final buffer = StringBuffer(lines[keyIndex].substring(keyMatch.end));
    for (final line in lines.skip(keyIndex + 1)) {
      if (!line.trimLeft().startsWith('#')) buffer.write(line);
    }
    return buffer.toString().trim();
  }
}

/// One `##` section of a doc.
final class Section {
  const new(this.headerLine, this.body);

  /// The `##` line as written, without its line ending.
  final String headerLine;

  /// Every line after the header line up to the next section header.
  ///
  /// Trailing blank lines are spacing, not body.
  final String body;

  /// The text after `##`, trimmed.
  String get headerText => headerLine.trimLeft().substring(2).trim();
}

/// A doc split into frontmatter, head, and `##` sections, losing no text.
///
/// The input is LF text; line endings are the caller's concern.
final class Doc {
  new _({
    required this.frontmatter,
    required this.head,
    required this.title,
    required this.titleLineIndex,
    required this.sections,
    required this.afterFrontmatter,
  });

  /// Parses [text] into its frontmatter, head, and sections.
  static Doc parse(String text) {
    final lines = _splitLines(text);
    final close = _frontmatterClose(lines);
    final bodyLines = lines.sublist(close < 0 ? 0 : close + 1);
    final scan = _scan(bodyLines);
    return Doc._(
      frontmatter: close < 0 ? null : _keyBlocks(lines.sublist(1, close)),
      head: scan.head,
      title: scan.title,
      titleLineIndex: scan.titleLineIndex,
      sections: scan.sections,
      afterFrontmatter: bodyLines.join(),
    );
  }

  /// The frontmatter key blocks in file order, or null without frontmatter.
  ///
  /// A keyless block, when present, comes first.
  final List<KeyBlock>? frontmatter;

  /// The text between the frontmatter and the first section header.
  ///
  /// Trailing blank lines are dropped.
  final String head;

  /// The sections in file order.
  final List<Section> sections;

  /// The text after the closing `---` line, or the whole text without
  /// frontmatter.
  final String afterFrontmatter;

  /// The text after `# ` on the first such head line, as written.
  final String? title;

  /// The index of the [title] line among the lines of [afterFrontmatter].
  ///
  /// Null exactly when [title] is null.
  final int? titleLineIndex;

  /// Whether the `draft` key holds the YAML boolean `true`.
  ///
  /// A value that is not valid YAML counts as false.
  bool get isDraft {
    final block = frontmatter?.where((b) => b.key == 'draft').firstOrNull;
    if (block == null) return false;
    try {
      return loadYaml(block.valueText) == true;
    } on YamlException {
      return false;
    }
  }
}

/// A column-0 key line: a bare or quoted key, then a colon before a space.
final _keyLine = RegExp(
  r'''^("[^"]*"|'[^']*'|[^\s#'"\[\]{}&*!|>%@`?-].*?)[ \t]*:(?=[ \t\r\n]|$)''',
);
final _sectionHeader = RegExp(r'^ {0,3}##(?:[ \t]|$)');
final _fenceOpen = RegExp(r'^ {0,3}(`{3,}|~{3,})(.*)$');
final _fenceClose = RegExp(r'^ {0,3}(`{3,}|~{3,})[ \t]*$');

/// Splits [text] into lines, each keeping its trailing `\n` when it has one.
List<String> _splitLines(String text) {
  final lines = <String>[];
  var start = 0;
  while (start < text.length) {
    final end = text.indexOf('\n', start);
    if (end < 0) {
      lines.add(text.substring(start));
      break;
    }
    lines.add(text.substring(start, end + 1));
    start = end + 1;
  }
  return lines;
}

String _withoutNewline(String line) =>
    line.endsWith('\n') ? line.substring(0, line.length - 1) : line;

bool _isBlank(String line) => line.trim().isEmpty;

/// Whether [line] is a column-0 comment or a blank line.
bool _isTrivia(String line) => line.startsWith('#') || _isBlank(line);

/// Returns the index of the closing `---` line, or -1 without frontmatter.
int _frontmatterClose(List<String> lines) {
  if (lines.isEmpty || _withoutNewline(lines.first) != '---') return -1;
  for (var i = 1; i < lines.length; i++) {
    if (_withoutNewline(lines[i]) == '---') return i;
  }
  return -1;
}

/// Splits frontmatter [lines] into key blocks.
///
/// Column-0 comment and blank lines directly above a key line belong to that
/// key; any other line belongs to the block above; lines above the first
/// block form one keyless block.
List<KeyBlock> _keyBlocks(List<String> lines) {
  final starts = <int>[];
  final keys = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final match = _keyLine.firstMatch(lines[i]);
    if (match == null) continue;
    var start = i;
    while (start > 0 && _isTrivia(lines[start - 1])) {
      start--;
    }
    starts.add(start);
    keys.add(match.group(1)!);
  }
  if (starts.isEmpty) {
    return lines.isEmpty ? [] : [KeyBlock('', lines.join())];
  }
  return [
    if (starts.first > 0) KeyBlock('', lines.sublist(0, starts.first).join()),
    for (var i = 0; i < starts.length; i++)
      KeyBlock(
        keys[i],
        lines
            .sublist(starts[i], i + 1 < starts.length ? starts[i + 1] : null)
            .join(),
      ),
  ];
}

/// Splits [lines] into head, title, and sections outside fenced code.
({String head, String? title, int? titleLineIndex, List<Section> sections})
_scan(List<String> lines) {
  final fence = _FenceTracker();
  final headLines = <String>[];
  final sections = <Section>[];
  String? title;
  int? titleLineIndex;
  String? headerLine;
  var bodyLines = <String>[];

  void closeSection() {
    final header = headerLine;
    if (header != null) {
      sections.add(Section(header, _joinWithoutTrailingBlank(bodyLines)));
    }
    bodyLines = [];
  }

  for (final line in lines) {
    final bare = _withoutNewline(line);
    final fenced = fence.consume(bare);
    if (!fenced && _sectionHeader.hasMatch(bare)) {
      closeSection();
      headerLine = bare;
    } else if (headerLine != null) {
      bodyLines.add(line);
    } else {
      if (!fenced && title == null && bare.startsWith('# ')) {
        title = bare.substring(2);
        titleLineIndex = headLines.length;
      }
      headLines.add(line);
    }
  }
  closeSection();
  return (
    head: _joinWithoutTrailingBlank(headLines),
    title: title,
    titleLineIndex: titleLineIndex,
    sections: sections,
  );
}

String _joinWithoutTrailingBlank(List<String> lines) {
  var end = lines.length;
  while (end > 0 && _isBlank(lines[end - 1])) {
    end--;
  }
  return lines.sublist(0, end).join();
}

/// Tracks whether the scan is inside a fenced code block.
///
/// A fence opens with three or more backticks or tildes and closes with the
/// same character, at least as many; an unclosed fence runs to the end.
final class _FenceTracker {
  String? _char;
  var _length = 0;

  /// Feeds one [line]; returns whether it is fence content or a delimiter.
  bool consume(String line) {
    if (_char == null) return _open(line);
    final close = _fenceClose.firstMatch(line);
    final run = close?.group(1);
    if (run != null && run[0] == _char && run.length >= _length) {
      _char = null;
    }
    return true;
  }

  bool _open(String line) {
    final match = _fenceOpen.firstMatch(line);
    final run = match?.group(1);
    if (run == null) return false;
    final isBacktick = run[0] == '`';
    if (isBacktick && match!.group(2)!.contains('`')) return false;
    _char = run[0];
    _length = run.length;
    return true;
  }
}
