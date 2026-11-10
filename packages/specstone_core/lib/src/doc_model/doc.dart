import 'package:specstone_core/src/doc_model/markdown_lines.dart'
    show isThematicBreak;
import 'package:yaml/yaml.dart';

/// One frontmatter key kept as its original text, comments included.
///
/// A block with an empty [key] holds the leading frontmatter lines no key
/// owns, so no text is lost; it has no value.
final class KeyBlock {
  const new(this.key, this.text);

  /// The key as written, quotes included; empty for the keyless block.
  final String key;

  /// The YAML name of the key: a quoted key decoded, a bare key as written.
  ///
  /// Empty for the keyless block. A quoted key that does not decode to a
  /// string keeps its spelling.
  String get name {
    if (key.isEmpty || !(key.startsWith('"') || key.startsWith("'"))) {
      return key;
    }
    try {
      final decoded = loadYaml(key);
      return decoded is String ? decoded : key;
    } on YamlException {
      return key;
    }
  }

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
    required this.text,
    required this.frontmatter,
    required this.head,
    required this.title,
    required this.titleLineIndex,
    required this.sections,
    required this.sectionLineIndexes,
    required this.afterFrontmatter,
    required this.hasUnclosedFence,
  });

  /// Parses [text] into its frontmatter, head, and sections.
  static Doc parse(String text) {
    final lines = _splitLines(text);
    final close = _frontmatterClose(lines);
    final bodyLines = lines.sublist(close < 0 ? 0 : close + 1);
    final scan = _scan(bodyLines);
    return Doc._(
      text: text,
      frontmatter: close < 0 ? null : _keyBlocks(lines.sublist(1, close)),
      head: scan.head,
      title: scan.title,
      titleLineIndex: scan.titleLineIndex,
      sections: scan.sections,
      sectionLineIndexes: scan.sectionLineIndexes,
      afterFrontmatter: bodyLines.join(),
      hasUnclosedFence: scan.unclosedFence,
    );
  }

  /// The text [parse] read.
  final String text;

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

  /// The index of each section's header line among the lines of
  /// [afterFrontmatter], one per [sections] element, in the same order.
  final List<int> sectionLineIndexes;

  /// The text after the closing `---` line, or the whole text without
  /// frontmatter.
  final String afterFrontmatter;

  /// Whether the text after the frontmatter ends inside a fenced code block.
  ///
  /// Such a fence swallows every later `##` line, so no section after it is
  /// seen.
  final bool hasUnclosedFence;

  /// The text after `# ` on the first such head line, as written.
  final String? title;

  /// The index of the [title] line among the lines of [afterFrontmatter].
  ///
  /// Null exactly when [title] is null.
  final int? titleLineIndex;

  /// The head text after the title line, or the whole head without a title
  /// line, in the form of a section body.
  ///
  /// Trailing blank lines are dropped and leading ones stay; empty when
  /// nothing but blank lines follows. Text before the title line is neither
  /// title nor lead.
  String get lead {
    final at = titleLineIndex;
    final text = _splitLines(head).skip(at == null ? 0 : at + 1).join();
    if (text.trim().isEmpty) return '';
    return text.endsWith('\n') ? text : '$text\n';
  }

  /// Whether the `draft` key holds the YAML boolean `true`.
  ///
  /// A value that is not valid YAML counts as false.
  bool get isDraft {
    final block = frontmatter?.where((b) => b.name == 'draft').firstOrNull;
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

/// Whether [line], without its line ending, is a `##` header line as
/// [Doc.parse] reads it outside fenced code.
bool isSectionHeaderLine(String line) => _sectionHeader.hasMatch(line);

/// Whether [line], without its line ending, is a `# ` title line as
/// [Doc.parse] reads it outside fenced code.
bool isTitleLine(String line) => line.startsWith('# ');

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
({
  String head,
  String? title,
  int? titleLineIndex,
  List<Section> sections,
  List<int> sectionLineIndexes,
  bool unclosedFence,
})
_scan(List<String> lines) {
  final fence = _BlockTracker();
  final headLines = <String>[];
  final sections = <Section>[];
  final sectionLineIndexes = <int>[];
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

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final bare = _withoutNewline(line);
    final fenced = fence.consume(bare);
    if (!fenced && isSectionHeaderLine(bare)) {
      closeSection();
      headerLine = bare;
      sectionLineIndexes.add(i);
    } else if (headerLine != null) {
      bodyLines.add(line);
    } else {
      if (!fenced && title == null && isTitleLine(bare)) {
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
    sectionLineIndexes: sectionLineIndexes,
    unclosedFence: fence.isOpen,
  );
}

String _joinWithoutTrailingBlank(List<String> lines) {
  var end = lines.length;
  while (end > 0 && _isBlank(lines[end - 1])) {
    end--;
  }
  return lines.sublist(0, end).join();
}

/// Returns, per line of [lines] (each without its line end), whether it is
/// fenced code content or a fence delimiter.
List<bool> fencedLines(List<String> lines) => blockScan(lines).fenced;

/// Reads [lines] (each without its line end) the way [Doc.parse] does,
/// starting outside any fence.
///
/// Per line, `fenced` is whether it is fenced code content or a fence
/// delimiter, and `continuesParagraph` whether it is the next line of the
/// paragraph above it (GFM). `openFence` is the delimiter line of a fence
/// still open after the last line, or null when every fence closed.
({List<bool> fenced, List<bool> continuesParagraph, String? openFence})
blockScan(List<String> lines) {
  final tracker = _BlockTracker();
  final fenced = List.filled(lines.length, false);
  final continues = List.filled(lines.length, false);
  for (var i = 0; i < lines.length; i++) {
    fenced[i] = tracker.consume(lines[i]);
    continues[i] = tracker.continuesParagraph;
  }
  return (
    fenced: fenced,
    continuesParagraph: continues,
    openFence: tracker.openingLine,
  );
}

/// Reads [lines] as [blockScan] does and reports, per line, the fence it
/// opens or closes.
///
/// `opens` holds the info word of the fence a line opens (empty without one),
/// null on any other line; `closes` is whether a line is a closing delimiter.
/// A fence a container ends has no closing line.
({List<bool> fenced, List<String?> opens, List<bool> closes}) fenceScan(
  List<String> lines,
) {
  final tracker = _BlockTracker();
  final fenced = List.filled(lines.length, false);
  final opens = List<String?>.filled(lines.length, null);
  final closes = List.filled(lines.length, false);
  for (var i = 0; i < lines.length; i++) {
    fenced[i] = tracker.consume(lines[i]);
    opens[i] = tracker.openedInfo;
    closes[i] = tracker.closedFence;
  }
  return (fenced: fenced, opens: opens, closes: closes);
}

const _tab = 0x09;
const _space = 0x20;
const _closeParen = 0x29;
const _star = 0x2A;
const _plus = 0x2B;
const _dash = 0x2D;
const _dot = 0x2E;
const _digitZero = 0x30;
const _digitNine = 0x39;
const _lessThan = 0x3C;
const _equals = 0x3D;
const _quoteMarker = 0x3E;
const _hash = 0x23;
const _backtick = 0x60;
const _tilde = 0x7E;

const _tabStop = 4;

/// The columns a block may sit past its container's content column (GFM).
const _maxIndent = 3;
const _minFenceRun = 3;
const _maxHeadingLevel = 6;
const _maxOrderedDigits = 9;

/// The most spaces after a list marker that still lead to the item content.
const _maxMarkerGap = 4;

/// The start of a GFM HTML block that can interrupt a paragraph (kinds 1-6).
final _htmlBlockStart = RegExp(
  r'<(?:(?:pre|script|style|textarea)(?:\s|>|$)|!--|\?|![a-z]|!\[CDATA\[|'
  '/?(?:address|article|aside|base|basefont|blockquote|body|caption|center|'
  'col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|'
  'footer|form|frame|frameset|h1|h2|h3|h4|h5|h6|head|header|hr|html|iframe|'
  'legend|li|link|main|menu|menuitem|nav|noframes|ol|optgroup|option|p|param|'
  'section|source|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul)'
  r'(?:\s|>|/>|$))',
  caseSensitive: false,
);

/// Tracks fenced code blocks and paragraphs the way GitHub Flavored Markdown
/// reads them, inside block quotes and list items included.
///
/// A fence opens with three or more backticks or tildes at most 3 columns
/// past its container's content, and closes with the same character, at
/// least as many, or where its container ends; an unclosed fence runs to the
/// end. A `##` header line outside a fence ends every container.
final class _BlockTracker {
  final _containers = <_Container>[];
  _Fence? _fence;
  var _inParagraph = false;
  var _continues = false;
  String? _openedInfo;
  var _closedFence = false;

  /// The info word of the fence the line fed last opened, else null.
  String? get openedInfo => _openedInfo;

  /// Whether the line fed last closed a fence.
  bool get closedFence => _closedFence;

  /// The delimiter line of the open fence, or null outside a fence.
  String? get openingLine => _fence?.openingLine;

  /// Whether the lines fed so far end inside an open fence.
  bool get isOpen => _fence != null;

  /// Whether the line fed last is the next line of the paragraph above it.
  bool get continuesParagraph => _continues;

  /// Feeds one [line]; returns whether it is fence content or a delimiter.
  bool consume(String line) {
    _continues = false;
    _openedInfo = null;
    _closedFence = false;
    final text = _expandTabs(line);
    var column = 0;
    var matched = 0;
    for (final container in _containers) {
      final next = container.continueAt(text, column);
      if (next == null) break;
      column = next;
      matched++;
    }
    final fence = _fence;
    if (fence != null) {
      if (matched == _containers.length) {
        if (fence.closesOn(text, column)) {
          _fence = null;
          _closedFence = true;
        }
        return true;
      }
      // A fence takes no lazy line, so it ends with its container.
      _fence = null;
      _closeContainers(matched);
    }
    final fenced = _readBlocks(line, text, column, matched);
    if (!fenced && _containers.isNotEmpty && isSectionHeaderLine(line)) {
      _closeContainers(0);
    }
    return fenced;
  }

  /// Reads the containers and the leaf block [text] starts at [column], past
  /// the first [matched] containers it continues.
  bool _readBlocks(String line, String text, int column, int matched) {
    var at = column;
    var paragraphOpen = _inParagraph && matched == _containers.length;
    var opened = false;
    for (;;) {
      final start = _containerStart(text, at, paragraphOpen: paragraphOpen);
      if (start == null) break;
      if (!opened) _closeContainers(matched);
      opened = true;
      _containers.add(start.container);
      _inParagraph = paragraphOpen = false;
      at = start.column;
    }
    if (!opened && matched < _containers.length) {
      if (_inParagraph && _isLazyLine(text, at)) {
        _continues = true;
        return false;
      }
      _closeContainers(matched);
    }
    return _readLeaf(line, text, at);
  }

  /// Reads the leaf block [text] starts at [column]; returns whether it opens
  /// a fence.
  bool _readLeaf(String line, String text, int column) {
    final start = _indentEnd(text, column);
    if (start >= text.length) {
      _inParagraph = false;
      return false;
    }
    // Indented code, or the next line of the open paragraph.
    if (start - column > _maxIndent) {
      _continues = _inParagraph;
      return false;
    }
    final run = _fenceRunAt(text, start);
    if (run > 0) {
      _fence = _Fence(
        marker: text.codeUnitAt(start),
        run: run,
        openingLine: line,
      );
      _openedInfo = _infoWordAt(text, start + run);
      _inParagraph = false;
      return true;
    }
    final endsParagraph =
        _interruptsParagraph(text, start) ||
        (_inParagraph && _isSetextUnderline(text, start));
    _continues = _inParagraph && !endsParagraph;
    _inParagraph = !endsParagraph;
    return false;
  }

  void _closeContainers(int kept) {
    if (kept < _containers.length) {
      _containers.length = kept;
      _inParagraph = false;
    }
  }
}

/// Returns the first word of the info string that starts at [from].
String _infoWordAt(String text, int from) {
  var start = from;
  while (start < text.length && _isBlankUnit(text.codeUnitAt(start))) {
    start++;
  }
  var end = start;
  while (end < text.length && !_isBlankUnit(text.codeUnitAt(end))) {
    end++;
  }
  return text.substring(start, end);
}

bool _isBlankUnit(int unit) => unit == _space || unit == _tab;

/// An open fenced code block.
final class _Fence {
  const new({
    required this.marker,
    required this.run,
    required this.openingLine,
  });

  final int marker;
  final int run;

  /// The delimiter line as written.
  final String openingLine;

  /// Whether [text], past its containers at [column], closes this fence.
  bool closesOn(String text, int column) {
    final start = _indentEnd(text, column);
    if (start - column > _maxIndent || start >= text.length) return false;
    if (text.codeUnitAt(start) != marker) return false;
    final end = _runEnd(text, start, marker);
    return end - start >= run && _indentEnd(text, end) >= text.length;
  }
}

/// A block that holds other blocks: a block quote or a list item.
sealed class _Container {
  const new();

  /// Returns the column past this container on [text], from [column], or null
  /// when [text] does not continue it.
  int? continueAt(String text, int column);
}

final class _Quote extends _Container {
  const new();

  @override
  int? continueAt(String text, int column) => _afterQuoteMarker(text, column);
}

final class _ListItem extends _Container {
  const new(this.contentColumn);

  final int contentColumn;

  /// A blank line, or one indented to [contentColumn], continues the item.
  @override
  int? continueAt(String text, int column) {
    final start = _indentEnd(text, column);
    if (start >= text.length) return column;
    return start >= contentColumn ? contentColumn : null;
  }
}

/// Returns the container [text] starts at [column], with its content column,
/// or null when none starts there.
///
/// With [paragraphOpen], only a bullet or `1.` or `1)` with content starts a
/// list item, so a paragraph line such as `2. x` stays in its paragraph.
({_Container container, int column})? _containerStart(
  String text,
  int column, {
  required bool paragraphOpen,
}) {
  final quoteColumn = _afterQuoteMarker(text, column);
  if (quoteColumn != null) {
    return (container: const _Quote(), column: quoteColumn);
  }
  final itemColumn = _listItemColumn(
    text,
    column,
    paragraphOpen: paragraphOpen,
  );
  if (itemColumn == null) return null;
  return (container: _ListItem(itemColumn), column: itemColumn);
}

/// Returns the column after the `>` marker, and one space after it, that
/// [text] holds at most 3 columns past [column], or null.
int? _afterQuoteMarker(String text, int column) {
  final start = _indentEnd(text, column);
  if (start - column > _maxIndent || start >= text.length) return null;
  if (text.codeUnitAt(start) != _quoteMarker) return null;
  final after = start + 1;
  final hasSpace = after < text.length && text.codeUnitAt(after) == _space;
  return hasSpace ? after + 1 : after;
}

/// Returns the content column of the list item [text] starts past [column],
/// or null when it starts none.
int? _listItemColumn(String text, int column, {required bool paragraphOpen}) {
  final start = _indentEnd(text, column);
  if (start - column > _maxIndent || start >= text.length) return null;
  final markerEnd = _listMarkerEnd(text, start);
  if (markerEnd == null || isThematicBreak(text.substring(start))) return null;
  final contentStart = _indentEnd(text, markerEnd);
  final isEmpty = contentStart >= text.length;
  if (paragraphOpen && (isEmpty || !_startsAtOne(text, start, markerEnd))) {
    return null;
  }
  final gap = contentStart - markerEnd;
  return isEmpty || gap > _maxMarkerGap ? markerEnd + 1 : contentStart;
}

/// Returns the index after the bullet or ordered marker at [start], when a
/// space or the line end follows it, or null.
int? _listMarkerEnd(String text, int start) {
  final first = text.codeUnitAt(start);
  var end = start + 1;
  if (first != _dash && first != _plus && first != _star) {
    end = _digitsEnd(text, start);
    final digits = end - start;
    if (digits == 0 || digits > _maxOrderedDigits || end >= text.length) {
      return null;
    }
    final delimiter = text.codeUnitAt(end);
    if (delimiter != _dot && delimiter != _closeParen) return null;
    end++;
  }
  return end >= text.length || text.codeUnitAt(end) == _space ? end : null;
}

/// Whether the marker in `[start, markerEnd)` is a bullet or numbers 1.
bool _startsAtOne(String text, int start, int markerEnd) {
  final first = text.codeUnitAt(start);
  if (first == _dash || first == _plus || first == _star) return true;
  return int.parse(text.substring(start, markerEnd - 1)) == 1;
}

/// Whether [text] from [column] is the next line of an open paragraph that
/// sits in containers the line does not continue (a GFM lazy line).
bool _isLazyLine(String text, int column) {
  final start = _indentEnd(text, column);
  if (start >= text.length) return false;
  if (start - column > _maxIndent) return true;
  return _fenceRunAt(text, start) == 0 && !_interruptsParagraph(text, start);
}

/// Whether the leaf at [start] ends an open paragraph, or opens no paragraph:
/// an ATX heading, a thematic break, or an HTML block start.
bool _interruptsParagraph(String text, int start) =>
    _isAtxHeading(text, start) ||
    isThematicBreak(text.substring(start)) ||
    (text.codeUnitAt(start) == _lessThan &&
        _htmlBlockStart.matchAsPrefix(text, start) != null);

/// Whether [text] from [start] is a run of `=` or of `-` with only spaces
/// after it, which turns the paragraph above it into a heading.
bool _isSetextUnderline(String text, int start) {
  final marker = text.codeUnitAt(start);
  if (marker != _equals && marker != _dash) return false;
  return _indentEnd(text, _runEnd(text, start, marker)) >= text.length;
}

/// Returns the length of the fence opening run at [start], or 0 when none.
///
/// A backtick fence whose info string holds a backtick is no fence.
int _fenceRunAt(String text, int start) {
  final marker = text.codeUnitAt(start);
  if (marker != _backtick && marker != _tilde) return 0;
  final end = _runEnd(text, start, marker);
  if (end - start < _minFenceRun) return 0;
  if (marker == _backtick && text.indexOf('`', end) >= 0) return 0;
  return end - start;
}

bool _isAtxHeading(String text, int start) {
  final level = _runEnd(text, start, _hash) - start;
  final end = start + level;
  return level >= 1 &&
      level <= _maxHeadingLevel &&
      (end >= text.length || text.codeUnitAt(end) == _space);
}

/// Returns the first index at or after [from] that holds no space.
int _indentEnd(String text, int from) {
  var i = from;
  while (i < text.length && text.codeUnitAt(i) == _space) {
    i++;
  }
  return i;
}

int _runEnd(String text, int start, int unit) {
  var i = start;
  while (i < text.length && text.codeUnitAt(i) == unit) {
    i++;
  }
  return i;
}

int _digitsEnd(String text, int start) {
  var i = start;
  while (i < text.length) {
    final unit = text.codeUnitAt(i);
    if (unit < _digitZero || unit > _digitNine) break;
    i++;
  }
  return i;
}

/// Returns [line] with each tab widened to the next 4-column tab stop.
String _expandTabs(String line) {
  if (!line.contains('\t')) return line;
  final out = StringBuffer();
  var column = 0;
  for (final unit in line.codeUnits) {
    if (unit == _tab) {
      final width = _tabStop - column % _tabStop;
      out.write(' ' * width);
      column += width;
    } else {
      out.writeCharCode(unit);
      column++;
    }
  }
  return out.toString();
}
