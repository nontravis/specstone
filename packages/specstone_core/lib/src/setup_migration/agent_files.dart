import 'dart:convert';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/setup_migration/agent_text.g.dart';

/// The AGENT.md text, ending in one line feed, embedded from
/// `assets/agent/AGENT.md` by `tool/generate_agent_text.dart`
/// (`setup_migration/set_up_new_project/write_agent_files`).
final String agentMdText = utf8.decode(base64Decode(agentMdTextBase64));

const _projectRule = '- Run `specstone get project` before any task.\n';
const _endMarker = '<!-- END specstone -->';
const _byteOrderMark = '\uFEFF';
const _carriage = '\r';
final _beginMarker = RegExp(r'^<!-- BEGIN specstone v\d+\.\d+\.\d+ -->$');

String _beginLine(String cliVersion) =>
    '<!-- BEGIN specstone v$cliVersion -->\n';

/// Returns the block of `CLAUDE.md` and `GEMINI.md`: both imports, as LF text.
///
/// [agentMdPath] and [projectDocPath] read from the instruction file's folder.
String importBlock({
  required String cliVersion,
  required String agentMdPath,
  required String projectDocPath,
}) =>
    '${_beginLine(cliVersion)}'
    '@$agentMdPath\n'
    '@$projectDocPath\n'
    '$_endMarker\n';

/// Returns the block of `AGENTS.md` and Copilot's file: the rules inline.
String inlineBlock({required String cliVersion}) =>
    '${_beginLine(cliVersion)}$agentMdText$_projectRule$_endMarker\n';

/// Returns the whole `.cursor/rules/specstone.mdc`, frontmatter included.
String cursorRulesText({required String cliVersion}) =>
    '---\nalwaysApply: true\n---\n${inlineBlock(cliVersion: cliVersion)}';

/// The Specstone marker lines of a text, numbered from 1.
///
/// `firstMarkerLine` is the first BEGIN or END line, or the opening line of
/// the code fence still open at the end, null without either.
/// `openFenceLine` is that fence's opening line alone, null when every fence
/// closes.
typedef MarkerScan = ({
  int? beginLine,
  int? endLine,
  int? firstMarkerLine,
  int? openFenceLine,
  bool isMalformed,
});

/// Finds the marker lines of [text] outside fenced code.
///
/// A marker is a whole line: BEGIN with a `X.Y.Z` version, or END. The text
/// is malformed unless it holds no marker, or one BEGIN and then one END, and
/// closes every code fence: a block after an open fence would sit in code.
/// An open fence makes `firstMarkerLine` the fence's opening line, whatever
/// the markers hold.
MarkerScan scanMarkers(String text) {
  final lines = _lineStrings(text);
  if (lines.first.startsWith(_byteOrderMark)) {
    lines[0] = lines.first.substring(1);
  }
  final scan = blockScan(lines);
  final begins = <int>[];
  final ends = <int>[];
  for (var index = 0; index < lines.length; index++) {
    if (scan.fenced[index]) continue;
    if (_beginMarker.hasMatch(lines[index])) begins.add(index + 1);
    if (lines[index] == _endMarker) ends.add(index + 1);
  }
  final openFenceLine = _openFenceLine(lines, scan.openFence);
  final isWellFormed =
      openFenceLine == null &&
      ((begins.isEmpty && ends.isEmpty) ||
          (begins.length == 1 &&
              ends.length == 1 &&
              begins.first < ends.first));
  final markers = [
    ?openFenceLine,
    if (openFenceLine == null) ...begins,
    if (openFenceLine == null) ...ends,
  ]..sort();
  return (
    beginLine: begins.firstOrNull,
    endLine: ends.firstOrNull,
    firstMarkerLine: markers.firstOrNull,
    openFenceLine: openFenceLine,
    isMalformed: !isWellFormed,
  );
}

/// Returns the 1-based line of the fence still open at the end, or null.
int? _openFenceLine(List<String> lines, String? openFence) {
  if (openFence == null) return null;
  for (var index = lines.length - 1; index >= 0; index--) {
    if (lines[index] == openFence &&
        blockScan(lines.sublist(0, index)).openFence == null) {
      return index + 1;
    }
  }
  return null;
}

/// Returns [fileText] holding [block], or null when it already does.
///
/// Appends [block] when [fileText] holds none and replaces the existing one in
/// place when its body differs; the BEGIN line's version and the line endings
/// do not count in the compare. Writes the file's own line ending and keeps a
/// leading UTF-8 BOM and every byte outside the block.
///
/// Throws [ArgumentError] when the markers of [fileText] are malformed.
String? upsertBlock(String fileText, String block) {
  final scan = scanMarkers(fileText);
  if (scan.isMalformed) {
    throw ArgumentError.value(
      scan.firstMarkerLine,
      'firstMarkerLine',
      'malformed markers or an unclosed code fence',
    );
  }
  final eol = LineEnding.of(fileText);
  final beginLine = scan.beginLine;
  final endLine = scan.endLine;
  if (beginLine == null || endLine == null) {
    return _append(fileText, eol.apply(block), eol);
  }
  final lines = fileText.split('\n');
  final currentBody = _bodyOf(_lineStrings(fileText), beginLine, endLine);
  final newBody = _bodyOf(_lineStrings(block), 1, _lineStrings(block).length);
  if (_sameLines(currentBody, newBody)) return null;
  return _replace(lines, beginLine, endLine, block, eol: eol);
}

String _append(String fileText, String block, LineEnding eol) {
  if (fileText.isEmpty || fileText.endsWith('\n')) return '$fileText$block';
  return '$fileText${eol.apply('\n')}$block';
}

String _replace(
  List<String> lines,
  int beginLine,
  int endLine,
  String block, {
  required LineEnding eol,
}) {
  final bom = lines[beginLine - 1].startsWith(_byteOrderMark)
      ? _byteOrderMark
      : '';
  // The END line keeps its own ending, so a file without a final line feed
  // gets none.
  final lastEndsInCarriage = lines[endLine - 1].endsWith(_carriage);
  final isCrlf = eol == LineEnding.crlf;
  final blockLines = _lineStrings(block);
  final lastIndex = blockLines.length - 1;
  final replacement = [
    for (var index = 0; index < blockLines.length; index++)
      _withEnding(
        '${index == 0 ? bom : ''}${blockLines[index]}',
        hasCarriage: index == lastIndex ? lastEndsInCarriage : isCrlf,
      ),
  ];
  return [
    ...lines.sublist(0, beginLine - 1),
    ...replacement,
    ...lines.sublist(endLine),
  ].join('\n');
}

String _withEnding(String line, {required bool hasCarriage}) =>
    hasCarriage ? '$line$_carriage' : line;

/// Splits [text] into its lines without line ends; a final line feed adds none.
List<String> _lineStrings(String text) {
  final lines = toLf(text).split('\n');
  if (lines.length > 1 && lines.last.isEmpty) lines.removeLast();
  return lines;
}

List<String> _bodyOf(List<String> lines, int beginLine, int endLine) =>
    lines.sublist(beginLine, endLine - 1);

bool _sameLines(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
